# CLI and MCP Server Guide

Anki SwiftUI provides command-line and MCP tools for scripting, automation, and Claude Code integration.

## Installation

### Prerequisites

- Rust 1.88+ (via [rustup](https://rustup.rs/))
- macOS 12.0+ or Linux
- A configured Anki collection

### Build CLI and MCP Server

```bash
# Build both binaries
cargo build --release -p anki-atlas-cli -p anki-atlas-mcp

# Binaries are in target/release/
./target/release/anki-atlas --version
./target/release/anki-atlas-mcp
```

Add to your PATH for system-wide access:

```bash
ln -s $(pwd)/target/release/anki-atlas /usr/local/bin/
ln -s $(pwd)/target/release/anki-atlas-mcp /usr/local/bin/
```

## CLI Commands

Run `anki-atlas --help` for all commands. Below are the key workflows.

### version

Display the CLI version:

```bash
anki-atlas version
```

### sync

Initialize and index a collection:

```bash
anki-atlas sync /path/to/collection.anki2
```

Options:
- `--no-migrate` — skip schema migration
- `--no-index` — skip indexing (use existing index)
- `--force-reindex` — reindex all notes regardless of changes

Use this once to set up a collection, then run `index` for incremental updates.

### index

Incrementally reindex the collection:

```bash
anki-atlas index
```

Options:
- `--force` — reindex all notes (same as `sync --force-reindex`)

Run this after importing new cards to update the search index.

### search

Query the collection with hybrid search:

```bash
anki-atlas search "ownership in Rust" --deck Rust --limit 10
```

Options:
- `--deck NAME` — filter by deck name (repeatable)
- `--tag TAG` — filter by tag (repeatable)
- `-n, --limit N` — max results (default: 10)
- `--semantic` — semantic search only
- `--fts` — full-text search only
- `--chunks` — search within chunks (semantic only)
- `--verbose` — show ranking scores

### topics

Manage topic hierarchies for analytics:

```bash
# Show topic tree
anki-atlas topics tree

# Show subtree under rust
anki-atlas topics tree --root-path rust

# Load topics from file
anki-atlas topics load --file topics.json

# Label topics with AI
anki-atlas topics label --file notes.json --min-confidence 0.6
```

### coverage

Analyze topic coverage in your collection:

```bash
anki-atlas coverage "rust/ownership" --no-subtree
```

Shows how many notes cover the topic and quality metrics.

### gaps

Find gaps in topic coverage:

```bash
anki-atlas gaps "rust/concurrency" --min-coverage 2
```

Lists topics with fewer than N covering notes.

### weak-notes

Find notes with low retention:

```bash
anki-atlas weak-notes "rust/ownership" --limit 20
```

Shows notes that need improvement in a topic area.

### duplicates

Find similar notes in the collection:

```bash
anki-atlas duplicates --threshold 0.92 --deck Rust
```

Options:
- `--threshold N` — similarity threshold 0.0–1.0 (default: 0.92)
- `--max N` — max clusters to find (default: 50)
- `--deck NAME` — filter by deck (repeatable)
- `--tag TAG` — filter by tag (repeatable)

### generate

AI-generate cards from source text:

```bash
anki-atlas generate source.txt
```

Options:
- `--dry-run` — preview results without saving

Input file format: plain text or Markdown.

### validate

Validate note quality:

```bash
anki-atlas validate collection.json --quality
```

Checks for:
- Missing fields
- Malformed HTML
- Invalid media references
- (with `--quality`) poor field coverage and empty fields

### obsidian-sync

Sync with Obsidian vault:

```bash
anki-atlas obsidian-sync /path/to/vault \
  --source-dirs "Notes,Learning" \
  --dry-run
```

Options:
- `--source-dirs DIRS` — comma-separated paths to sync (default: all)
- `--dry-run` — preview changes without writing

### tag-audit

Audit and fix tag consistency:

```bash
anki-atlas tag-audit tags.json --fix
```

Options:
- `--fix` — apply corrections

Normalizes tag hierarchies and detects inconsistencies.

### cardloop

Quality improvement loop: scan, queue, fix, resolve.

```bash
# Scan for issues (audit, generation, or all)
anki-atlas cardloop scan --loop-kind all \
  --registry registry.db \
  --anki-collection collection.anki2

# Show dashboard
anki-atlas cardloop status --registry registry.db

# Get next items to fix
anki-atlas cardloop next --registry registry.db --count 5

# Mark items as fixed/skipped
anki-atlas cardloop resolve --registry registry.db \
  --item-id abc123 \
  --action fixed

# Show history
anki-atlas cardloop log --registry registry.db --limit 50
```

## MCP Server

The MCP server enables Claude Code integration with your Anki collection.

### Starting the Server

```bash
anki-atlas-mcp
```

The server starts on port 3000 by default (configurable via `MCP_PORT`).

### Claude Code Integration

Configure Claude Code to use the MCP server:

1. Add to `.claude/config.json`:

```json
{
  "mcp_servers": [
    {
      "name": "anki",
      "command": "/path/to/anki-atlas-mcp",
      "env": {
        "ANKIATLAS_ANKI_COLLECTION_PATH": "/path/to/collection.anki2"
      }
    }
  ]
}
```

2. In Claude Code, you can now:
   - Search your collection
   - Generate cards
   - Analyze topics
   - Find duplicates
   - All via natural language

### Available Tools

**search** — Hybrid search (semantic + FTS)

```
Input: query, deck_names[], tags[], limit, search_mode (hybrid|semantic_only|fts_only)
Output: search results with ranking scores
```

**search_chunks** — Search within note chunks

```
Input: query, deck_names[], tags[], limit
Output: ranked chunk results
```

**topics_tree** — Show topic hierarchy

```
Input: root_path (optional)
Output: topic tree structure
```

**topic_coverage** — Coverage metrics for a topic

```
Input: topic_path, include_subtree (bool)
Output: coverage report
```

**topic_gaps** — Find gaps in topic coverage

```
Input: topic_path, min_coverage
Output: list of under-covered subtopics
```

**topic_weak_notes** — Notes with low retention

```
Input: topic_path, max_results
Output: weak notes in topic
```

**duplicates** — Find similar notes

```
Input: threshold (0.0–1.0), max_clusters, deck_names[], tags[]
Output: clusters of similar notes
```

**index_collection** — Reindex the collection

```
Input: mode (incremental|force)
Output: indexing status
```

## Configuration

### Environment Variables

**Collection Settings:**
- `ANKIATLAS_ANKI_COLLECTION_PATH` — path to `collection.anki2`
- `ANKIATLAS_ANKI_MEDIA_ROOT` — path to media folder (optional)

**Database:**
- `ANKIATLAS_POSTGRES_URL` — PostgreSQL connection URL (analytics features; optional)

**Embedding:**
- `ANKIATLAS_EMBEDDING_PROVIDER` — `openai`, `google`, `fastembed`, `mock` (default: `openai`)
- `ANKIATLAS_EMBEDDING_MODEL` — model name (default: `text-embedding-3-small`)
- `ANKIATLAS_EMBEDDING_DIMENSION` — embedding dimension (default: 1536)

**API Server:**
- `ANKIATLAS_API_HOST` — bind address (default: `0.0.0.0`)
- `ANKIATLAS_API_PORT` — bind port (default: `8000`)
- `ANKIATLAS_API_KEY` — optional API authentication key

**Logging:**
- `ANKIATLAS_DEBUG` — enable debug logging (default: `false`)

See `docs/CONFIG.md` for full reference.

### .env File

Create `.env` in the project root:

```env
ANKIATLAS_ANKI_COLLECTION_PATH=/Users/user/Library/Application Support/Anki2/User 1/collection.anki2
ANKIATLAS_ANKI_MEDIA_ROOT=/Users/user/Library/Application Support/Anki2/User 1/collection.media
ANKIATLAS_EMBEDDING_PROVIDER=openai
ANKIATLAS_EMBEDDING_MODEL=text-embedding-3-small
ANKIATLAS_DEBUG=false
```

## Examples

### Batch Search Workflow

```bash
# Search for cards on a topic
anki-atlas search "async/await" --deck Rust --limit 20 > results.json

# Analyze results
jq '.results[].note.front' results.json
```

### Automation with cron

Index daily and find duplicates:

```bash
# In crontab
0 2 * * * /usr/local/bin/anki-atlas index && /usr/local/bin/anki-atlas duplicates --threshold 0.95 > /tmp/duplicates.txt
```

### Obsidian Integration

Sync your vault with Anki:

```bash
# One-time sync
anki-atlas obsidian-sync /path/to/vault --source-dirs "Learning"

# Preview changes first
anki-atlas obsidian-sync /path/to/vault --source-dirs "Learning" --dry-run
```

### Topic Coverage Report

```bash
# Find weak areas in Rust studies
anki-atlas gaps "rust" --min-coverage 3 > gaps.txt

# See low-retention cards
anki-atlas weak-notes "rust/ownership" --limit 10
```

## Troubleshooting

### Collection Not Found

```
Error: no such file or directory
```

Solution: Set `ANKIATLAS_ANKI_COLLECTION_PATH` or pass the path directly:

```bash
anki-atlas sync /path/to/collection.anki2
```

### Index Out of Sync

If search results are stale, reindex:

```bash
anki-atlas index --force
```

### MCP Server Won't Start

Check logs:

```bash
ANKIATLAS_DEBUG=true anki-atlas-mcp
```

Verify environment variables are set correctly.

## See Also

- `docs/CONFIG.md` — detailed configuration reference
- `docs/USER_GUIDE.md` — SwiftUI app documentation
- CLI `--help` — inline help for any command
