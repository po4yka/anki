use serde::Deserialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ApiDeploymentKind {
    Companion,
    Cloud,
}

impl std::str::FromStr for ApiDeploymentKind {
    type Err = String;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "companion" => Ok(Self::Companion),
            "cloud" => Ok(Self::Cloud),
            other => Err(format!("expected 'companion' or 'cloud', got '{other}'")),
        }
    }
}

/// API server settings.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ApiSettings {
    pub host: String,
    pub port: u16,
    pub api_key: Option<String>,
    pub debug: bool,
    pub deployment_kind: ApiDeploymentKind,
    pub instance_id: Option<String>,
}
