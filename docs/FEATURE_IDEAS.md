# Feature Ideas: Improvements Over Original Anki

This document catalogs feature ideas that leverage the Rust + SwiftUI + Atlas
architecture. Each idea includes effort estimate, prerequisites, and
implementation notes.

---

## Quick Wins (1-2 sessions each)

### 1. Predictive Retention Curves

Show per-card retention predictions visually. FSRS already computes
retrievability -- surface it in the UI.

```
Card: "Mitochondria is the..."
Retention: 92% -> 85% -> [review due] -> 95%
         ████████░░  <- predicted curve to next review
```

**Prerequisites**: rslib scheduler has `Retrievability` in states
**Implementation**:
- Add `getRetainability(cardId)` to AnkiService
- Create `RetentionCurveView` using Swift Charts
- Show in card detail popover from ReviewerView and SearchView

---

### 2. Smart Study Suggestions

Use the knowledge graph edges + FSRS data to suggest optimal study order
based on prerequisite relationships.

```
"You should review 'Cell Biology' before 'Genetics' --
 3 prerequisite cards are below 70% retention"
```

**Prerequisites**: Knowledge graph `concept_edges` table, FSRS retrievability
**Implementation**:
- Query prerequisite edges for current deck
- Filter by retention < threshold
- Show suggestion banner in DeckBrowserView before starting review

---

### 3. Automatic Cloze Generation

Extend the LLM card generator to auto-detect key terms and generate
cloze deletions from pasted text.

```
Input:  "The mitochondria is the powerhouse of the cell"
Output: "The {{c1::mitochondria}} is the {{c2::powerhouse}} of the cell"
```

**Prerequisites**: atlas/generator LLM integration
**Implementation**:
- Add "Smart Cloze" prompt template to generator
- Add mode toggle in CardGeneratorView (Basic / Cloze / Smart Cloze)
- Use LLM to identify key terms and wrap in cloze syntax

---

### 4. Similar Card Suggestions While Editing

When creating a new card, show existing similar cards to prevent
duplicates and suggest knowledge graph connections.

```
Similar cards found:
  "What is the powerhouse of the cell?" (92% match)
  "Mitochondria function" (78% match)
```

**Prerequisites**: `VectorRepository::find_similar_to_note` exists
**Implementation**:
- Embed the note text on save (or debounced while typing)
- Call `find_similar_to_note` before saving
- Show results in a disclosure group in NoteEditorView
- Option to link as related concept in knowledge graph

---

### 5. Forgetting Prediction Dashboard

Show which cards you're about to forget, days before they're due.

```
At Risk (next 7 days):
  15 cards dropping below 80% retention
  8 cards dropping below 60% retention
  243 cards stable above 90%
```

**Prerequisites**: FSRS stability + retrievability per card
**Implementation**:
- Batch compute predicted retention at T+1d, T+3d, T+7d
- Group cards by risk level
- Add "At Risk" tab to StatisticsView
- Option to start early review of at-risk cards

---

## Medium Effort (3-5 sessions)

### 6. Learning Streaks and Gamification

Track daily review streaks, cards learned, and time spent. Surface
achievements to maintain motivation.

```
 15-day streak | 2,847 cards mature | 23min avg/day
```

**Prerequisites**: revlog table has all historical data
**Implementation**:
- Create `streak_data` table in SQLite (or compute from revlog)
- Track: current streak, longest streak, total reviews, total time
- Add streak display to DeckBrowserView header
- Optional: achievement badges (100 cards, 30-day streak, etc.)

---

### 7. Adaptive Difficulty Detection

Automatically detect when cards are too easy or too hard and suggest
actions: split complex cards, suspend trivially easy ones.

```
This card has 8 consecutive 'Easy' ratings.
Consider: [Suspend] [Increase interval] [Mark as mastered]
```

**Prerequisites**: revlog analysis per card
**Implementation**:
- Analyze consecutive ease ratings from revlog
- Flag cards with N+ consecutive Easy (too easy) or Again (too hard)
- Show suggestions in card detail and as a batch in analytics
- Add "Difficulty Audit" to AnalyticsDashboardView

---

### 8. PDF and Webpage Import

Import highlighted text from PDFs or web pages directly into cards
via LLM extraction.

```
[Paste URL] -> extract key facts -> generate cards -> preview -> import
```

**Prerequisites**: atlas/generator LLM integration, reqwest for HTTP
**Implementation**:
- Add URL input field to CardGeneratorView (currently file-only)
- Use `reqwest` to fetch webpage, extract text (readability algorithm)
- For PDF: use `pdf-extract` or similar crate
- Feed extracted text to LLM card generator
- Preview and batch import

---

### 9. Interleaved Practice Mode

Mix cards from different decks based on topic similarity for better
long-term retention (research-backed interleaving effect).

```
Study mode: [Normal] [Interleaved] [Focused]
Interleaved: mixes related topics from different decks
```

**Prerequisites**: Knowledge graph edges, embedding similarity
**Implementation**:
- Create custom queue builder that pulls from multiple decks
- Use embedding similarity to select cards from related topics
- Alternate between different subject areas within a session
- Add mode selector to review session start

---

### 10. Voice-Powered Review

Use macOS/iOS speech recognition for hands-free review and
language learning with pronunciation feedback.

```
Card front: "Comment dit-on 'hello'?"
[Speak answer] -> "Bonjour" -> [Correct! Grade: Good]
```

**Prerequisites**: `SFSpeechRecognizer` (Apple framework)
**Implementation**:
- Add speech input button to ReviewerView
- Capture audio, transcribe via SFSpeechRecognizer
- Compare transcription to card answer (fuzzy match)
- Auto-grade based on similarity threshold
- Show pronunciation feedback for language cards

---

### 11. Optimal Review Time Detection

Analyze historical performance by time of day and suggest best
study windows based on personal patterns.

```
Your best retention: 9-11am (94% correct)
Avoid: 2-4pm (78% correct)
Suggested schedule: [Set reminder for 9:00am]
```

**Prerequisites**: revlog timestamps
**Implementation**:
- Aggregate review success rate by hour-of-day from revlog
- Compute rolling 30-day performance by time slot
- Show heatmap in StatisticsView (hour x day-of-week)
- Optional: macOS notification scheduling for optimal times

---

## Larger Projects (5+ sessions)

### 12. Collaborative Deck Sharing

Share decks with other users via the sync server, with real-time
merge conflict resolution.

```
Shared Deck: "Medical Board Prep" (3 contributors)
  12 new cards from @alice (pending review)
  5 edits from @bob (auto-merged)
```

**Prerequisites**: anki-atlas-server, user auth
**Implementation**:
- Add user authentication to atlas server (JWT or API keys)
- Deck permission model (owner, editor, viewer)
- Operational transform or CRDT for conflict-free card merging
- Shared deck browser UI with contributor activity feed
- Pull/push model for deck updates

---

### 13. Active Writing Practice

Beyond flashcards: write short-form answers and have LLM grade
them against the expected answer.

```
Q: "Explain the process of mitosis"
[Your answer: "Mitosis is cell division..."]
Score: 7/10 -- Missing: prophase details, spindle formation
```

**Prerequisites**: atlas/llm integration
**Implementation**:
- New review mode: "Write" (in addition to "Flip")
- Text input field for user's answer
- LLM grades answer against card back (rubric-based)
- Score mapped to SRS rating (0-3 -> Again, 4-6 -> Hard, 7-8 -> Good, 9-10 -> Easy)
- Review history tracks written vs flip reviews separately

---

### 14. Spaced Learning Paths

Auto-generate a study plan from a textbook, course syllabus, or
topic tree with weekly goals and progress tracking.

```
Course: "Organic Chemistry 101"
Week 1: Atomic structure (23 cards) ████████░░ 80%
Week 2: Bonding (31 cards)         ██████░░░░ 60%
Week 3: Stereochemistry (18 cards) ░░░░░░░░░░ not started
```

**Prerequisites**: Taxonomy system, coverage analysis, LLM generation
**Implementation**:
- Input: syllabus text or topic outline
- LLM breaks into weekly topics with prerequisites
- Map topics to existing cards (coverage analysis)
- Auto-generate missing cards
- Track progress per week with completion targets
- Calendar view with study schedule

---

### 15. Cross-Reference Annotations

Automatically link cards bidirectionally with explanatory context,
building a personal knowledge wiki within the SRS.

```
Card: "What is ATP?"
  See also: "Mitochondria function" (prerequisite)
  See also: "Krebs cycle" (builds on this)
  See also: "Cellular respiration" (broader context)
```

**Prerequisites**: Knowledge graph concept_edges, embedding similarity
**Implementation**:
- Auto-suggest links via embedding similarity on card save
- User confirms/rejects suggested connections
- Show "Related Cards" section in card detail
- Navigate between related cards during review
- Build concept map visualization from explicit links

---

### 16. Document Annotation Mode

Highlight and annotate documents (PDF, EPUB, web) with automatic
card generation from annotations.

```
[Open PDF] -> highlight "ATP synthase" -> right-click ->
  [Create card from highlight]
  [Add to existing card]
  [Create cloze from paragraph]
```

**Prerequisites**: PDF rendering, LLM integration
**Implementation**:
- PDFKit integration for macOS (built-in framework)
- Annotation layer with highlight + note tools
- Right-click menu to create cards from selections
- LLM generates question from highlighted context
- Annotations sync with card references (bidirectional link)

---

## Architecture Advantages Over Original Anki

| Capability | Original Anki | This Project |
|-----------|--------------|--------------|
| Search | Text-only SQL | Hybrid semantic + FTS with pgvector |
| Scheduling | SM-2 or FSRS | FSRS with predictive analytics |
| Card generation | Manual only | LLM-powered from text/URL/PDF |
| Duplicate detection | Field checksum | Embedding similarity (semantic) |
| Topic organization | Flat tags | Hierarchical taxonomy + knowledge graph |
| Quality analysis | None | Weak note detection, gap analysis |
| Note sources | Manual entry | Obsidian sync, PDF import, URL import |
| API access | None | MCP server, REST API, CLI |
| Extension model | Python plugins | Rust crates (compiled, type-safe) |
| Mobile | Separate codebases | Shared Rust core + SwiftUI |
| Collaboration | Shared decks (static) | Real-time collaborative editing |
| Analytics | Basic stats | Retention prediction, optimal timing |

---

## Priority Matrix

| Feature | Impact | Effort | Priority |
|---------|--------|--------|----------|
| Retention curves (#1) | High | Small | Do first |
| Smart study suggestions (#2) | High | Small | Do first |
| Auto cloze generation (#3) | High | Small | Do first |
| Similar card suggestions (#4) | High | Small | Do first |
| Forgetting dashboard (#5) | High | Small | Do first |
| Learning streaks (#6) | Medium | Medium | Short-term |
| Adaptive difficulty (#7) | Medium | Medium | Short-term |
| PDF/webpage import (#8) | High | Medium | Short-term |
| Interleaved practice (#9) | Medium | Medium | Short-term |
| Voice review (#10) | Medium | Medium | Short-term |
| Optimal time detection (#11) | Low | Medium | When convenient |
| Collaborative decks (#12) | High | Large | Medium-term |
| Active writing (#13) | High | Large | Medium-term |
| Learning paths (#14) | High | Large | Medium-term |
| Cross-references (#15) | Medium | Large | Medium-term |
| Document annotation (#16) | High | Large | Long-term |
