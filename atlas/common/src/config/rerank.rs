/// Reranking settings.
#[derive(Debug, Clone, PartialEq)]
pub struct RerankSettings {
    pub enabled: bool,
    pub model: String,
    pub top_n: u32,
    pub batch_size: u32,
}
