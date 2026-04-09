# Configuration Reference

All atlas services load configuration from environment variables prefixed with `ANKIATLAS_`. Settings are validated on startup and must be explicitly set or will use documented defaults.

Configuration is loaded via `atlas/common/src/config/mod.rs` and validated to ensure all fields are valid before the application starts.

## Environment Variables

### Database

| Variable | Default | Type | Description |
|----------|---------|------|-------------|
| `ANKIATLAS_POSTGRES_URL` | `postgresql://localhost:5432/ankiatlas` | string | PostgreSQL connection URL; must start with `postgresql://` or `postgres://` |

### Job Queue

| Variable | Default | Type | Description |
|----------|---------|------|-------------|
| `ANKIATLAS_JOB_QUEUE_NAME` | `ankiatlas_jobs` | string | Queue name in PostgreSQL for async job dispatch |
| `ANKIATLAS_JOB_RESULT_TTL_SECONDS` | `86400` | u32 | Job result retention period in seconds (1 day default); must be > 0 |
| `ANKIATLAS_JOB_MAX_RETRIES` | `3` | u32 | Maximum retry attempts for failed jobs; must be > 0 |

### Embedding

| Variable | Default | Type | Description |
|----------|---------|------|-------------|
| `ANKIATLAS_EMBEDDING_PROVIDER` | `openai` | enum | Embedding provider: `openai`, `google`, `fastembed`, `mock` |
| `ANKIATLAS_EMBEDDING_MODEL` | `text-embedding-3-small` | string | Model identifier for the selected provider |
| `ANKIATLAS_EMBEDDING_DIMENSION` | `1536` | u32 | Output dimension for embeddings; must be > 0 and in valid set for provider |

**Valid embedding dimensions by provider:**

- **OpenAI**: 1536 (text-embedding-3-small), 3072 (text-embedding-3-large)
- **Google**: 384, 768, 1024, 1536, 3072 (Gemini Embedding 2 recommends 768, 1536, or 3072)
- **FastEmbed**: 384, 768, 1024
- **Mock**: any positive value

### Reranking

| Variable | Default | Type | Description |
|----------|---------|------|-------------|
| `ANKIATLAS_RERANK_ENABLED` | `false` | bool | Enable reranking in search results |
| `ANKIATLAS_RERANK_MODEL` | `cross-encoder/ms-marco-MiniLM-L-6-v2` | string | Model identifier for reranking |
| `ANKIATLAS_RERANK_TOP_N` | `50` | u32 | Number of results to rerank before selection; must be > 0 |
| `ANKIATLAS_RERANK_BATCH_SIZE` | `32` | u32 | Batch size for reranking inference; must be > 0 |

### API Server

| Variable | Default | Type | Description |
|----------|---------|------|-------------|
| `ANKIATLAS_API_HOST` | `0.0.0.0` | string | HTTP server bind address |
| `ANKIATLAS_API_PORT` | `8000` | u16 | HTTP server bind port |
| `ANKIATLAS_API_KEY` | (unset) | string | Optional API authentication key; if set, requests must include `Authorization: Bearer <key>` |
| `ANKIATLAS_DEBUG` | `false` | bool | Enable debug logging and verbose error responses |

### Anki Collection

| Variable | Default | Type | Description |
|----------|---------|------|-------------|
| `ANKIATLAS_ANKI_COLLECTION_PATH` | (unset) | string | Path to the Anki collection.anki2 file; optional, used for local indexing and sync |
| `ANKIATLAS_ANKI_MEDIA_ROOT` | (unset) | string | Path to Anki media folder; optional, used for media asset references |

## Configuration Validation

The `Settings::validate()` function enforces these constraints:

1. **PostgreSQL URL**: Must start with `postgresql://` or `postgres://`
2. **Job TTL and Retries**: Must be positive (> 0)
3. **Embedding Dimension**: Must be positive and in the valid set for the selected provider
4. **Rerank Values**: `top_n` and `batch_size` must be positive
5. **Gemini Embedding 2 (Google provider)**: Warns if dimension is not 768, 1536, or 3072; fails if dimension > 3072

Validation errors are fatal and will prevent the application from starting.

## Example .env File

```env
# Database
ANKIATLAS_POSTGRES_URL=postgresql://localhost:5432/ankiatlas

# Job Queue
ANKIATLAS_JOB_QUEUE_NAME=ankiatlas_jobs
ANKIATLAS_JOB_RESULT_TTL_SECONDS=86400
ANKIATLAS_JOB_MAX_RETRIES=3

# Embedding
ANKIATLAS_EMBEDDING_PROVIDER=openai
ANKIATLAS_EMBEDDING_MODEL=text-embedding-3-small
ANKIATLAS_EMBEDDING_DIMENSION=1536

# Reranking (optional)
ANKIATLAS_RERANK_ENABLED=false
ANKIATLAS_RERANK_MODEL=cross-encoder/ms-marco-MiniLM-L-6-v2
ANKIATLAS_RERANK_TOP_N=50
ANKIATLAS_RERANK_BATCH_SIZE=32

# API Server
ANKIATLAS_API_HOST=0.0.0.0
ANKIATLAS_API_PORT=8000
ANKIATLAS_DEBUG=false

# Anki Collection (optional)
ANKIATLAS_ANKI_COLLECTION_PATH=/Users/user/Library/Application Support/Anki2/User 1/collection.anki2
ANKIATLAS_ANKI_MEDIA_ROOT=/Users/user/Library/Application Support/Anki2/User 1/collection.media
```

## Loading Configuration

Configuration is loaded in this order:

1. Environment variables from the system
2. Variables from `.env` file (if present, via `dotenvy`)
3. Defaults (see above)
4. Validation (fails if any constraint is violated)

Example in Rust:

```rust
use atlas_common::config::Settings;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let config = Settings::load()?;
    
    // Extract subsystem settings
    let db_config = config.database();
    let job_config = config.jobs();
    let api_config = config.api();
    let embedding_config = config.embedding();
    let rerank_config = config.rerank();
    
    Ok(())
}
```

## Common Configurations

### Local Development

```env
ANKIATLAS_POSTGRES_URL=postgresql://localhost:5432/ankiatlas
ANKIATLAS_EMBEDDING_PROVIDER=mock
ANKIATLAS_DEBUG=true
ANKIATLAS_API_PORT=8000
```

### Testing with FastEmbed

```env
ANKIATLAS_POSTGRES_URL=postgresql://localhost:5432/ankiatlas_test
ANKIATLAS_EMBEDDING_PROVIDER=fastembed
ANKIATLAS_EMBEDDING_MODEL=BAAI/bge-small-en-v1.5
ANKIATLAS_EMBEDDING_DIMENSION=384
ANKIATLAS_RERANK_ENABLED=true
```

### Production with Google Gemini

```env
ANKIATLAS_POSTGRES_URL=postgresql://prod-user:${DB_PASS}@db.example.com/ankiatlas_prod
ANKIATLAS_EMBEDDING_PROVIDER=google
ANKIATLAS_EMBEDDING_MODEL=gemini-embedding-2-preview
ANKIATLAS_EMBEDDING_DIMENSION=768
ANKIATLAS_API_PORT=443
ANKIATLAS_API_KEY=${API_KEY}
ANKIATLAS_DEBUG=false
```

## See Also

- `atlas/common/src/config/mod.rs` -- Configuration source code
- `atlas/jobs/` -- Job queue implementation details
- `atlas/search/` -- Embedding and reranking integration
- `atlas/llm/` -- LLM provider integration
