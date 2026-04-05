# Atlas Features Architecture -- Phase 5

This document defines the SwiftUI screens for Atlas-powered features:
hybrid search, analytics, AI card generation, knowledge graph, and
Obsidian integration.

Target: macOS 13+. Requires Phase 3 (SwiftUI app) and Phase 4 (Atlas
integration) complete.

---

## 1. Bridge Architecture

Atlas services are async Rust functions behind trait objects, not
protobuf-based RPC. A separate `atlas_bridge` crate bridges Swift to
Atlas using JSON serialization (all DTOs derive Serialize/Deserialize).

### Why separate crate (Option B)

| Option | Verdict |
|--------|---------|
| A: Extend existing bridge | Couples Anki core to Atlas infra (PgPool, Qdrant) |
| **B: Separate atlas_bridge** | Clean separation; independent compilation; JSON native |
| C: Local REST server | Overkill for in-process communication |
| D: JSON over existing FFI | Conflates protobuf and JSON dispatch |

### atlas_bridge/src/lib.rs

```rust
#[repr(C)]
pub struct ByteBuffer { data: *mut u8, len: usize }

#[unsafe(no_mangle)]
pub extern "C" fn atlas_init(data: *const u8, len: usize) -> *mut c_void;

#[unsafe(no_mangle)]
pub extern "C" fn atlas_command(
    handle: *mut c_void,
    method: *const c_char,
    input: *const u8,
    input_len: usize,
    is_error: *mut bool,
) -> ByteBuffer;

#[unsafe(no_mangle)]
pub extern "C" fn atlas_free(handle: *mut c_void);

#[unsafe(no_mangle)]
pub extern "C" fn atlas_free_buffer(buf: ByteBuffer);
```

Internal dispatch matches method string to service call:

```rust
struct AtlasHandle {
    runtime: tokio::runtime::Runtime,
    services: SurfaceServices,
}

match method {
    "search" => services.search.search(&req),
    "get_taxonomy_tree" => services.analytics.get_taxonomy_tree(&req),
    "get_coverage" => services.analytics.get_coverage(&req),
    "get_gaps" => services.analytics.get_gaps(&req),
    "get_weak_notes" => services.analytics.get_weak_notes(&req),
    "find_duplicates" => services.analytics.find_duplicates(&req),
    "generate_preview" => services.generate_preview.preview(&req),
    "validate_card" => services.validation.validate_file(&req),
    "obsidian_scan" => services.obsidian_scan.scan(&req),
    "kg_see_also" => query::see_also(&kg_repo, note_id, limit),
    "kg_topic_neighborhood" => query::topic_neighborhood(&kg_repo, topic_id, hops),
}
```

### Swift: AtlasService actor

```swift
actor AtlasService {
    private let handle: OpaquePointer

    init(config: AtlasConfig) throws { ... }

    func command<Req: Encodable, Resp: Decodable>(
        method: String, request: Req
    ) async throws -> Resp {
        // JSON encode -> atlas_command -> JSON decode
    }

    func search(_ request: SearchRequest) async throws -> SearchResponse
    func getCoverage(topicPath: String) async throws -> TopicCoverage?
    func getGaps(topicPath: String, minCoverage: Int) async throws -> [TopicGap]
    func getWeakNotes(topicPath: String) async throws -> [WeakNote]
    func findDuplicates(threshold: Double) async throws -> DuplicatesResponse
    func generatePreview(file: URL) async throws -> GeneratePreview
    func obsidianScan(vaultPath: String) async throws -> ObsidianScanPreview
}
```

Swift DTOs are Codable structs mirroring Rust serde types. No protobuf
generation needed.

---

## 2. Navigation Integration

Extend SidebarItem:

```swift
enum SidebarItem: String, CaseIterable, Identifiable {
    case decks, browse, stats, sync
    case atlasSearch = "Smart Search"
    case analytics = "Analytics"
    case generator = "Card Generator"
    case knowledgeGraph = "Knowledge Graph"
    case obsidian = "Obsidian"
}
```

Atlas items grayed out when `appState.atlasService == nil`.

### AppState extension

```swift
@Observable @MainActor
final class AppState {
    let service: AnkiService
    let atlasService: AtlasService?  // nil if not configured
    var isAtlasAvailable: Bool { atlasService != nil }
}
```

---

## 3. Screen Designs

### 3a. Enhanced Search

**Files:** `Views/Atlas/Search/AtlasSearchView.swift`, `Models/AtlasSearchModel.swift`

**Model:**
- `query: String`, `searchMode: SearchMode` (.hybrid/.semanticOnly/.ftsOnly)
- `results: [SearchResultItem]`, `stats: FusionStats?`
- `deckFilter`, `tagFilter`, `semanticWeight`, `ftsWeight`

**UI:** Segmented control for search mode. Results show `rrf_score` as
relevance bar, `headline` with highlights, `match_modality` badge,
source indicators (semantic/fts/both).

**Atlas path:** `SearchFacade.search()` -> `search::service::SearchService`

### 3b. Analytics

**Files:** `Views/Atlas/Analytics/{TaxonomyTreeView,CoverageView,GapDetectionView,WeakNotesView,DuplicatesView}.swift`, `Models/AnalyticsModel.swift`

**Model:**
- `taxonomyTree: [TaxonomyNode]`, `selectedTopicPath: String?`
- `coverage: TopicCoverage?`, `gaps: [TopicGap]`
- `weakNotes: [WeakNote]`, `duplicateClusters: [DuplicateCluster]`

**Taxonomy Tree:** Recursive List with DisclosureGroup. Each node shows
label, note count badge, coverage meter bar, weak notes count.

**Coverage View:** Detail pane with note_count, mature_count,
avg_confidence gauge, weak_notes count, avg_lapses metric.

**Gap Detection:** Table of TopicGap items. Columns: topic path, gap
type badge (Missing=red, Undercovered=amber), note count vs threshold.

**Weak Notes:** Table with note preview, topic, confidence gauge,
lapses count, fail rate. Click opens note editor.

**Duplicates:** Grouped list of DuplicateCluster. Header shows
representative text and cluster size. Expand for DuplicateDetail items
with similarity score, text preview, deck, tags.

**Atlas path:** `AnalyticsFacade` methods -> `analytics::service::AnalyticsService`

### 3c. AI Features

**Files:** `Views/Atlas/Generator/{CardGeneratorView,CardPreviewView}.swift`,
`Views/Atlas/Validation/CardValidationView.swift`,
`Models/{CardGeneratorModel,CardValidationModel}.swift`

**Card Generator:** Two-pane. Left: source text/URL, topic selector,
language tags. Right: generated card tiles showing front/back,
confidence badge, card type (Basic/Cloze/MCQ). Actions: Generate,
Improve, Import to Anki.

**Card Validation:** Split view. Left: card front/back fields + tags.
Right: quality score radar (clarity, atomicity, testability,
memorability, accuracy, relevance), issues list with severity badges.

**Atlas path:** `GeneratePreviewService.preview()` for non-LLM preview,
`generator::agents::GeneratorAgent` for full LLM generation (requires
LlmProvider configuration).

**Note:** LLM generation requires API key configuration in preferences.
Start with heuristic validation and preview; defer full LLM to after
provider UI.

### 3d. Knowledge Graph

**Files:** `Views/Atlas/KnowledgeGraph/{ConceptGraphView,TopicEdgeBrowser}.swift`,
`Models/KnowledgeGraphModel.swift`

**Model:**
- `relatedNotes: [ConceptEdge]`, `prerequisites: [ConceptEdge]`
- `topicNeighborhood: TopicNeighborhood?`

**Concept Graph:** Start with list/table view of edges (force-directed
graph is Phase 6 polish). Nodes = notes, edges colored by EdgeType
(Similar=blue, Prerequisite=orange, Related=gray). Edge width =
weight.

**Topic Edge Browser:** Select topic from taxonomy, view adjacency
list grouped by EdgeType. Each edge shows target label, type badge,
source badge, weight bar.

**Atlas path:** `knowledge_graph::query::see_also()`,
`prerequisite_chain()`, `topic_neighborhood()` via
`KnowledgeGraphRepository`.

### 3e. Obsidian Integration

**Files:** `Views/Atlas/Obsidian/{VaultBrowserView,VaultSyncView}.swift`,
`Models/ObsidianModel.swift`

**Model:**
- `vaultPath: URL?`, `scanPreview: ObsidianScanPreview?`
- `vaultStats: VaultStats?`

**Vault Browser:** NSOpenPanel for vault path. Directory tree with
note counts. VaultStats display: total_notes, total_dirs,
notes_with_frontmatter, wikilinks_count, orphaned notes, broken links.

**Vault Sync:** ObsidianScanPreview showing discovered notes with
title, section count, generated card count. Progress bar. Import
action.

**Atlas path:** `ObsidianScanService.scan()` ->
`obsidian::sync::ObsidianSyncWorkflow` +
`obsidian::analyzer::VaultAnalyzer`

---

## 4. File Structure

```
AnkiApp/AnkiApp/AnkiApp/
  Bridge/
    AtlasBridge.h              // C declarations for atlas_bridge
    AtlasService.swift         // Actor wrapping atlas_command
    AtlasDTOs.swift            // Codable structs matching Rust serde types
  Models/
    AtlasSearchModel.swift
    AnalyticsModel.swift
    CardGeneratorModel.swift
    CardValidationModel.swift
    KnowledgeGraphModel.swift
    ObsidianModel.swift
  Views/Atlas/
    Search/
      AtlasSearchView.swift
    Analytics/
      TaxonomyTreeView.swift
      CoverageView.swift
      GapDetectionView.swift
      WeakNotesView.swift
      DuplicatesView.swift
    Generator/
      CardGeneratorView.swift
      CardPreviewView.swift
    Validation/
      CardValidationView.swift
    KnowledgeGraph/
      ConceptGraphView.swift
      TopicEdgeBrowser.swift
    Obsidian/
      VaultBrowserView.swift
      VaultSyncView.swift
```

---

## 5. Implementation Order

1. `atlas_bridge` crate + `AtlasBridge.h` + `AtlasService.swift`
2. `AtlasDTOs.swift` (Codable structs for SearchRequest/Response, etc.)
3. `AtlasSearchView` + `AtlasSearchModel` (validates bridge end-to-end)
4. Analytics: TaxonomyTree -> Coverage -> Gaps -> WeakNotes -> Duplicates
5. Obsidian: VaultBrowser -> VaultSync
6. Validation: CardValidationView (heuristic-only initially)
7. Generator: CardGeneratorView (preview-only initially, LLM later)
8. Knowledge Graph: TopicEdgeBrowser -> ConceptGraphView (list first)

---

## 6. Infrastructure Requirements

Atlas services require at runtime:
- **PostgreSQL** (embedded-postgres or external) for analytics/search schema
- **Qdrant** (subprocess or embedded) for vector search
- **Embedding provider** (fastembed local or OpenAI API) for semantic search

These are configured in `AtlasConfig` passed to `atlas_init`. The app
should degrade gracefully: Atlas sidebar items disabled when services
are unavailable, with a "Configure Atlas" settings pane.
