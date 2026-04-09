# Anki SwiftUI User Guide

Welcome to Anki SwiftUI, a native macOS spaced repetition application with AI-powered search and analytics. This guide walks you through the core features and workflows.

## Getting Started

### Opening a Collection

1. Launch Anki SwiftUI
2. Go to **Preferences** (Command+,)
3. Select your Anki collection file (`collection.anki2`)
4. Return to the main window — your decks will load

If no decks appear, create a new one:
- Click **New Deck** in the Decks view
- Enter a name and confirm

### First Review Session

1. In the **Decks** sidebar, select a deck to review
2. Click the deck card in the main panel
3. Click **Study** to start a review session
4. Read the question and think of an answer
5. Click **Show Answer** to reveal the answer
6. Rate your response using the buttons:
   - **Again** — you need more practice
   - **Hard** — you found it difficult
   - **Good** — you got it right
   - **Easy** — very familiar

## Studying

### Deck Browser

The **Decks** view in the sidebar shows your deck hierarchy:
- Tap a deck to view overview statistics
- Hover over a deck to see new, review, and learning card counts
- Create new decks using the **New Deck** button
- Right-click a deck for rename/delete options

Each deck card shows:
- **New** — unseen cards
- **Learning** — cards you're still mastering
- **Due** — cards ready for review

### Review Session

During review, the app displays:
- **Card content** — question rendered in WKWebView (supports HTML, LaTeX, images)
- **Progress bar** — shows your position in the deck
- **Card info sidebar** — (optional) shows statistics and scheduling details

Click the **Info** button to toggle card statistics showing:
- Ease factor
- Review count
- Time spent
- Next review date

Keyboard shortcuts during review:
- **Cmd+1/2/3/4** — rate the card (Again/Hard/Good/Easy)
- **Space** — show/hide answer
- **Cmd+Z** — undo last answer
- **Cmd+5** — flag/unflag card

### Congratulations Screen

When you finish all reviews, you'll see the congratulations screen showing:
- Total reviews completed
- Streak information
- Average time per card

## Creating Content

### Adding Notes

1. Go to the **Decks** view
2. Click **Add Note** (Command+N)
3. Select a note type (e.g., Basic, Cloze)
4. Pick a destination deck
5. Fill in the fields:
   - **Front** — the question
   - **Back** — the answer
6. Add tags (space-separated)
7. Click **Save**

### Field Editor

The note editor provides:
- **Rich text formatting**: bold, italic, underline, subscript, superscript
- **Image insertion**: drag-and-drop or paste from clipboard
- **LaTeX support**: wrap formulas in `$$...$$ ` for display math or `$...$` for inline
- **Formatting toolbar** for quick styling
- **Field requirements indicator**: shows which fields are required and how many cards will be generated

### Cloze Deletions

Create fill-in-the-blank questions:

1. Type your text: "The capital of France is {{c1::Paris}}"
2. Select text and click the **Cloze** button in the formatting toolbar
3. Multiple clozes: {{c1::First}}, {{c2::Second}} — generates separate cards for each

### Tags

Organize notes with tags:
- Use **colon separators** for hierarchy: `topic::subtopic::detail`
- Tags help with filtering and organization
- Search by tag in the Browse view

## Browsing and Searching

### Browse View

The **Browse** view lets you search, filter, and edit notes:
- **Search box** — find notes by content, tags, deck, or fields
- **Column view** — configure visible columns (front, back, tags, due date, etc.)
- **Filter panel** — narrow results by deck, tag, or card state

### Search Syntax

| Syntax | Example | Result |
|--------|---------|--------|
| Text search | `ownership` | Notes containing "ownership" |
| Tag filter | `tag:topic::rust` | Notes with tag starting with `topic::rust` |
| Deck filter | `deck:Rust` | Cards from "Rust" deck |
| Field search | `front:async` | "async" in the front field |
| Is:new, is:due | `is:due` | Cards ready for review |
| Rating filter | `rated:1..2` | Cards rated 1 or 2 |

### Atlas Search (Search+)

The **Search+** feature in Atlas uses hybrid search combining semantic and keyword matching:
- **Semantic search**: finds conceptually similar notes using embeddings
- **Full-text search**: finds exact word matches
- **Hybrid mode**: combines both for best results
- **Deck/tag filtering**: narrow results by deck or tag

Use Search+ to find related concepts across your collection, even if the exact wording differs.

## Deck Options

The **Deck Options** dialog configures card scheduling:

### Learning Steps

Cards you're learning show on different schedules:
- Default: 1m, 10m (1 minute, then 10 minutes after first correct)
- Controls how quickly new cards progress to normal review

### Relearning Steps

Cards you've forgotten restart with special scheduling:
- Default: 10m (review again after 10 minutes)

### FSRS Settings

Anki uses the FSRS (Free Spaced Repetition Scheduler) algorithm:
- **Target retention**: default 0.90 (aim for 90% recall)
- **Interval modifier**: adjust by percentage (higher = longer intervals)
- **Maximum interval**: cap on review spacing (default 36,500 days)

Most users can leave defaults. Adjust if reviewing feels too easy or too hard.

## Statistics

The **Statistics** view shows your progress with interactive charts:

### Available Charts

- **Card counts** — distribution of new, learning, due, and suspended cards
- **Added** — notes added over time
- **Study time** — minutes studied per day
- **Intervals** — distribution of card review spacings
- **Eases** — card difficulty distribution

### Time Range

Customize the view:
- **Today** — current session only
- **1 month** — last 30 days
- **3 months** — last quarter
- **Year** — last 365 days
- **All** — entire history

### Interpreting Graphs

- **Higher ease** — easier cards (less review needed)
- **Longer intervals** — cards you've learned well
- **Study time peaks** — when you studied most
- **Card count by state** — how many cards are at each stage

## Import and Export

### Importing Decks

1. Go to **Import** in the sidebar
2. Select an `.apkg` file (Anki deck package)
3. Choose a destination deck
4. Click **Import**

The import process updates existing notes if they match and adds new ones.

### Exporting Decks

1. Go to **Export** in the sidebar
2. Select the deck(s) to export
3. Choose format:
   - **.apkg** — complete deck with media
   - **.colpkg** — entire collection
4. Click **Export**

You can import exported decks into Anki Desktop or share them with others.

### CSV Import

For bulk importing from spreadsheets:
- Use the web interface or CLI for advanced CSV import
- See the CLI guide for `anki-atlas sync` command details

## Sync

### AnkiWeb Sync

Synchronize your collection with AnkiWeb:

1. Go to **Sync** in the sidebar
2. Log in with your AnkiWeb account
3. Click **Upload** or **Download**
4. Wait for completion

### Conflict Resolution

If changes exist on both sides (unlikely if syncing regularly):
- Choose **Keep local** to use your current version
- Choose **Fetch remote** to pull the latest from AnkiWeb
- The app will guide you if conflicts occur

Tip: Sync frequently to avoid conflicts.

## Atlas Features

### Hybrid Search (Search+)

Find notes using semantic understanding:
- Type a concept or question
- Results include semantically related notes, not just exact matches
- Filter by deck or tag for focused searching

Example: Search for "memory techniques" to find notes about mnemonics, spaced repetition, and recall.

### Analytics

The **Analytics** view provides insights:
- **Topic coverage** — how well your notes cover a topic area
- **Weak notes** — notes with low recall or missing content
- **Gaps** — topics with insufficient card coverage
- **Knowledge graph** — visual relationships between topics

### Card Generator

The **Generator** view creates cards from source text:

1. Paste or upload text
2. Set generation parameters
3. AI suggests new cards based on the source
4. Review and refine suggestions
5. Save to your collection

### Obsidian Sync

Bidirectional synchronization with Obsidian:

1. Go to **Obsidian** in the sidebar
2. Connect to your vault
3. Map source directories
4. Sync creates/updates cards from your notes
5. Changes in Anki reflect back to Obsidian

This workflow integrates note-taking with spaced repetition.

## Keyboard Shortcuts

### Global

| Shortcut | Action |
|----------|--------|
| Cmd+, | Open Preferences |
| Cmd+N | Add Note |
| Cmd+Shift+D | New Deck |
| Cmd+Q | Quit |

### During Review

| Shortcut | Action |
|----------|--------|
| Space | Show/hide answer |
| Cmd+1 | Again |
| Cmd+2 | Hard |
| Cmd+3 | Good |
| Cmd+4 | Easy |
| Cmd+5 | Flag card |
| Cmd+Z | Undo last answer |

### In Browse View

| Shortcut | Action |
|----------|--------|
| Cmd+F | Focus search |
| Return | Edit selected note |
| Delete | Delete note |

## Tips and Best Practices

### Card Quality

- **Front is a question** — avoid stating the answer in the question
- **Back is a concise answer** — longer cards take more time to review
- **One concept per card** — easier to remember and schedule
- **Use cloze for lists** — better than multiple-choice for retention

### Efficient Reviewing

- **Review daily** — consistent spacing improves retention
- **Don't suspend** — embrace the learning curve
- **Focus on understanding** — cards are reminders, not learning tools
- **Adjust deck options** — use FSRS target retention to balance workload

### Organization

- **Organize by subject** — create deck hierarchies matching your knowledge
- **Use tags consistently** — `topic::concept::detail` makes filtering powerful
- **Archive old decks** — move completed decks to keep current decks organized
- **Regular maintenance** — periodically review duplicates and weak cards

## Troubleshooting

### Collection Won't Open

1. Check file exists at the path in Preferences
2. Ensure the file is not open in another Anki instance
3. Try restarting the app

### Cards Not Syncing

1. Verify AnkiWeb login is correct
2. Check internet connection
3. Try clicking **Sync** again (network may be temporary issue)
4. If stuck, check Preferences for the collection path

### Slow Review Performance

1. Check if you have large images on cards
2. Try disabling the info sidebar (click **I** during review)
3. Reduce the number of cards in the current session
4. Restart the app if it feels sluggish

### Images Not Appearing

1. Verify images are in the media folder (`collection.media/`)
2. Check the image filename in the card HTML
3. Re-add the image and check the spelling

## See Also

- **Anki Manual** — [docs.ankiweb.net](https://docs.ankiweb.net) for deeper scheduling theory
- **Atlas Documentation** — advanced search and analytics features
- **CLI Guide** — command-line tools for automation and scripting
