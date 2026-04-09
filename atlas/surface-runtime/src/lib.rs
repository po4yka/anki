mod contracts;
pub mod error;
mod service_facades;
pub mod services;
mod services_builder;
pub mod workflows;

pub use error::SurfaceError;
pub use services::{
    AnalyticsFacade, BridgeServicesConfig, BuildSurfaceServicesOptions, SearchFacade,
    SurfaceServices, build_surface_services, build_surface_services_from_bridge_config,
};
pub use workflows::{
    GeneratePreview, GeneratePreviewService, IndexExecutionSummary, IndexExecutor, IndexingService,
    ObsidianScanPreview, ObsidianScanService, QualityCheck, SurfaceOperation, SurfaceProgressEvent,
    SurfaceProgressSink, SyncExecutionHandle, SyncExecutionService, SyncExecutionSummary,
    TagAuditEntry, TagAuditService, TagAuditSummary, ValidationService, ValidationSummary,
};
