# UI Parity Audit: Original Anki vs SwiftUI Implementation

## Summary

| Category | Original Features | Implemented | Partial | Missing | Parity % |
|----------|------------------|-------------|---------|---------|----------|
| Deck Browser | 8 | 4 | 0 | 4 | 50% |
| Deck Overview | 7 | 1 | 0 | 6 | 14% |
| Reviewer | 16 | 5 | 0 | 11 | 31% |
| Browser | 12 | 2 | 1 | 9 | 21% |
| Note Editor | 11 | 4 | 0 | 7 | 36% |
| Statistics | 8 | 1 | 0 | 7 | 13% |
| Deck Config | 8 | 0 | 0 | 8 | 0% |
| Import/Export | 6 | 0 | 0 | 6 | 0% |
| Sync | 5 | 0 | 1 | 4 | 10% |
| Preferences | 6 | 3 | 0 | 3 | 50% |
| Note Types | 6 | 1 | 0 | 5 | 17% |
| Tags | 5 | 2 | 0 | 3 | 40% |
| Media | 5 | 0 | 0 | 5 | 0% |
| Image Occlusion | 4 | 0 | 0 | 4 | 0% |
| Custom Study | 3 | 0 | 0 | 3 | 0% |
| Undo/Redo | 3 | 0 | 0 | 3 | 0% |
| Add-ons | 5 | 0 | 0 | 5 | 0% |
| Profiles | 3 | 0 | 0 | 3 | 0% |
| **Atlas (NEW)** | 0 | 10 | 1 | 0 | **100%** |
| **TOTAL** | 121 | 33 | 3 | 96 | **27%** |

Atlas features (search, analytics, card gen, Obsidian) are net-new -- not in original Anki.

---

## TIER 1: ESSENTIAL (Must-Have for Daily Use)

### Deck Browser
| Feature | Original | SwiftUI | Gap |
|---------|----------|---------|-----|
| Hierarchical deck tree | Yes | Yes | -- |
| New/learning/review counts | Yes | Yes | -- |
| Study button per deck | Yes | Yes | -- |
| Deck collapse/expand | Yes | Yes | -- |
| Create deck | Yes | NO | MISSING |
| Rename deck | Yes | NO | MISSING |
| Delete deck | Yes | NO | MISSING |
| Drag-drop reorder | Yes | NO | MISSING |

### Deck Overview (between browser and reviewer)
| Feature | Original | SwiftUI | Gap |
|---------|----------|---------|-----|
| Card counts (new/learn/review/suspended) | Yes | Partial (in browser) | PARTIAL |
| Deck description | Yes | NO | MISSING |
| Study button | Yes | Yes (in browser) | -- |
| Custom study options | Yes | NO | MISSING |
| Filtered deck create | Yes | NO | MISSING |
| Unbury button | Yes | NO | MISSING |
| Rebuild/empty filtered | Yes | NO | MISSING |

### Card Reviewer
| Feature | Original | SwiftUI | Gap |
|---------|----------|---------|-----|
| Card front/back display (HTML) | Yes | Yes (WebKit) | -- |
| Answer buttons (Again/Hard/Good/Easy) | Yes | Yes | -- |
| Keyboard shortcuts (1-4, space) | Yes | Yes | -- |
| Progress bar (new/learn/review) | Yes | Yes | -- |
| Congrats screen | Yes | Yes | -- |
| Audio playback | Yes | NO | **CRITICAL** |
| Audio replay button | Yes | NO | **CRITICAL** |
| Flag card (colors) | Yes | NO | MISSING |
| Mark card | Yes | NO | MISSING |
| Bury card | Yes | NO | MISSING |
| Suspend card | Yes | NO | MISSING |
| Edit during review | Yes | NO | **IMPORTANT** |
| Undo last answer | Yes | NO | **IMPORTANT** |
| Type-answer comparison | Yes | NO | MISSING |
| Timer display | Yes | NO | MISSING |
| Auto-advance | Yes | NO | MISSING |

### Note Editor
| Feature | Original | SwiftUI | Gap |
|---------|----------|---------|-----|
| Multi-field editing | Yes | Yes (TextEditor) | -- |
| Notetype picker | Yes | Yes | -- |
| Deck picker | Yes | Yes | -- |
| Tag editor with autocomplete | Yes | Yes | -- |
| Rich text (bold/italic/etc) | Yes | NO | **CRITICAL** |
| Cloze deletion helper | Yes | NO | **CRITICAL** |
| Media attachment (image/audio) | Yes | NO | **CRITICAL** |
| HTML source editing | Yes | NO | IMPORTANT |
| LaTeX/MathJax | Yes | NO | MISSING |
| Edit existing notes | Yes | NO | **IMPORTANT** |
| Duplicate detection | Yes | NO | MISSING |

### Sync
| Feature | Original | SwiftUI | Gap |
|---------|----------|---------|-----|
| Full bidirectional sync | Yes | NO (stub) | **CRITICAL** |
| Conflict resolution (upload/download) | Yes | NO | **CRITICAL** |
| Media sync | Yes | NO | IMPORTANT |
| Progress display | Yes | NO | MISSING |
| Error handling/recovery | Yes | NO | MISSING |

---

## TIER 2: IMPORTANT (Needed for Full Experience)

### Browser / Card List
| Feature | Original | SwiftUI | Gap |
|---------|----------|---------|-----|
| Search with query syntax | Yes | Basic text only | PARTIAL |
| Sortable columns | Yes | NO | MISSING |
| Card info sidebar | Yes | NO | MISSING |
| Find & replace | Yes | NO | MISSING |
| Batch operations (tag/deck/flag) | Yes | NO | MISSING |
| Batch delete/suspend/bury | Yes | NO | MISSING |
| Note preview | Yes | NO | MISSING |
| Saved searches | Yes | NO | MISSING |
| Find duplicates | Yes | NO (Atlas has this) | PARTIAL |
| Column customization | Yes | NO | MISSING |
| Export selected | Yes | NO | MISSING |
| Layout options (split view) | Yes | NO | MISSING |

### Statistics
| Feature | Original | SwiftUI | Gap |
|---------|----------|---------|-----|
| Review count chart | Yes | Yes (bar chart) | -- |
| Card count breakdown | Yes | NO | MISSING |
| Ease distribution | Yes | NO | MISSING |
| Interval histogram | Yes | NO | MISSING |
| Future due forecast | Yes | NO | MISSING |
| Hours studied | Yes | NO | MISSING |
| Retention rate (FSRS) | Yes | NO | MISSING |
| Time range picker | Yes | NO | MISSING |

### Deck Config
| Feature | Original | SwiftUI | Gap |
|---------|----------|---------|-----|
| New card settings (steps, limit, order) | Yes | NO | MISSING |
| Review settings (limit, bonus, modifier) | Yes | NO | MISSING |
| Lapse settings (steps, threshold, action) | Yes | NO | MISSING |
| FSRS parameters | Yes | NO | MISSING |
| Presets (create/switch) | Yes | NO | MISSING |
| Advanced options (bury, display order) | Yes | NO | MISSING |
| Custom scheduling (JS) | Yes | NO | MISSING |
| Per-deck overrides | Yes | NO | MISSING |

### Import/Export
| Feature | Original | SwiftUI | Gap |
|---------|----------|---------|-----|
| Import .apkg | Yes | NO | MISSING |
| Import .colpkg | Yes | NO | MISSING |
| Import CSV with field mapping | Yes | NO | MISSING |
| Export .apkg | Yes | NO | MISSING |
| Export .colpkg | Yes | NO | MISSING |
| Export CSV | Yes | NO | MISSING |

---

## TIER 3: NICE-TO-HAVE (Full Feature Parity)

### Note Type Management
| Feature | Original | SwiftUI | Gap |
|---------|----------|---------|-----|
| List note types | Yes | Yes (in picker) | PARTIAL |
| Create note type | Yes | NO | MISSING |
| Clone note type | Yes | NO | MISSING |
| Edit fields (add/remove/reorder) | Yes | NO | MISSING |
| Edit card templates (front/back/CSS) | Yes | NO | MISSING |
| Change note type (convert) | Yes | NO | MISSING |

### Media Management
| Feature | Original | SwiftUI | Gap |
|---------|----------|---------|-----|
| Check media integrity | Yes | NO | MISSING |
| Find unused media | Yes | NO | MISSING |
| Remove unused media | Yes | NO | MISSING |
| Media folder access | Yes | NO | MISSING |
| Media server (for card display) | Yes | Partial (WebKit) | PARTIAL |

### Image Occlusion
| Feature | Original | SwiftUI | Gap |
|---------|----------|---------|-----|
| Image loading | Yes | NO | MISSING |
| Mask drawing (rect/polygon/freehand) | Yes | NO | MISSING |
| Shape management | Yes | NO | MISSING |
| Occlusion card generation | Yes | NO | MISSING |

### Custom Study / Filtered Decks
| Feature | Original | SwiftUI | Gap |
|---------|----------|---------|-----|
| Review forgotten cards | Yes | NO | MISSING |
| Study ahead | Yes | NO | MISSING |
| Cram mode | Yes | NO | MISSING |

### Undo/Redo
| Feature | Original | SwiftUI | Gap |
|---------|----------|---------|-----|
| Undo last operation | Yes | NO | MISSING |
| Redo | Yes | NO | MISSING |
| Operation history | Yes | NO | MISSING |

### Profiles
| Feature | Original | SwiftUI | Gap |
|---------|----------|---------|-----|
| Multiple profiles | Yes | NO | MISSING |
| Profile switching | Yes | NO | MISSING |
| Profile management | Yes | NO | MISSING |

### Add-ons
| Feature | Original | SwiftUI | Gap |
|---------|----------|---------|-----|
| Install add-ons | Yes | NO | NOT PLANNED |
| Manage add-ons | Yes | NO | NOT PLANNED |
| Add-on API | Yes | NO | NOT PLANNED |

Note: Add-on system is Python-based and not applicable to Swift. MCP server replaces extensibility.

---

## ATLAS FEATURES (Net-New, Not in Original Anki)

| Feature | Status | Notes |
|---------|--------|-------|
| Hybrid search (FTS + semantic) | DONE | Mode toggle, RRF ranking |
| Topic taxonomy tree | DONE | Hierarchical with note counts |
| Coverage analytics | DONE | Confidence gauge, metrics |
| Gap detection | DONE | Missing/undercovered topics |
| Weak notes identification | DONE | Sorted by confidence |
| Duplicate detection | DONE | Similarity clusters |
| LLM card generation | DONE | From text, with preview |
| Obsidian vault browser | DONE | Scan and list notes |
| Knowledge graph | STUB | Backend not yet wired |
| MCP server (Claude Code) | DONE | All tools exposed |

---

## PRIORITY IMPLEMENTATION ORDER

### Sprint 1: Critical Gaps (makes it usable for daily study)
1. **Audio playback** in reviewer (AVFoundation)
2. **Edit existing notes** (load note by ID, modify, save)
3. **Sync with AnkiWeb** (wire to rslib sync client)
4. **Rich text editor** (at minimum: bold, italic, cloze button)
5. **Undo last answer** in reviewer

### Sprint 2: Important Gaps (complete study experience)
6. **Deck CRUD** (create, rename, delete)
7. **Bury/suspend** from reviewer
8. **Flag cards** from reviewer
9. **Edit during review** (open editor popup)
10. **Media attachment** in editor (image picker)
11. **Deck config screen** (new/review/lapse settings)

### Sprint 3: Browser & Stats (power user features)
12. **Browser improvements** (sort, batch operations, note preview)
13. **More statistics charts** (intervals, ease, forecast, retention)
14. **Import .apkg** files
15. **Export .apkg** files
16. **Time range picker** for stats

### Sprint 4: Full Parity (completeness)
17. **Note type management** (create, edit fields, edit templates)
18. **Image occlusion** editor
19. **Custom study / filtered decks**
20. **CSV import** with field mapping
21. **Media management** (check, cleanup)
22. **Undo/redo** system
23. **Conflict resolution** UI for sync
24. **Knowledge graph** visualization
