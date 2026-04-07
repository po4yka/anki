use std::path::PathBuf;
use std::sync::Arc;

use crate::collection::CollectionFacade;
use common::logging::{LoggingConfig, init_global_logging};
use jobs::types::{IndexJobPayload, SyncJobPayload};
use rmcp::handler::server::{router::tool::ToolRouter, wrapper::Parameters};
use rmcp::model::{
    Annotated, GetPromptRequestParams, GetPromptResult, Implementation, ListPromptsResult,
    ListResourceTemplatesResult, ListResourcesResult, PaginatedRequestParams, Prompt,
    PromptArgument, PromptMessage, PromptMessageRole, RawResource, RawResourceTemplate,
    ReadResourceRequestParams, ReadResourceResult, ResourceContents, ServerCapabilities,
    ServerInfo,
};
use rmcp::service::RequestContext;
use rmcp::{ErrorData, RoleServer, ServerHandler, ServiceExt, tool, tool_handler, tool_router};
use serde_json::Value;
use surface_contracts::search::{ChunkSearchRequest, SearchFilterInput, SearchRequest};
use surface_runtime::{BuildSurfaceServicesOptions, SurfaceError, SurfaceServices};

use crate::formatters;
use crate::handlers::{error_result, success_result};
use crate::tools::{
    ChunkSearchResultView, ChunkSearchToolInput, ChunkSearchToolResult, CreateNotetypeToolInput,
    DeleteNotetypeToolInput, DuplicatesToolInput, DuplicatesToolResult, GenerateToolInput,
    GetNotetypeToolInput, IndexJobToolInput, JobAcceptedToolResult, JobCancelToolInput,
    JobStatusToolInput, JobStatusToolResult, ListNotetypesToolInput, ListNotetypesToolResult,
    MutationToolResult, ObsidianSyncToolInput, SearchResultView, SearchToolInput, SearchToolResult,
    SyncJobToolInput, TagAuditToolInput, ToolError, TopicCoverageToolInput,
    TopicCoverageToolResult, TopicGapsToolInput, TopicGapsToolResult, TopicWeakNotesToolInput,
    TopicWeakNotesToolResult, TopicsToolInput, TopicsToolResult, UpdateNotetypeToolInput,
    ValidateToolInput, WorkflowToolResult,
};

#[derive(Clone)]
pub struct AnkiAtlasServer {
    services: Arc<SurfaceServices>,
    collection: Option<Arc<CollectionFacade>>,
    tool_router: ToolRouter<Self>,
}

impl AnkiAtlasServer {
    pub fn new(services: Arc<SurfaceServices>, collection: Option<Arc<CollectionFacade>>) -> Self {
        Self {
            services,
            collection,
            tool_router: Self::tool_router(),
        }
    }

    pub fn name(&self) -> &str {
        "anki-atlas"
    }

    pub fn version(&self) -> &str {
        env!("CARGO_PKG_VERSION")
    }

    pub fn tool_count(&self) -> usize {
        self.tool_router.list_all().len()
    }

    pub fn tool_names(&self) -> Vec<String> {
        self.tool_router
            .list_all()
            .into_iter()
            .map(|tool| tool.name.into_owned())
            .collect()
    }

    fn tool_error(code: &str, message: impl Into<String>, details: Option<String>) -> ToolError {
        ToolError {
            error: code.to_string(),
            message: message.into(),
            details,
        }
    }

    fn surface_error(error: SurfaceError) -> ToolError {
        match error {
            SurfaceError::Unsupported(message) => Self::tool_error("unsupported", message, None),
            SurfaceError::PathNotFound(path) => Self::tool_error(
                "not_found",
                format!("path not found: {}", path.display()),
                None,
            ),
            SurfaceError::NotFound(message) => Self::tool_error("not_found", message, None),
            SurfaceError::InvalidInput(message) => Self::tool_error("invalid_input", message, None),
            SurfaceError::Database(error) => {
                Self::tool_error("database_unavailable", error.to_string(), None)
            }
            SurfaceError::VectorStore(error) => {
                Self::tool_error("vector_store_unavailable", error.to_string(), None)
            }
            SurfaceError::Provider(message) => Self::tool_error("provider_error", message, None),
            other => Self::tool_error("internal_error", other.to_string(), None),
        }
    }

    fn col_facade(&self) -> Result<Arc<CollectionFacade>, rmcp::ErrorData> {
        self.collection.clone().ok_or_else(|| {
            rmcp::ErrorData::new(
                rmcp::model::ErrorCode::INTERNAL_ERROR,
                "ANKIATLAS_ANKI_COLLECTION_PATH is not configured",
                None,
            )
        })
    }
}

#[allow(clippy::field_reassign_with_default, clippy::manual_async_fn)]
#[tool_handler(router = self.tool_router)]
impl ServerHandler for AnkiAtlasServer {
    fn get_info(&self) -> ServerInfo {
        let mut info = ServerInfo::new(
            ServerCapabilities::builder()
                .enable_tools()
                .enable_prompts()
                .enable_resources()
                .build(),
        );
        info.server_info = Implementation::new(self.name(), self.version());
        info.instructions = Some(
            "Search and inspect anki-atlas data. Browse resources for taxonomy and stats. \
             Use prompts for common workflows. Sync/index writes are exposed only as async jobs."
                .to_string(),
        );
        info
    }

    fn list_resources(
        &self,
        _request: Option<PaginatedRequestParams>,
        _context: RequestContext<RoleServer>,
    ) -> impl std::future::Future<Output = Result<ListResourcesResult, ErrorData>> + Send + '_ {
        let mut result = ListResourcesResult::default();
        result.resources = vec![
            Annotated::new(
                RawResource::new("anki://taxonomy", "Topic Taxonomy")
                    .with_description("Full topic taxonomy tree as JSON")
                    .with_mime_type("application/json"),
                None,
            ),
            Annotated::new(
                RawResource::new("anki://stats", "Collection Stats")
                    .with_description("Card counts, coverage summary, and index status")
                    .with_mime_type("application/json"),
                None,
            ),
        ];
        std::future::ready(Ok(result))
    }

    fn list_resource_templates(
        &self,
        _request: Option<PaginatedRequestParams>,
        _context: RequestContext<RoleServer>,
    ) -> impl std::future::Future<Output = Result<ListResourceTemplatesResult, ErrorData>> + Send + '_
    {
        let mut result = ListResourceTemplatesResult::default();
        result.resource_templates = vec![Annotated::new(
            RawResourceTemplate::new("anki://taxonomy/{path}", "Topic Coverage")
                .with_description("Coverage metrics for a specific topic path"),
            None,
        )];
        std::future::ready(Ok(result))
    }

    fn read_resource(
        &self,
        request: ReadResourceRequestParams,
        _context: RequestContext<RoleServer>,
    ) -> impl std::future::Future<Output = Result<ReadResourceResult, ErrorData>> + Send + '_ {
        async move {
            let uri = request.uri.as_str();
            let make_result = |json: String, u: &str| {
                ReadResourceResult::new(vec![
                    ResourceContents::text(json, u).with_mime_type("application/json"),
                ])
            };
            match uri {
                "anki://taxonomy" => {
                    let tree = self
                        .services
                        .analytics
                        .get_taxonomy_tree(None)
                        .await
                        .map_err(|e| ErrorData::internal_error(e.to_string(), None))?;
                    let json = serde_json::to_string_pretty(&tree)
                        .map_err(|e| ErrorData::internal_error(e.to_string(), None))?;
                    Ok(make_result(json, uri))
                }
                "anki://stats" => {
                    let stats = serde_json::json!({
                        "note_count": sqlx::query_scalar::<_, i64>(
                            "SELECT COUNT(*) FROM notes WHERE deleted_at IS NULL"
                        )
                        .fetch_one(&self.services.db)
                        .await
                        .unwrap_or(0),
                        "card_count": sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM cards")
                            .fetch_one(&self.services.db)
                            .await
                            .unwrap_or(0),
                        "topic_count": sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM topics")
                            .fetch_one(&self.services.db)
                            .await
                            .unwrap_or(0),
                    });
                    let json = serde_json::to_string_pretty(&stats)
                        .map_err(|e| ErrorData::internal_error(e.to_string(), None))?;
                    Ok(make_result(json, uri))
                }
                _ if uri.starts_with("anki://taxonomy/") => {
                    let path = uri
                        .strip_prefix("anki://taxonomy/")
                        .unwrap_or("")
                        .to_string();
                    let coverage = self
                        .services
                        .analytics
                        .get_coverage(path.clone(), true)
                        .await
                        .map_err(|e| ErrorData::internal_error(e.to_string(), None))?;
                    let json = serde_json::to_string_pretty(&coverage)
                        .map_err(|e| ErrorData::internal_error(e.to_string(), None))?;
                    Ok(make_result(json, uri))
                }
                _ => Err(ErrorData::resource_not_found(
                    "resource_not_found",
                    Some(serde_json::json!({"uri": uri})),
                )),
            }
        }
    }

    fn list_prompts(
        &self,
        _request: Option<PaginatedRequestParams>,
        _context: RequestContext<RoleServer>,
    ) -> impl std::future::Future<Output = Result<ListPromptsResult, ErrorData>> + Send + '_ {
        fn prompt_arg(name: &str, desc: &str, required: bool) -> PromptArgument {
            let mut arg = PromptArgument::new(name);
            arg.description = Some(desc.to_string());
            arg.required = Some(required);
            arg
        }

        let mut result = ListPromptsResult::default();
        result.prompts = vec![
            Prompt::new(
                "generate_cards",
                Some("Generate Anki flashcards from a topic"),
                Some(vec![
                    prompt_arg("topic", "Topic to generate cards for", true),
                    prompt_arg("count", "Number of cards (default: 5)", false),
                ]),
            ),
            Prompt::new(
                "find_gaps",
                Some("Find knowledge coverage gaps in a topic area"),
                Some(vec![prompt_arg("topic", "Topic path to analyze", true)]),
            ),
            Prompt::new(
                "review_card",
                Some("Review and improve an existing card"),
                Some(vec![prompt_arg(
                    "query",
                    "Card content or search query",
                    true,
                )]),
            ),
            Prompt::new(
                "explain_topic",
                Some("Explain a topic with related concepts"),
                Some(vec![prompt_arg("topic", "Topic to explain", true)]),
            ),
        ];
        std::future::ready(Ok(result))
    }

    fn get_prompt(
        &self,
        request: GetPromptRequestParams,
        _context: RequestContext<RoleServer>,
    ) -> impl std::future::Future<Output = Result<GetPromptResult, ErrorData>> + Send + '_ {
        async move {
            let args = request.arguments.unwrap_or_default();
            let arg_str = |key: &str, default: &str| -> String {
                args.get(key)
                    .and_then(|v| v.as_str())
                    .unwrap_or(default)
                    .to_string()
            };
            match request.name.as_str() {
                "generate_cards" => {
                    let topic = arg_str("topic", "general");
                    let count = args
                        .get("count")
                        .and_then(|v| v.as_str())
                        .and_then(|c| c.parse::<usize>().ok())
                        .unwrap_or(5);
                    Ok(GetPromptResult::new(vec![PromptMessage::new_text(
                        PromptMessageRole::User,
                        format!(
                            "Generate {count} Anki flashcards about '{topic}'. \
                             Include a mix of card types: basic Q&A, cloze, and MCQ. \
                             Test understanding and reasoning, not rote memorization. \
                             Format as JSON array: card_type, front, back, tags. \
                             Cards must be bilingual (EN + RU)."
                        ),
                    )])
                    .with_description("Generate Anki flashcards"))
                }
                "find_gaps" => {
                    let topic = arg_str("topic", "programming");
                    Ok(GetPromptResult::new(vec![PromptMessage::new_text(
                        PromptMessageRole::User,
                        format!(
                            "Analyze '{topic}' for knowledge gaps. \
                             Use ankiatlas_topic_gaps to find missing subtopics. \
                             For each gap, suggest flashcard topics to fill it. \
                             Prioritize by importance."
                        ),
                    )])
                    .with_description("Find knowledge gaps"))
                }
                "review_card" => {
                    let query = arg_str("query", "");
                    Ok(GetPromptResult::new(vec![PromptMessage::new_text(
                        PromptMessageRole::User,
                        format!(
                            "Find and review the card matching '{query}'. \
                             Use ankiatlas_search to locate it. Evaluate: \
                             1) Atomic? 2) Tests reasoning? 3) Clear wording? \
                             4) Correct tags? Suggest improvements."
                        ),
                    )])
                    .with_description("Review a card"))
                }
                "explain_topic" => {
                    let topic = arg_str("topic", "");
                    Ok(GetPromptResult::new(vec![PromptMessage::new_text(
                        PromptMessageRole::User,
                        format!(
                            "Explain '{topic}' using the anki-atlas knowledge base. \
                             Use ankiatlas_search for existing cards, \
                             ankiatlas_topic_coverage for status. \
                             Present: key concepts, prerequisites, related topics, gaps."
                        ),
                    )])
                    .with_description("Explain a topic"))
                }
                _ => Err(ErrorData::invalid_params(
                    format!("unknown prompt: {}", request.name),
                    None,
                )),
            }
        }
    }
}

#[tool_router]
impl AnkiAtlasServer {
    #[tool(
        name = "ankiatlas_search",
        description = "Search notes with the shared hybrid search service"
    )]
    async fn ankiatlas_search(
        &self,
        Parameters(input): Parameters<SearchToolInput>,
    ) -> Result<rmcp::model::CallToolResult, rmcp::ErrorData> {
        let request = SearchRequest {
            query: input.query.clone(),
            filters: Some(SearchFilterInput {
                deck_names: Some(input.deck_names.clone()),
                tags: Some(input.tags.clone()),
                ..Default::default()
            }),
            limit: input.limit,
            semantic_weight: 1.0,
            fts_weight: 1.0,
            search_mode: input.search_mode.into(),
            rerank_override: None,
            rerank_top_n_override: None,
        };
        if let Err(error) = request.validate() {
            return error_result(
                input.output_mode,
                Self::tool_error("invalid_input", error, None),
            );
        }
        match self.services.search.search(&request).await {
            Ok(result) => {
                let response = SearchToolResult {
                    query: result.query,
                    total_results: result.results.len(),
                    lexical_mode: format!("{:?}", result.lexical_mode),
                    lexical_fallback_used: result.lexical_fallback_used,
                    rerank_applied: result.rerank_applied,
                    query_suggestions: result.query_suggestions,
                    autocomplete_suggestions: result.autocomplete_suggestions,
                    results: result
                        .results
                        .into_iter()
                        .map(|item| SearchResultView {
                            note_id: item.note_id.into(),
                            rrf_score: item.rrf_score,
                            semantic_score: item.semantic_score,
                            fts_score: item.fts_score,
                            rerank_score: item.rerank_score,
                            headline: item.headline,
                            sources: item.sources,
                            match_modality: item.match_modality,
                            match_chunk_kind: item.match_chunk_kind,
                            match_source_field: item.match_source_field,
                            match_asset_rel_path: item.match_asset_rel_path,
                        })
                        .collect(),
                };
                success_result(
                    input.output_mode,
                    formatters::format_search(&response),
                    &response,
                )
            }
            Err(error) => error_result(
                input.output_mode,
                Self::tool_error("search_error", error.to_string(), None),
            ),
        }
    }

    #[tool(
        name = "ankiatlas_search_chunks",
        description = "Search raw multimodal chunks with semantic retrieval only"
    )]
    async fn ankiatlas_search_chunks(
        &self,
        Parameters(input): Parameters<ChunkSearchToolInput>,
    ) -> Result<rmcp::model::CallToolResult, rmcp::ErrorData> {
        let request = ChunkSearchRequest {
            query: input.query.clone(),
            filters: Some(SearchFilterInput {
                deck_names: Some(input.deck_names.clone()),
                tags: Some(input.tags.clone()),
                ..Default::default()
            }),
            limit: input.limit,
        };
        if let Err(error) = request.validate() {
            return error_result(
                input.output_mode,
                Self::tool_error("invalid_input", error, None),
            );
        }
        match self.services.search.search_chunks(&request).await {
            Ok(result) => {
                let response = ChunkSearchToolResult {
                    query: result.query,
                    total_results: result.results.len(),
                    results: result
                        .results
                        .into_iter()
                        .map(|item| ChunkSearchResultView {
                            note_id: item.note_id.into(),
                            chunk_id: item.chunk_id,
                            chunk_kind: item.chunk_kind,
                            modality: item.modality,
                            source_field: item.source_field,
                            asset_rel_path: item.asset_rel_path,
                            mime_type: item.mime_type,
                            preview_label: item.preview_label,
                            score: item.score,
                        })
                        .collect(),
                };
                success_result(
                    input.output_mode,
                    formatters::format_chunk_search(&response),
                    &response,
                )
            }
            Err(error) => error_result(
                input.output_mode,
                Self::tool_error("search_error", error.to_string(), None),
            ),
        }
    }

    #[tool(name = "ankiatlas_topics", description = "Inspect the taxonomy tree")]
    async fn ankiatlas_topics(
        &self,
        Parameters(input): Parameters<TopicsToolInput>,
    ) -> Result<rmcp::model::CallToolResult, rmcp::ErrorData> {
        match self
            .services
            .analytics
            .get_taxonomy_tree(input.root_path.clone())
            .await
        {
            Ok(topics) => {
                let response = TopicsToolResult {
                    root_path: input.root_path,
                    topic_count: topics.len(),
                    topics: serde_json::json!(topics),
                };
                success_result(
                    input.output_mode,
                    formatters::format_topics(&response),
                    &response,
                )
            }
            Err(error) => error_result(
                input.output_mode,
                Self::tool_error("analytics_error", error.to_string(), None),
            ),
        }
    }

    #[tool(
        name = "ankiatlas_topic_coverage",
        description = "Inspect topic coverage metrics"
    )]
    async fn ankiatlas_topic_coverage(
        &self,
        Parameters(input): Parameters<TopicCoverageToolInput>,
    ) -> Result<rmcp::model::CallToolResult, rmcp::ErrorData> {
        match self
            .services
            .analytics
            .get_coverage(input.topic_path.clone(), input.include_subtree)
            .await
        {
            Ok(coverage) => {
                let response = TopicCoverageToolResult {
                    topic_path: input.topic_path,
                    found: coverage.is_some(),
                    coverage: coverage
                        .map(|value| serde_json::to_value(value).unwrap_or(Value::Null)),
                };
                success_result(
                    input.output_mode,
                    formatters::format_coverage(&response),
                    &response,
                )
            }
            Err(error) => error_result(
                input.output_mode,
                Self::tool_error("analytics_error", error.to_string(), None),
            ),
        }
    }

    #[tool(
        name = "ankiatlas_topic_gaps",
        description = "Inspect topic gap candidates"
    )]
    async fn ankiatlas_topic_gaps(
        &self,
        Parameters(input): Parameters<TopicGapsToolInput>,
    ) -> Result<rmcp::model::CallToolResult, rmcp::ErrorData> {
        match self
            .services
            .analytics
            .get_gaps(input.topic_path.clone(), input.min_coverage)
            .await
        {
            Ok(gaps) => {
                let response = TopicGapsToolResult {
                    topic_path: input.topic_path,
                    min_coverage: input.min_coverage,
                    gaps: serde_json::to_value(gaps).unwrap_or(Value::Null),
                };
                success_result(
                    input.output_mode,
                    formatters::format_gaps(&response),
                    &response,
                )
            }
            Err(error) => error_result(
                input.output_mode,
                Self::tool_error("analytics_error", error.to_string(), None),
            ),
        }
    }

    #[tool(
        name = "ankiatlas_topic_weak_notes",
        description = "List weak notes for a topic"
    )]
    async fn ankiatlas_topic_weak_notes(
        &self,
        Parameters(input): Parameters<TopicWeakNotesToolInput>,
    ) -> Result<rmcp::model::CallToolResult, rmcp::ErrorData> {
        match self
            .services
            .analytics
            .get_weak_notes(input.topic_path.clone(), input.max_results)
            .await
        {
            Ok(notes) => {
                let response = TopicWeakNotesToolResult {
                    topic_path: input.topic_path,
                    max_results: input.max_results,
                    notes: serde_json::to_value(notes).unwrap_or(Value::Null),
                };
                success_result(
                    input.output_mode,
                    formatters::format_weak_notes(&response),
                    &response,
                )
            }
            Err(error) => error_result(
                input.output_mode,
                Self::tool_error("analytics_error", error.to_string(), None),
            ),
        }
    }

    #[tool(
        name = "ankiatlas_duplicates",
        description = "Find duplicate-note clusters"
    )]
    async fn ankiatlas_duplicates(
        &self,
        Parameters(input): Parameters<DuplicatesToolInput>,
    ) -> Result<rmcp::model::CallToolResult, rmcp::ErrorData> {
        match self
            .services
            .analytics
            .find_duplicates(
                input.threshold,
                input.max_clusters,
                (!input.deck_filter.is_empty()).then(|| input.deck_filter.clone()),
                (!input.tag_filter.is_empty()).then(|| input.tag_filter.clone()),
            )
            .await
        {
            Ok((clusters, stats)) => {
                let response = DuplicatesToolResult {
                    threshold: input.threshold,
                    max_clusters: input.max_clusters,
                    clusters: serde_json::to_value(clusters).unwrap_or(Value::Null),
                    stats: serde_json::to_value(stats).unwrap_or(Value::Null),
                };
                success_result(
                    input.output_mode,
                    formatters::format_duplicates(&response),
                    &response,
                )
            }
            Err(error) => error_result(
                input.output_mode,
                Self::tool_error("analytics_error", error.to_string(), None),
            ),
        }
    }

    #[tool(name = "ankiatlas_sync_job", description = "Enqueue a sync job")]
    async fn ankiatlas_sync_job(
        &self,
        Parameters(input): Parameters<SyncJobToolInput>,
    ) -> Result<rmcp::model::CallToolResult, rmcp::ErrorData> {
        match self
            .services
            .job_manager
            .enqueue_sync_job(
                SyncJobPayload {
                    source: input.source,
                    run_migrations: input.run_migrations,
                    index: input.index,
                    reindex_mode: input.reindex_mode.into(),
                },
                None,
            )
            .await
        {
            Ok(record) => {
                let response = JobAcceptedToolResult {
                    job_id: record.job_id.clone(),
                    job_type: record.job_type.to_string(),
                    status: record.status.to_string(),
                    poll_hint: format!("call ankiatlas_job_status with job_id={}", record.job_id),
                    cancel_hint: format!("call ankiatlas_job_cancel with job_id={}", record.job_id),
                };
                success_result(
                    input.output_mode,
                    formatters::format_job_accepted(&response),
                    &response,
                )
            }
            Err(error) => error_result(
                input.output_mode,
                Self::tool_error("job_error", error.to_string(), None),
            ),
        }
    }

    #[tool(name = "ankiatlas_index_job", description = "Enqueue an index job")]
    async fn ankiatlas_index_job(
        &self,
        Parameters(input): Parameters<IndexJobToolInput>,
    ) -> Result<rmcp::model::CallToolResult, rmcp::ErrorData> {
        match self
            .services
            .job_manager
            .enqueue_index_job(
                IndexJobPayload {
                    reindex_mode: input.reindex_mode.into(),
                },
                None,
            )
            .await
        {
            Ok(record) => {
                let response = JobAcceptedToolResult {
                    job_id: record.job_id.clone(),
                    job_type: record.job_type.to_string(),
                    status: record.status.to_string(),
                    poll_hint: format!("call ankiatlas_job_status with job_id={}", record.job_id),
                    cancel_hint: format!("call ankiatlas_job_cancel with job_id={}", record.job_id),
                };
                success_result(
                    input.output_mode,
                    formatters::format_job_accepted(&response),
                    &response,
                )
            }
            Err(error) => error_result(
                input.output_mode,
                Self::tool_error("job_error", error.to_string(), None),
            ),
        }
    }

    #[tool(name = "ankiatlas_job_status", description = "Inspect a queued job")]
    async fn ankiatlas_job_status(
        &self,
        Parameters(input): Parameters<JobStatusToolInput>,
    ) -> Result<rmcp::model::CallToolResult, rmcp::ErrorData> {
        match self.services.job_manager.get_job(&input.job_id).await {
            Ok(record) => {
                let response = JobStatusToolResult {
                    job_id: record.job_id,
                    job_type: record.job_type.to_string(),
                    status: record.status.to_string(),
                    progress: record.progress,
                    message: record.message,
                    result: record
                        .result
                        .map(|value| serde_json::to_value(value).unwrap_or(Value::Null)),
                    error: record.error,
                };
                success_result(
                    input.output_mode,
                    formatters::format_job_status(&response),
                    &response,
                )
            }
            Err(error) => error_result(
                input.output_mode,
                Self::tool_error("job_error", error.to_string(), None),
            ),
        }
    }

    #[tool(
        name = "ankiatlas_job_cancel",
        description = "Request job cancellation"
    )]
    async fn ankiatlas_job_cancel(
        &self,
        Parameters(input): Parameters<JobCancelToolInput>,
    ) -> Result<rmcp::model::CallToolResult, rmcp::ErrorData> {
        match self.services.job_manager.cancel_job(&input.job_id).await {
            Ok(record) => {
                let response = JobStatusToolResult {
                    job_id: record.job_id,
                    job_type: record.job_type.to_string(),
                    status: record.status.to_string(),
                    progress: record.progress,
                    message: record.message,
                    result: record
                        .result
                        .map(|value| serde_json::to_value(value).unwrap_or(Value::Null)),
                    error: record.error,
                };
                success_result(
                    input.output_mode,
                    formatters::format_job_status(&response),
                    &response,
                )
            }
            Err(error) => error_result(
                input.output_mode,
                Self::tool_error("job_error", error.to_string(), None),
            ),
        }
    }

    #[tool(
        name = "ankiatlas_generate",
        description = "Preview note generation from a markdown file"
    )]
    async fn ankiatlas_generate(
        &self,
        Parameters(input): Parameters<GenerateToolInput>,
    ) -> Result<rmcp::model::CallToolResult, rmcp::ErrorData> {
        match self
            .services
            .generate_preview
            .preview(PathBuf::from(&input.file_path).as_path())
        {
            Ok(preview) => {
                let response = WorkflowToolResult {
                    path: input.file_path,
                    summary: format!("estimated cards: {}", preview.estimated_cards),
                    data: serde_json::to_value(preview).unwrap_or(Value::Null),
                };
                success_result(
                    input.output_mode,
                    formatters::format_workflow(&response),
                    &response,
                )
            }
            Err(error) => error_result(input.output_mode, Self::surface_error(error)),
        }
    }

    #[tool(
        name = "ankiatlas_validate",
        description = "Validate card content from a file"
    )]
    async fn ankiatlas_validate(
        &self,
        Parameters(input): Parameters<ValidateToolInput>,
    ) -> Result<rmcp::model::CallToolResult, rmcp::ErrorData> {
        match self.services.validation.validate_file(
            PathBuf::from(&input.file_path).as_path(),
            if input.quality {
                surface_runtime::QualityCheck::Include
            } else {
                surface_runtime::QualityCheck::Skip
            },
        ) {
            Ok(summary) => {
                let response = WorkflowToolResult {
                    path: input.file_path,
                    summary: format!("valid={} issues={}", summary.is_valid, summary.issues.len()),
                    data: serde_json::to_value(summary).unwrap_or(Value::Null),
                };
                success_result(
                    input.output_mode,
                    formatters::format_workflow(&response),
                    &response,
                )
            }
            Err(error) => error_result(input.output_mode, Self::surface_error(error)),
        }
    }

    #[tool(
        name = "ankiatlas_obsidian_sync",
        description = "Preview an Obsidian vault scan"
    )]
    async fn ankiatlas_obsidian_sync(
        &self,
        Parameters(input): Parameters<ObsidianSyncToolInput>,
    ) -> Result<rmcp::model::CallToolResult, rmcp::ErrorData> {
        match self.services.obsidian_scan.scan(
            PathBuf::from(&input.vault_path).as_path(),
            &input.source_dirs,
            if input.dry_run {
                common::ExecutionMode::DryRun
            } else {
                common::ExecutionMode::Execute
            },
        ) {
            Ok(summary) => {
                let response = WorkflowToolResult {
                    path: input.vault_path,
                    summary: format!(
                        "notes={} generated_cards={}",
                        summary.note_count, summary.generated_cards
                    ),
                    data: serde_json::to_value(summary).unwrap_or(Value::Null),
                };
                success_result(
                    input.output_mode,
                    formatters::format_workflow(&response),
                    &response,
                )
            }
            Err(error) => error_result(input.output_mode, Self::surface_error(error)),
        }
    }

    #[tool(
        name = "ankiatlas_tag_audit",
        description = "Validate and normalize tag files"
    )]
    async fn ankiatlas_tag_audit(
        &self,
        Parameters(input): Parameters<TagAuditToolInput>,
    ) -> Result<rmcp::model::CallToolResult, rmcp::ErrorData> {
        match self
            .services
            .tag_audit
            .audit_file(PathBuf::from(&input.file_path).as_path(), input.fix)
        {
            Ok(summary) => {
                let response = WorkflowToolResult {
                    path: input.file_path,
                    summary: format!(
                        "entries={} applied_fixes={}",
                        summary.entries.len(),
                        summary.applied_fixes
                    ),
                    data: serde_json::to_value(summary).unwrap_or(Value::Null),
                };
                success_result(
                    input.output_mode,
                    formatters::format_workflow(&response),
                    &response,
                )
            }
            Err(error) => error_result(input.output_mode, Self::surface_error(error)),
        }
    }

    #[tool(
        name = "ankiatlas_list_notetypes",
        description = "List all notetypes in the Anki collection with their names, IDs, kinds, and field/template counts"
    )]
    async fn ankiatlas_list_notetypes(
        &self,
        Parameters(input): Parameters<ListNotetypesToolInput>,
    ) -> Result<rmcp::model::CallToolResult, rmcp::ErrorData> {
        let facade = self.col_facade()?;
        match facade
            .with_col(|col| {
                let notetypes = col.get_all_notetypes()?;
                let summaries: Vec<_> = notetypes
                    .into_iter()
                    .map(|nt| crate::tools::NotetypeSummary {
                        id: nt.id.0,
                        name: nt.name.clone(),
                        kind: if nt.config.kind() == anki::notetype::NotetypeKind::Cloze {
                            "cloze".into()
                        } else {
                            "normal".into()
                        },
                        field_count: nt.fields.len(),
                        template_count: nt.templates.len(),
                    })
                    .collect();
                Ok(summaries)
            })
            .await
        {
            Ok(notetypes) => {
                let total = notetypes.len();
                let result = ListNotetypesToolResult { total, notetypes };
                success_result(
                    input.output_mode,
                    formatters::format_notetype_list(&result),
                    &result,
                )
            }
            Err(e) => error_result(
                input.output_mode,
                Self::tool_error("collection_error", e, None),
            ),
        }
    }

    #[tool(
        name = "ankiatlas_get_notetype",
        description = "Get full details of a notetype including all fields, templates (with front/back HTML), and CSS. Provide either notetype_id or notetype_name."
    )]
    async fn ankiatlas_get_notetype(
        &self,
        Parameters(input): Parameters<GetNotetypeToolInput>,
    ) -> Result<rmcp::model::CallToolResult, rmcp::ErrorData> {
        let facade = self.col_facade()?;
        let id = input.notetype_id;
        let name = input.notetype_name.clone();
        match facade
            .with_col(move |col| {
                use anki::error::OrNotFound;
                let nt = if let Some(ntid) = id {
                    col.get_notetype(anki::notetype::NotetypeId(ntid))?
                } else if let Some(ref n) = name {
                    col.get_notetype_by_name(n)?
                } else {
                    use anki::error::OrInvalid;
                    return None::<()>
                        .or_invalid("provide notetype_id or notetype_name")
                        .map(|_| unreachable!());
                };
                nt.or_not_found(0i64)
            })
            .await
        {
            Ok(nt) => {
                let result = crate::tools::NotetypeDetailToolResult {
                    id: nt.id.0,
                    name: nt.name.clone(),
                    kind: if nt.config.kind() == anki::notetype::NotetypeKind::Cloze {
                        "cloze".into()
                    } else {
                        "normal".into()
                    },
                    css: nt.config.css.clone(),
                    sort_field_idx: nt.config.sort_field_idx,
                    fields: nt
                        .fields
                        .iter()
                        .map(|f| crate::tools::FieldDetail {
                            ord: f.ord.unwrap_or(0),
                            name: f.name.clone(),
                            sticky: f.config.sticky,
                            rtl: f.config.rtl,
                            plain_text: f.config.plain_text,
                            font_name: f.config.font_name.clone(),
                            font_size: f.config.font_size,
                            description: f.config.description.clone(),
                            exclude_from_search: f.config.exclude_from_search,
                            prevent_deletion: f.config.prevent_deletion,
                        })
                        .collect(),
                    templates: nt
                        .templates
                        .iter()
                        .map(|t| crate::tools::TemplateDetail {
                            ord: t.ord.unwrap_or(0),
                            name: t.name.clone(),
                            q_format: t.config.q_format.clone(),
                            a_format: t.config.a_format.clone(),
                            q_format_browser: t.config.q_format_browser.clone(),
                            a_format_browser: t.config.a_format_browser.clone(),
                            target_deck_id: t.config.target_deck_id,
                        })
                        .collect(),
                };
                success_result(
                    input.output_mode,
                    formatters::format_notetype_detail(&result),
                    &result,
                )
            }
            Err(e) => error_result(
                input.output_mode,
                Self::tool_error("collection_error", e, None),
            ),
        }
    }

    #[tool(
        name = "ankiatlas_create_notetype",
        description = "Create a new notetype. Use stock_kind ('basic', 'basic_and_reversed', 'basic_optional_reversed', 'basic_typing', 'cloze', 'image_occlusion') to start from a built-in template, or provide custom fields and templates."
    )]
    async fn ankiatlas_create_notetype(
        &self,
        Parameters(input): Parameters<CreateNotetypeToolInput>,
    ) -> Result<rmcp::model::CallToolResult, rmcp::ErrorData> {
        let facade = self.col_facade()?;
        match facade
            .with_col(move |col| {
                use anki::notetype::{CardTemplate, NoteField, Notetype, NotetypeKind};

                let mut nt = if let Some(ref sk) = input.stock_kind {
                    use anki::notetype::all_stock_notetypes;
                    let tr = anki_i18n::I18n::template_only();
                    let mut stock = all_stock_notetypes(&tr);
                    let idx = match sk.as_str() {
                        "basic" => 0,
                        "basic_and_reversed" => 1,
                        "basic_optional_reversed" => 2,
                        "basic_typing" => 3,
                        "cloze" => 4,
                        "image_occlusion" => 5,
                        other => {
                            use anki::error::OrInvalid;
                            return None::<usize>.or_invalid(format!(
                                "unknown stock_kind '{}'; use: basic, basic_and_reversed, basic_optional_reversed, basic_typing, cloze, image_occlusion",
                                other
                            )).map(|_| unreachable!());
                        }
                    };
                    stock.remove(idx)
                } else {
                    let is_cloze = input.kind.as_deref() == Some("cloze");
                    let mut nt = Notetype::default();
                    if is_cloze {
                        nt.config.kind = NotetypeKind::Cloze as i32;
                    }
                    if let Some(ref fields) = input.fields {
                        for spec in fields {
                            let mut f = NoteField::new(&spec.name);
                            if let Some(v) = spec.sticky { f.config.sticky = v; }
                            if let Some(v) = spec.rtl { f.config.rtl = v; }
                            if let Some(v) = spec.plain_text { f.config.plain_text = v; }
                            if let Some(ref v) = spec.font_name { f.config.font_name = v.clone(); }
                            if let Some(v) = spec.font_size { f.config.font_size = v; }
                            if let Some(ref v) = spec.description { f.config.description = v.clone(); }
                            if let Some(v) = spec.exclude_from_search { f.config.exclude_from_search = v; }
                            if let Some(v) = spec.prevent_deletion { f.config.prevent_deletion = v; }
                            nt.fields.push(f);
                        }
                    }
                    if let Some(ref templates) = input.templates {
                        for spec in templates {
                            let mut t = CardTemplate::new(&spec.name, &spec.q_format, &spec.a_format);
                            if let Some(ref v) = spec.q_format_browser { t.config.q_format_browser = v.clone(); }
                            if let Some(ref v) = spec.a_format_browser { t.config.a_format_browser = v.clone(); }
                            if let Some(v) = spec.target_deck_id { t.config.target_deck_id = v; }
                            nt.templates.push(t);
                        }
                    }
                    nt
                };
                nt.name = input.name.clone();
                if let Some(ref css) = input.css {
                    nt.config.css = css.clone();
                }
                col.add_notetype(&mut nt, false)?;
                Ok((nt.id.0, nt.name.clone()))
            })
            .await
        {
            Ok((ntid, ntname)) => {
                let result = MutationToolResult {
                    notetype_id: ntid,
                    notetype_name: ntname,
                    message: "Created".into(),
                };
                success_result(input.output_mode, formatters::format_notetype_mutation(&result), &result)
            }
            Err(e) => error_result(
                input.output_mode,
                Self::tool_error("collection_error", e, None),
            ),
        }
    }

    #[tool(
        name = "ankiatlas_update_notetype",
        description = "Update an existing notetype. Only provided fields are changed. For fields/templates: provide the full desired list (existing items keep their ord, new items omit ord). Handles add/remove/reorder, CSS, name, kind, sort_field_idx."
    )]
    async fn ankiatlas_update_notetype(
        &self,
        Parameters(input): Parameters<UpdateNotetypeToolInput>,
    ) -> Result<rmcp::model::CallToolResult, rmcp::ErrorData> {
        let facade = self.col_facade()?;
        match facade
            .with_col(move |col| {
                use anki::error::OrNotFound;
                use anki::notetype::{CardTemplate, NoteField, NotetypeId, NotetypeKind};

                let ntid = NotetypeId(input.notetype_id);
                let existing = col.get_notetype(ntid)?.or_not_found(input.notetype_id)?;
                let mut nt = (*existing).clone();

                if let Some(ref name) = input.name {
                    nt.name = name.clone();
                }
                if let Some(ref css) = input.css {
                    nt.config.css = css.clone();
                }
                if let Some(ref kind) = input.kind {
                    nt.config.kind = match kind.as_str() {
                        "cloze" => NotetypeKind::Cloze as i32,
                        _ => NotetypeKind::Normal as i32,
                    };
                }
                if let Some(idx) = input.sort_field_idx {
                    nt.config.sort_field_idx = idx;
                }
                if let Some(ref field_specs) = input.fields {
                    nt.fields = field_specs
                        .iter()
                        .map(|spec| {
                            let mut f = if let Some(ord) = spec.ord {
                                existing
                                    .fields
                                    .iter()
                                    .find(|f| f.ord == Some(ord))
                                    .cloned()
                                    .unwrap_or_else(|| NoteField::new(&spec.name))
                            } else {
                                NoteField::new(&spec.name)
                            };
                            f.name = spec.name.clone();
                            if let Some(v) = spec.sticky {
                                f.config.sticky = v;
                            }
                            if let Some(v) = spec.rtl {
                                f.config.rtl = v;
                            }
                            if let Some(v) = spec.plain_text {
                                f.config.plain_text = v;
                            }
                            if let Some(ref v) = spec.font_name {
                                f.config.font_name = v.clone();
                            }
                            if let Some(v) = spec.font_size {
                                f.config.font_size = v;
                            }
                            if let Some(ref v) = spec.description {
                                f.config.description = v.clone();
                            }
                            if let Some(v) = spec.exclude_from_search {
                                f.config.exclude_from_search = v;
                            }
                            if let Some(v) = spec.prevent_deletion {
                                f.config.prevent_deletion = v;
                            }
                            f
                        })
                        .collect();
                }
                if let Some(ref tmpl_specs) = input.templates {
                    nt.templates = tmpl_specs
                        .iter()
                        .map(|spec| {
                            let mut t = if let Some(ord) = spec.ord {
                                existing
                                    .templates
                                    .iter()
                                    .find(|t| t.ord == Some(ord))
                                    .cloned()
                                    .unwrap_or_else(|| {
                                        CardTemplate::new(
                                            &spec.name,
                                            &spec.q_format,
                                            &spec.a_format,
                                        )
                                    })
                            } else {
                                CardTemplate::new(&spec.name, &spec.q_format, &spec.a_format)
                            };
                            t.name = spec.name.clone();
                            t.config.q_format = spec.q_format.clone();
                            t.config.a_format = spec.a_format.clone();
                            if let Some(ref v) = spec.q_format_browser {
                                t.config.q_format_browser = v.clone();
                            }
                            if let Some(ref v) = spec.a_format_browser {
                                t.config.a_format_browser = v.clone();
                            }
                            if let Some(v) = spec.target_deck_id {
                                t.config.target_deck_id = v;
                            }
                            t
                        })
                        .collect();
                }
                col.update_notetype(&mut nt, false)?;
                Ok((nt.id.0, nt.name.clone()))
            })
            .await
        {
            Ok((ntid, ntname)) => {
                let result = MutationToolResult {
                    notetype_id: ntid,
                    notetype_name: ntname,
                    message: "Updated".into(),
                };
                success_result(
                    input.output_mode,
                    formatters::format_notetype_mutation(&result),
                    &result,
                )
            }
            Err(e) => error_result(
                input.output_mode,
                Self::tool_error("collection_error", e, None),
            ),
        }
    }

    #[tool(
        name = "ankiatlas_delete_notetype",
        description = "Delete a notetype and ALL its associated notes and cards. This is destructive and cannot be undone from the MCP. If this is the last notetype, a stock Basic notetype will be created automatically."
    )]
    async fn ankiatlas_delete_notetype(
        &self,
        Parameters(input): Parameters<DeleteNotetypeToolInput>,
    ) -> Result<rmcp::model::CallToolResult, rmcp::ErrorData> {
        let facade = self.col_facade()?;
        let ntid_val = input.notetype_id;
        match facade
            .with_col(move |col| {
                use anki::notetype::NotetypeId;
                let ntid = NotetypeId(ntid_val);
                let name = col
                    .get_notetype(ntid)?
                    .map(|nt| nt.name.clone())
                    .unwrap_or_else(|| format!("id:{ntid_val}"));
                col.remove_notetype(ntid)?;
                Ok((ntid_val, name))
            })
            .await
        {
            Ok((ntid, ntname)) => {
                let result = MutationToolResult {
                    notetype_id: ntid,
                    notetype_name: ntname,
                    message: "Deleted".into(),
                };
                success_result(
                    input.output_mode,
                    formatters::format_notetype_mutation(&result),
                    &result,
                )
            }
            Err(e) => error_result(
                input.output_mode,
                Self::tool_error("collection_error", e, None),
            ),
        }
    }
}

pub async fn run_server() -> anyhow::Result<()> {
    let _ = init_global_logging(&LoggingConfig {
        debug: false,
        json_output: true,
    });

    let settings = common::config::Settings::load()?;
    let services = Arc::new(
        surface_runtime::build_surface_services(
            &settings,
            BuildSurfaceServicesOptions {
                enable_direct_execution: false,
            },
        )
        .await?,
    );

    let collection = settings
        .anki_collection_path
        .as_deref()
        .map(|p| Arc::new(CollectionFacade::new(std::path::PathBuf::from(p))));

    let transport = rmcp::transport::stdio();
    let server = AnkiAtlasServer::new(services, collection)
        .serve(transport)
        .await?;
    server.waiting().await?;
    Ok(())
}
