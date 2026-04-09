/// API server settings.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ApiSettings {
    pub host: String,
    pub port: u16,
    pub api_key: Option<String>,
    pub debug: bool,
}
