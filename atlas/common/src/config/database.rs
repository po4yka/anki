/// Database bootstrap settings.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DatabaseSettings {
    pub postgres_url: String,
}
