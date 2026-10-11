# Achievement guide

The development source includes **42 achievements** and **19 original monochrome badge icons**. These changes are not in the published [v0.3.0 release](https://github.com/senketsukamui/kindlevel/releases/tag/v0.3.0). Tap the badge beside Settings or choose **Tools → Kindlevel achievements**. Use **All**, **Earned**, **Locked**, or **Book quests**; swipe or use arrows to browse. Tap anywhere on a card for its full description and recognition date. Notification previews are available from **Tools → Preview achievement notification**, with a paginated chooser.

Milestones cover reading time, pages, confirmed finishes, historical best streaks, reading days, single-day records, returns, highlights, notes, authors and time windows. Book quests include **Don't Panic** (Hitchhiker's Guide), **The Spice Must Flow** (Dune), **Big Reader Is Watching** (1984), **There and Back Again** (The Hobbit), **One Does Not Simply Finish** (Lord of the Rings), **The White Whale** (Moby-Dick), a bundled-book starter badge, and **Dude...** for actually opening Mein Kampf. Read-specific-book conditions require recorded reading time; `open` quests trigger on ReaderReady with the document’s metadata, even with no statistics database. Opening quests are tracked from this version onward and are not inferred from files on the shelf or old reading totals. Having the file on your device does not qualify. Finish conditions require a confirmed finish, never a page-percentage guess.

Unlocks persist in Kindlevel's own `achievement_unlocks` ledger and are never revoked when a streak ends, a finish is removed, or history disappears. Existing history is recognized quietly on the first check, and eligible definitions added later are also backfilled quietly. Newly reached conditions display a corner notification. Recognition timestamps show when Kindlevel observed the condition, not the original date a historical milestone happened. XP is stored only in definitions and displayed as **reserved**; it is not awarded, totaled or used for levels.

Checks run when Kindlevel opens, history refreshes, a finish is recorded, and after native reader events. Page-driven checks run at most once every 30 seconds; annotation and save/resume events can check sooner. Kindlevel asks the default collector to flush its recorded page intervals, then reads the database through its existing read-only adapter. It does not time an idle reader or count rapid page tapping itself. Pending checks and notifications are cancelled on sleep/close as appropriate.

Page milestones use native normalized book/page counts per local day, including another day's rereading. Time uses original recorded durations so layout rescaling does not multiply intervals. Time-window rules use the local start hour of each recorded interval; overnight windows support midnight crossings. A `per_day` overnight rule groups by calendar date, not a night spanning two dates. Returns count full days without activity and have their own fixed trigger thresholds, independent of the statistics screen's break selector. Author variety counts distinct metadata author credits from books with at least 15 minutes of recorded reading. Unknown authors are excluded.

**Marathon Reader** requires three recorded hours in one session. A book switch, sleep, closing the reader, or a gap of more than 60 seconds ends the session. Short gaps contribute no reading time, and overlapping records count once. Original page intervals are streamed through the session calculation, so layout rescaling does not multiply time and the plugin does not keep all page events in memory. Kindlevel stores open-book metadata and session-boundary timestamps in its own settings. Intervals spanning an explicit pause are excluded because their before/after reading allocation is unknown. Older history infers sessions from book IDs and gaps; historical sleep/close boundaries cannot be recovered before this feature was installed.

## Add your own achievements

Edit [`kindlevel_achievement_catalog.lua`](../kindlevel.koplugin/kindlevel_achievement_catalog.lua), or copy [`custom_achievements.example.lua`](../kindlevel.koplugin/custom_achievements.example.lua) to `custom_achievements.lua` inside `kindlevel.koplugin`. The optional file returns a list of definitions and does not require changes to the engine, UI or notification code. Restart KOReader, or click Reload Lua in the Mac preview, after editing. Keep your custom file and icons when replacing the plugin during an upgrade.

```lua
return {
    {
        id = "my_book_quest",
        icon = "achievements/book.svg", -- relative to assets/
        text = "A Personal Quest",
        description = "Read twenty minutes of my favorite book.",
        xp = 50, -- reserved for later
        group = "books", -- appears under Book quests
        trigger = {
            type = "book", action = "read", target = 20,
            titles = { "Your book's metadata title", "A translated title" },
        },
    },
}
```

IDs must be unique and remain stable. Icon paths are relative to `assets/`; missing or unreadable icons fall back to the standard badge. Invalid definitions, duplicate IDs and failing custom triggers are logged and isolated so other achievements continue working. Book matching normalizes Unicode case, whitespace and punctuation and matches when the metadata title **contains any title alias**. Prefixes, subtitles and edition suffixes qualify, including other book names containing the fragment. Add aliases for translations; optional `authors` restricts the author credit. Custom definitions may opt into `match = "exact"` if needed; all built-in book quests use substring matching.

| Trigger | Fields / behavior |
| --- | --- |
| `metric` | `metric`, `target`; metrics: `minutes`, `pages`, `finished`, `best_streak`, `active_days`, `highlights`, `notes`, `authors`, `books_read` |
| `daily` | `metric = "minutes"`, `"pages"`, or `"books"`; `target`; optional `weekdays = {0, 6}` (Sunday/Saturday) |
| `window` | `start_hour`, `end_hour`, `target` in minutes; optional `per_day = true`; intervals use an inclusive start and exclusive end |
| `return` | `scope = "reading"` or `"books"`, `min_gap` in full days, `target` number of returns |
| `book` | `action = "read"` with a minute `target`, or `action = "finish"` / `"open"`; `titles`; optional `authors` and `match` |
| `session` | `target` in recorded minutes, optional `max_gap` in seconds (default 60); longest session in one book, with explicit sleep/close boundaries |
| `all` / `any` | `conditions = {...}` combining other triggers |
| Lua function | `function(context)` returning a boolean, or `{value=..., target=..., unit=..., label=...}` for custom progress |

Custom callbacks receive `context.now`, `metrics`, `daily` (date → pages/seconds/books), `hours` (book/date/hour/seconds), `books` (metadata, seconds, sorted activity days), `finished` (confirmed book metadata/date), `activity_days`, `opened` (metadata of documents actually opened), and `sessions` (gap → longest session with `seconds`, `start`, `finish`, `book_id`; always includes gap 60). See the example file for a combined condition with a custom callback. These files are normal plugin Lua code; keep callbacks quick and free of side effects.

Tests: `tests/achievement_rules.lua` covers rules, title matching, backfill, persistence, custom definitions and every catalog page/icon. `tests/achievements.lua` checks actual timers, queues, previews, native page turns and automatic unlock notifications with XP unused. With the Mac preview running, `python3 tests/achievements_preview.py` checks paging, filters and full-card details without preview actions.


[Back to the project overview](../README.md).
