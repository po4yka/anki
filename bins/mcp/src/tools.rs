use rmcp::schemars;
use rmcp::schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::Value;

fn default_true() -> bool {
    true
}

fn default_limit() -> usize {
    10
}

fn default_max_results() -> i64 {
    20
}

fn default_min_coverage() -> i64 {
    1
}

fn default_threshold() -> f64 {
    0.92
}

fn default_max_clusters() -> usize {
    50
}

#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum OutputMode {
    #[default]
    Markdown,
    Json,
}

/// Search mode for controlling which retrieval sources are used.
#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum McpSearchMode {
    /// Use both semantic and FTS sources with RRF fusion (default).
    #[default]
    Hybrid,
    /// Use semantic (vector) search only.
    SemanticOnly,
    /// Use full-text search only.
    FtsOnly,
}

impl From<McpSearchMode> for surface_contracts::search::SearchMode {
    fn from(mode: McpSearchMode) -> Self {
        match mode {
            McpSearchMode::Hybrid => surface_contracts::search::SearchMode::Hybrid,
            McpSearchMode::SemanticOnly => surface_contracts::search::SearchMode::SemanticOnly,
            McpSearchMode::FtsOnly => surface_contracts::search::SearchMode::FtsOnly,
        }
    }
}

/// Reindex mode for MCP tool inputs (mirrors `common::ReindexMode` with JsonSchema).
#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum McpReindexMode {
    /// Only reindex notes that have changed since last index.
    #[default]
    Incremental,
    /// Force reindex all notes regardless of change status.
    Force,
}

impl From<McpReindexMode> for common::ReindexMode {
    fn from(mode: McpReindexMode) -> Self {
        match mode {
            McpReindexMode::Incremental => common::ReindexMode::Incremental,
            McpReindexMode::Force => common::ReindexMode::Force,
        }
    }
}

#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct SearchToolInput {
    #[serde(default)]
    pub output_mode: OutputMode,
    pub query: String,
    #[serde(default)]
    pub deck_names: Vec<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default = "default_limit")]
    pub limit: usize,
    #[serde(default)]
    pub search_mode: McpSearchMode,
}

#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct ChunkSearchToolInput {
    #[serde(default)]
    pub output_mode: OutputMode,
    pub query: String,
    #[serde(default)]
    pub deck_names: Vec<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default = "default_limit")]
    pub limit: usize,
}

#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct TopicsToolInput {
    #[serde(default)]
    pub output_mode: OutputMode,
    pub root_path: Option<String>,
}

#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct TopicCoverageToolInput {
    #[serde(default)]
    pub output_mode: OutputMode,
    pub topic_path: String,
    #[serde(default = "default_true")]
    pub include_subtree: bool,
}

#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct TopicGapsToolInput {
    #[serde(default)]
    pub output_mode: OutputMode,
    pub topic_path: String,
    #[serde(default = "default_min_coverage")]
    pub min_coverage: i64,
}

#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct TopicWeakNotesToolInput {
    #[serde(default)]
    pub output_mode: OutputMode,
    pub topic_path: String,
    #[serde(default = "default_max_results")]
    pub max_results: i64,
}

#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct DuplicatesToolInput {
    #[serde(default)]
    pub output_mode: OutputMode,
    #[serde(default = "default_threshold")]
    pub threshold: f64,
    #[serde(default = "default_max_clusters")]
    pub max_clusters: usize,
    #[serde(default)]
    pub deck_filter: Vec<String>,
    #[serde(default)]
    pub tag_filter: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct SyncJobToolInput {
    #[serde(default)]
    pub output_mode: OutputMode,
    pub source: String,
    #[serde(default = "default_true")]
    pub run_migrations: bool,
    #[serde(default = "default_true")]
    pub index: bool,
    #[serde(default)]
    pub reindex_mode: McpReindexMode,
}

#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct IndexJobToolInput {
    #[serde(default)]
    pub output_mode: OutputMode,
    #[serde(default)]
    pub reindex_mode: McpReindexMode,
}

#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct JobStatusToolInput {
    #[serde(default)]
    pub output_mode: OutputMode,
    pub job_id: String,
}

#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct JobCancelToolInput {
    #[serde(default)]
    pub output_mode: OutputMode,
    pub job_id: String,
}

#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct GenerateToolInput {
    #[serde(default)]
    pub output_mode: OutputMode,
    pub file_path: String,
}

#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct ValidateToolInput {
    #[serde(default)]
    pub output_mode: OutputMode,
    pub file_path: String,
    #[serde(default)]
    pub quality: bool,
}

#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct ObsidianSyncToolInput {
    #[serde(default)]
    pub output_mode: OutputMode,
    pub vault_path: String,
    #[serde(default)]
    pub source_dirs: Vec<String>,
    #[serde(default = "default_true")]
    pub dry_run: bool,
}

#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct TagAuditToolInput {
    #[serde(default)]
    pub output_mode: OutputMode,
    pub file_path: String,
    #[serde(default)]
    pub fix: bool,
}

#[derive(Debug, Clone, Serialize, JsonSchema)]
pub struct SearchResultView {
    pub note_id: i64,
    pub rrf_score: f64,
    pub semantic_score: Option<f64>,
    pub fts_score: Option<f64>,
    pub rerank_score: Option<f64>,
    pub headline: Option<String>,
    pub sources: Vec<String>,
    pub match_modality: Option<String>,
    pub match_chunk_kind: Option<String>,
    pub match_source_field: Option<String>,
    pub match_asset_rel_path: Option<String>,
}

#[derive(Debug, Clone, Serialize, JsonSchema)]
pub struct SearchToolResult {
    pub query: String,
    pub total_results: usize,
    pub lexical_mode: String,
    pub lexical_fallback_used: bool,
    pub rerank_applied: bool,
    pub query_suggestions: Vec<String>,
    pub autocomplete_suggestions: Vec<String>,
    pub results: Vec<SearchResultView>,
}

#[derive(Debug, Clone, Serialize, JsonSchema)]
pub struct ChunkSearchResultView {
    pub note_id: i64,
    pub chunk_id: String,
    pub chunk_kind: String,
    pub modality: String,
    pub source_field: Option<String>,
    pub asset_rel_path: Option<String>,
    pub mime_type: Option<String>,
    pub preview_label: Option<String>,
    pub score: f64,
}

#[derive(Debug, Clone, Serialize, JsonSchema)]
pub struct ChunkSearchToolResult {
    pub query: String,
    pub total_results: usize,
    pub results: Vec<ChunkSearchResultView>,
}

#[derive(Debug, Clone, Serialize, JsonSchema)]
pub struct TopicsToolResult {
    pub root_path: Option<String>,
    pub topic_count: usize,
    pub topics: Value,
}

#[derive(Debug, Clone, Serialize, JsonSchema)]
pub struct TopicCoverageToolResult {
    pub topic_path: String,
    pub found: bool,
    pub coverage: Option<Value>,
}

#[derive(Debug, Clone, Serialize, JsonSchema)]
pub struct TopicGapsToolResult {
    pub topic_path: String,
    pub min_coverage: i64,
    pub gaps: Value,
}

#[derive(Debug, Clone, Serialize, JsonSchema)]
pub struct TopicWeakNotesToolResult {
    pub topic_path: String,
    pub max_results: i64,
    pub notes: Value,
}

#[derive(Debug, Clone, Serialize, JsonSchema)]
pub struct DuplicatesToolResult {
    pub threshold: f64,
    pub max_clusters: usize,
    pub clusters: Value,
    pub stats: Value,
}

#[derive(Debug, Clone, Serialize, JsonSchema)]
pub struct JobAcceptedToolResult {
    pub job_id: String,
    pub job_type: String,
    pub status: String,
    pub poll_hint: String,
    pub cancel_hint: String,
}

#[derive(Debug, Clone, Serialize, JsonSchema)]
pub struct JobStatusToolResult {
    pub job_id: String,
    pub job_type: String,
    pub status: String,
    pub progress: f64,
    pub message: Option<String>,
    pub result: Option<Value>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, JsonSchema)]
pub struct WorkflowToolResult {
    pub path: String,
    pub summary: String,
    pub data: Value,
}

#[derive(Debug, Clone, Serialize, JsonSchema)]
pub struct ToolError {
    pub error: String,
    pub message: String,
    pub details: Option<String>,
}

// =================== Notetype tools ===================

#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct ListNotetypesToolInput {
    #[serde(default)]
    pub output_mode: OutputMode,
}

#[derive(Debug, Clone, Serialize, JsonSchema)]
pub struct NotetypeSummary {
    pub id: i64,
    pub name: String,
    pub kind: String,
    pub field_count: usize,
    pub template_count: usize,
}

#[derive(Debug, Clone, Serialize, JsonSchema)]
pub struct ListNotetypesToolResult {
    pub total: usize,
    pub notetypes: Vec<NotetypeSummary>,
}

#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct GetNotetypeToolInput {
    #[serde(default)]
    pub output_mode: OutputMode,
    pub notetype_id: Option<i64>,
    pub notetype_name: Option<String>,
}

#[derive(Debug, Clone, Serialize, JsonSchema)]
pub struct FieldDetail {
    pub ord: u32,
    pub name: String,
    pub sticky: bool,
    pub rtl: bool,
    pub plain_text: bool,
    pub font_name: String,
    pub font_size: u32,
    pub description: String,
    pub exclude_from_search: bool,
    pub prevent_deletion: bool,
}

#[derive(Debug, Clone, Serialize, JsonSchema)]
pub struct TemplateDetail {
    pub ord: u32,
    pub name: String,
    pub q_format: String,
    pub a_format: String,
    pub q_format_browser: String,
    pub a_format_browser: String,
    pub target_deck_id: i64,
}

#[derive(Debug, Clone, Serialize, JsonSchema)]
pub struct NotetypeDetailToolResult {
    pub id: i64,
    pub name: String,
    pub kind: String,
    pub css: String,
    pub sort_field_idx: u32,
    pub fields: Vec<FieldDetail>,
    pub templates: Vec<TemplateDetail>,
}

#[derive(Debug, Clone, Serialize, JsonSchema)]
pub struct MutationToolResult {
    pub notetype_id: i64,
    pub notetype_name: String,
    pub message: String,
}

#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct FieldSpec {
    pub name: String,
    pub ord: Option<u32>,
    #[serde(default)]
    pub sticky: Option<bool>,
    #[serde(default)]
    pub rtl: Option<bool>,
    #[serde(default)]
    pub plain_text: Option<bool>,
    #[serde(default)]
    pub font_name: Option<String>,
    #[serde(default)]
    pub font_size: Option<u32>,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub exclude_from_search: Option<bool>,
    #[serde(default)]
    pub prevent_deletion: Option<bool>,
}

#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct TemplateSpec {
    pub name: String,
    pub ord: Option<u32>,
    pub q_format: String,
    pub a_format: String,
    #[serde(default)]
    pub q_format_browser: Option<String>,
    #[serde(default)]
    pub a_format_browser: Option<String>,
    #[serde(default)]
    pub target_deck_id: Option<i64>,
}

#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct CreateNotetypeToolInput {
    #[serde(default)]
    pub output_mode: OutputMode,
    pub name: String,
    /// One of: "basic", "basic_and_reversed", "basic_optional_reversed", "basic_typing", "cloze", "image_occlusion"
    pub stock_kind: Option<String>,
    /// One of: "normal", "cloze". Used only when stock_kind is not set.
    #[serde(default)]
    pub kind: Option<String>,
    #[serde(default)]
    pub fields: Option<Vec<FieldSpec>>,
    #[serde(default)]
    pub templates: Option<Vec<TemplateSpec>>,
    #[serde(default)]
    pub css: Option<String>,
}

#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct UpdateNotetypeToolInput {
    #[serde(default)]
    pub output_mode: OutputMode,
    pub notetype_id: i64,
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub css: Option<String>,
    #[serde(default)]
    pub kind: Option<String>,
    #[serde(default)]
    pub sort_field_idx: Option<u32>,
    #[serde(default)]
    pub fields: Option<Vec<FieldSpec>>,
    #[serde(default)]
    pub templates: Option<Vec<TemplateSpec>>,
}

#[derive(Debug, Clone, Deserialize, JsonSchema)]
pub struct DeleteNotetypeToolInput {
    #[serde(default)]
    pub output_mode: OutputMode,
    pub notetype_id: i64,
}
