/// Job runtime settings.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct JobSettings {
    pub postgres_url: String,
    pub queue_name: String,
    pub result_ttl_seconds: u32,
    pub max_retries: u32,
}
