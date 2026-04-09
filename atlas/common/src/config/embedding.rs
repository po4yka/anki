use serde::Deserialize;
use strum::{Display, EnumString};

/// Supported embedding providers.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, EnumString, Display)]
#[serde(rename_all = "lowercase")]
#[strum(serialize_all = "lowercase")]
pub enum EmbeddingProviderKind {
    OpenAi,
    Google,
    FastEmbed,
    Mock,
}

/// Embedding provider settings.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EmbeddingSettings {
    pub provider: EmbeddingProviderKind,
    pub model: String,
    pub dimension: u32,
}
