use std::env;

use serde::Deserialize;

pub mod api;
pub mod database;
pub mod embedding;
pub mod jobs;
pub mod rerank;

pub use api::{ApiDeploymentKind, ApiSettings};
pub use database::DatabaseSettings;
pub use embedding::{EmbeddingProviderKind, EmbeddingSettings};
pub use jobs::JobSettings;
pub use rerank::RerankSettings;

/// Configuration error returned by Settings::load() and Settings::validate().
#[derive(Debug)]
pub struct ConfigError(pub String);

impl std::fmt::Display for ConfigError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl std::error::Error for ConfigError {}

/// Application settings loaded from env vars prefixed `ANKIATLAS_`.
#[derive(Debug, Clone, Deserialize)]
pub struct Settings {
    pub postgres_url: String,
    pub job_queue_name: String,
    pub job_result_ttl_seconds: u32,
    pub job_max_retries: u32,
    pub embedding_provider: EmbeddingProviderKind,
    pub embedding_model: String,
    pub embedding_dimension: u32,
    pub rerank_enabled: bool,
    pub rerank_model: String,
    pub rerank_top_n: u32,
    pub rerank_batch_size: u32,
    pub api_host: String,
    pub api_port: u16,
    pub api_key: Option<String>,
    pub debug: bool,
    pub deployment_kind: ApiDeploymentKind,
    pub instance_id: Option<String>,
    pub anki_collection_path: Option<String>,
    pub anki_media_root: Option<String>,
}

impl Settings {
    /// Load settings from environment variables and optional `.env` file.
    /// Validates all fields after loading.
    pub fn load() -> Result<Self, ConfigError> {
        let settings = Self {
            postgres_url: env_or(
                "ANKIATLAS_POSTGRES_URL",
                "postgresql://localhost:5432/ankiatlas",
            ),
            job_queue_name: env_or("ANKIATLAS_JOB_QUEUE_NAME", "ankiatlas_jobs"),
            job_result_ttl_seconds: env_or("ANKIATLAS_JOB_RESULT_TTL_SECONDS", "86400")
                .parse_u32("job_result_ttl_seconds")?,
            job_max_retries: env_or("ANKIATLAS_JOB_MAX_RETRIES", "3")
                .parse_u32("job_max_retries")?,
            embedding_provider: env_or("ANKIATLAS_EMBEDDING_PROVIDER", "openai")
                .parse_enum("embedding_provider")?,
            embedding_model: env_or("ANKIATLAS_EMBEDDING_MODEL", "text-embedding-3-small"),
            embedding_dimension: env_or("ANKIATLAS_EMBEDDING_DIMENSION", "1536")
                .parse_u32("embedding_dimension")?,
            rerank_enabled: env_or("ANKIATLAS_RERANK_ENABLED", "false")
                .parse_bool("rerank_enabled")?,
            rerank_model: env_or(
                "ANKIATLAS_RERANK_MODEL",
                "cross-encoder/ms-marco-MiniLM-L-6-v2",
            ),
            rerank_top_n: env_or("ANKIATLAS_RERANK_TOP_N", "50").parse_u32("rerank_top_n")?,
            rerank_batch_size: env_or("ANKIATLAS_RERANK_BATCH_SIZE", "32")
                .parse_u32("rerank_batch_size")?,
            api_host: env_or("ANKIATLAS_API_HOST", "0.0.0.0"),
            api_port: env_or("ANKIATLAS_API_PORT", "8000")
                .parse::<u16>()
                .map_err(|e| ConfigError(format!("invalid api_port: {e}")))?,
            api_key: env::var("ANKIATLAS_API_KEY").ok().filter(|s| !s.is_empty()),
            debug: env_or("ANKIATLAS_DEBUG", "false").parse_bool("debug")?,
            deployment_kind: env_or("ANKIATLAS_DEPLOYMENT_KIND", "companion")
                .parse_enum("deployment_kind")?,
            instance_id: env::var("ANKIATLAS_INSTANCE_ID")
                .ok()
                .filter(|s| !s.is_empty()),
            anki_collection_path: env::var("ANKIATLAS_ANKI_COLLECTION_PATH")
                .ok()
                .filter(|s| !s.is_empty()),
            anki_media_root: env::var("ANKIATLAS_ANKI_MEDIA_ROOT")
                .ok()
                .filter(|s| !s.is_empty()),
        };

        settings.validate()?;
        Ok(settings)
    }

    /// Validate all fields. Called automatically by `load()`.
    pub fn validate(&self) -> Result<(), ConfigError> {
        // postgres_url must start with postgresql:// or postgres://
        if !self.postgres_url.starts_with("postgresql://")
            && !self.postgres_url.starts_with("postgres://")
        {
            return Err(ConfigError(format!(
                "postgres_url must start with postgresql:// or postgres://, got: {}",
                self.postgres_url
            )));
        }

        // embedding_dimension must be positive and in valid set (unless mock provider)
        if self.embedding_dimension == 0 {
            return Err(ConfigError(
                "embedding_dimension must be positive".to_string(),
            ));
        }
        if self.embedding_provider != EmbeddingProviderKind::Mock {
            const VALID_DIMS: [u32; 5] = [384, 768, 1024, 1536, 3072];
            let is_gemini_embedding_2 = self.embedding_provider == EmbeddingProviderKind::Google
                && self.embedding_model == "gemini-embedding-2-preview";

            if is_gemini_embedding_2 {
                if self.embedding_dimension > 3072 {
                    return Err(ConfigError(format!(
                        "embedding_dimension {} exceeds Gemini Embedding 2 maximum of 3072",
                        self.embedding_dimension
                    )));
                }

                if !matches!(self.embedding_dimension, 768 | 1536 | 3072) {
                    tracing::warn!(
                        dimension = self.embedding_dimension,
                        "Gemini Embedding 2 is configured with a non-recommended dimensionality; recommended values are 3072, 1536, or 768"
                    );
                }
            } else if !VALID_DIMS.contains(&self.embedding_dimension) {
                return Err(ConfigError(format!(
                    "embedding_dimension {} not in valid set: {VALID_DIMS:?}",
                    self.embedding_dimension
                )));
            }
        }

        // Positive integer fields
        if self.job_result_ttl_seconds == 0 {
            return Err(ConfigError(
                "job_result_ttl_seconds must be positive".to_string(),
            ));
        }
        if self.job_max_retries == 0 {
            return Err(ConfigError("job_max_retries must be positive".to_string()));
        }
        if self.rerank_top_n == 0 {
            return Err(ConfigError("rerank_top_n must be positive".to_string()));
        }
        if self.rerank_batch_size == 0 {
            return Err(ConfigError(
                "rerank_batch_size must be positive".to_string(),
            ));
        }

        Ok(())
    }

    /// Extract the database-specific settings needed to create a pool.
    pub fn database(&self) -> DatabaseSettings {
        DatabaseSettings {
            postgres_url: self.postgres_url.clone(),
        }
    }

    /// Extract the job-runtime settings needed by queue producers and workers.
    pub fn jobs(&self) -> JobSettings {
        JobSettings {
            postgres_url: self.postgres_url.clone(),
            queue_name: self.job_queue_name.clone(),
            result_ttl_seconds: self.job_result_ttl_seconds,
            max_retries: self.job_max_retries,
        }
    }

    /// Extract the API server settings needed at the HTTP boundary.
    pub fn api(&self) -> ApiSettings {
        ApiSettings {
            host: self.api_host.clone(),
            port: self.api_port,
            api_key: self.api_key.clone(),
            debug: self.debug,
            deployment_kind: self.deployment_kind,
            instance_id: self.instance_id.clone(),
        }
    }

    /// Extract the embedding settings needed by embedding provider bootstrap.
    pub fn embedding(&self) -> EmbeddingSettings {
        EmbeddingSettings {
            provider: self.embedding_provider,
            model: self.embedding_model.clone(),
            dimension: self.embedding_dimension,
        }
    }

    /// Extract the reranking settings needed by search bootstrap.
    pub fn rerank(&self) -> RerankSettings {
        RerankSettings {
            enabled: self.rerank_enabled,
            model: self.rerank_model.clone(),
            top_n: self.rerank_top_n,
            batch_size: self.rerank_batch_size,
        }
    }
}

fn env_or(key: &str, default: &str) -> String {
    env::var(key).unwrap_or_else(|_| default.to_string())
}

trait ParseHelper {
    fn parse_u32(self, field: &str) -> Result<u32, ConfigError>;
    fn parse_bool(self, field: &str) -> Result<bool, ConfigError>;
    fn parse_enum<T: std::str::FromStr>(self, field: &str) -> Result<T, ConfigError>
    where
        T::Err: std::fmt::Display;
}

impl ParseHelper for String {
    fn parse_u32(self, field: &str) -> Result<u32, ConfigError> {
        self.parse::<u32>()
            .map_err(|e| ConfigError(format!("invalid {field}: {e}")))
    }

    fn parse_bool(self, field: &str) -> Result<bool, ConfigError> {
        self.parse::<bool>()
            .map_err(|e| ConfigError(format!("invalid {field}: {e}")))
    }

    fn parse_enum<T: std::str::FromStr>(self, field: &str) -> Result<T, ConfigError>
    where
        T::Err: std::fmt::Display,
    {
        self.parse::<T>()
            .map_err(|e| ConfigError(format!("invalid {field}: {e}")))
    }
}
