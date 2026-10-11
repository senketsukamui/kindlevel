# Kindlevel for KOReader

A local Kindle app inspired by the reel, with reading statistics, an activity calendar, a cover carousel, and a local book library. Book rendering, saved positions, and activity recording are handled by KOReader.

**[Download v0.3.0](https://github.com/senketsukamui/kindlevel/releases/download/v0.3.0/kindlevel-0.3.0.zip)** · [Release and installation notes](https://github.com/senketsukamui/kindlevel/releases/tag/v0.3.0)

## Install on your Paperwhite 10th generation

KOReader must already be installed. This package is a plugin; it does not include KOReader or require a new jailbreak.

1. Download **`kindlevel-0.3.0.zip`** from the [GitHub release](https://github.com/senketsukamui/kindlevel/releases/tag/v0.3.0) and unzip it on your computer. The installable ZIP is in the release assets; GitHub's automatic **Source code** archives are for development.
2. Exit KOReader, then connect the Kindle over USB.
3. Copy the **entire `kindlevel.koplugin` folder** into the `plugins` directory inside your KOReader installation. For a typical installation, the USB drive should contain:

   ```text
   koreader/
     reader.lua
     plugins/
       kindlevel.koplugin/
         main.lua
         _meta.lua
         kindlevel_library.lua
         kindlevel_screen.lua
         assets/
         books/
   ```

   On the Kindle, that is usually `/mnt/us/koreader/plugins/kindlevel.koplugin/`. If your installation is elsewhere, use the directory containing KOReader's `reader.lua`.

4. Safely eject the Kindle, disconnect USB, and start KOReader.
5. Open the main menu, go to the **Tools** section, and choose **Kindlevel**. If it is missing, open KOReader's plugin manager, enable **Kindlevel**, and restart KOReader. External plugins must be allowed in KOReader's plugin settings.

**Do not create an extra nesting level.** `main.lua` must be directly inside `plugins/kindlevel.koplugin/`.

### Upgrade from the original release

Exit KOReader and remove the old `readinghome.koplugin` folder before installing `kindlevel.koplugin`, so only one plugin is loaded. Choose your books folder again in Kindlevel's Settings; preferences now use `kindlevel.lua`. Your own books' reading positions remain in KOReader's existing document sidecars. Reassign any shortcut to the new **Kindlevel** gesture action.

## Try it

The first launch shows three original sample books: two EPUBs and one plain-text document.

- Swipe left/right or tap a neighboring cover to select a book.
- Tap the large cover or **Start reading** to open it in KOReader.
- Turn pages using KOReader's usual gestures and controls.
- To return, open KOReader's main menu and choose **Kindlevel**. This saves and closes the book, then restores the custom home.
- The selected book's saved completion percentage appears beneath its cover. Tap **Continue reading** to resume.
- The header shows **Today** (reading time, streak, and daily-goal progress) and **yearly books** (confirmed finishes toward your target). Tap Today for its session journal, or tap the yearly count for goal details. Goals set to 0 show totals without a progress line.
- **Statistics** shows period totals and a daily chart. Select **Year** for the activity calendar; tap a day to view its sessions, then tap a session to view that book.
- Tap the book-history count beneath the overview metrics to browse all books in your statistics history.
- **Return statistics →** beneath the dashboard shows returns after breaks, both across all reading and for individual books. Choose a break length of 3, 7, or 14 days; tap a return to open its day journal or book journey.
- **Book journey →** in a book’s statistics shows its recorded reading periods, position curve, breaks, and confirmed finishes. Tap a reading period to open its first day; swipe or use arrows to browse older periods.
- **Book calendar →** below the overview or yearly heatmap opens a month grid with book-title ribbons and hourly activity bars. Tap a ribbon for book details, or an uncovered part of a day for its journal. Arrows move by month; double arrows move by year.
- Tap the **Year goal** header to see confirmed finishes, progress, and the yearly target. **Set yearly goal** changes that year’s target; 0 turns it off.
- **Book statistics** beneath a cover shows that book’s recorded history. **Record finish** lets you supply a completion date, including past years.
- **Library** shows a grid of books. Tap a book to select it; swipe to move between library pages.
- The sliders icon at the top opens **Settings**.
- **Settings → Choose books folder** lets you use your own books. Navigate to a folder and **long-press its name**, or the current-folder entry, then confirm **Choose**.
- **Settings → Refresh library** picks up files added over USB.
- **Settings → Daily reading goal** sets a minutes-per-day target; 0 turns it off.
- **Settings → Yearly book goal** sets this year’s books-to-finish target (default 24).
- **Settings → Reading statistics tools** pauses/resumes the default collector and opens KOReader’s original calendar or time-range tools.
- **Settings → Refresh statistics** reloads the recorded history.
- **Settings → Open sample library** returns to the bundled examples.
- **Show home on file browser entry** displays the custom home whenever KOReader enters its file browser. KOReader can still reopen its last book directly if that is your startup preference.
- Tap **×** to close the custom screen and use KOReader's normal file browser.

The plugin registers a **Kindlevel** gesture action too. You can assign it through KOReader's gesture settings for quicker access from a book.

## Formats and scope

The library asks KOReader which documents it supports. It scans nested folders and includes readable EPUB, PDF, MOBI, FB2, DJVU, TXT, and other formats supported by your KOReader installation. Format support depends on the installed reader and the document itself.

Books use embedded covers or KOReader custom covers when available. A document with no cover receives a typographic fallback. An optional adjacent `Book title.cover.png`, `.jpg`, or `.svg` can also supply its cover.

This version has statistics, local library browsing, covers, reading, and resume. Server connections, synchronization, and vocabulary review are future work. The Kindle plugin makes no network requests. Recording settings change only when you explicitly pause/resume the collector in Statistics tools.

The scan skips hidden folders, symbolic links, and Kindle `.sdr` directories. It stops at 1,000 books, 20,000 entries, or ten nested folder levels; a notice in Settings explains when some folders were skipped. Choose a smaller books folder if needed.

## Existing Reading Statistics data

Keep KOReader’s default **Reading statistics** plugin enabled. Kindlevel reads its existing `settings/statistics.sqlite3` directly through read-only SQLite connections. No import, duplicate collector, or replacement database is needed. Opening Kindlevel from a book uses KOReader’s normal save/close path, so its collector flushes the current activity first.

Overview pages count distinct book/page combinations **within each local calendar day**, matching KOReader’s daily grouping. Rereading on another day counts in that day’s total. Book lifetime totals count distinct pages across the whole book history. Reading time includes rereading; the per-page estimate uses KOReader’s configured maximum seconds per page. The `page_stat` view preserves KOReader’s adjustment when pagination changes after font or layout edits.

Session intervals come from the original activity records, merged when consecutive events in the same book have a gap of at most `max(30 seconds, min_sec)`, following the default timeline behavior. Counts use local calendar days; KOReader’s custom shifted-day calendar remains available in its original calendar tools. History outside your selected library folder is included. Empty, unavailable, or paused history is not replaced with demo data on Kindle.

## Yearly goals and the book calendar

The monthly calendar follows the reference layout: Monday-first weeks, day numbers, ribbons across consecutive days a book was read, and hourly duration histograms. Ribbons break at week boundaries and gaps with no recorded reading. Overlapping titles occupy separate lanes. Four-, five-, and six-week months are supported; a `+N` badge shows additional books when the cell has no room for another lane. The hourly bars are scaled against the busiest hour in the displayed month.

The year goal counts **confirmed finished books**, once per book per calendar year. KOReader’s statistics database does not contain completion dates. Kindlevel imports the `Finished` status and its recorded date from available document sidecars in your selected library and reading history, and saves those observed dates in its own settings. Books with an unknown finish date are not inferred from page counts. Use **Record finish** to backfill a date or record a finish for a book without statistics. Past-year targets and completions are retained.

Tap `×` next to a finished book in the goal view to remove it from that year, then confirm. That exclusion prevents automatic reimport; an explicit Record finish adds it back. Changing dates or removing a goal entry does not modify KOReader’s statistics database or its original Finished status. Previously unobserved completions cannot be recovered automatically if their sidecars have been deleted or their status/date has since changed.

## Book journeys and returns (development)

These features are in the development source and Mac preview; they are not in the linked v0.3.0 release.

A return is recorded when reading resumes after at least **3 full local calendar days** without recorded activity. The shared break selector offers 3, 7, or 14 days and saves the choice in Kindlevel’s preferences. An ongoing break does not count as a return. **Returning to reading** checks activity across every book; **Returning to books** checks each book independently, so reading another book does not end that book’s break. Counts cover all recorded history, with a separate last-30-days count. Typical break is the median length of completed qualifying breaks.

A book journey groups recorded reading days into periods separated by qualifying breaks. Reading days and the inclusive calendar span from the first to latest entry are shown separately. The curve shows the **furthest recorded position on each reading day**, normalized by the page count stored with that event, so font changes do not multiply events. Backward movement can appear on the curve. A position is not proof that earlier pages were read; periods are not automatically labeled as rereads. Shaded gaps show breaks, and finishes come only from the existing confirmed-completion ledger. Older databases without per-event page counts still show reading periods and returns, with position history marked unavailable.

Calculations use positive-duration activity, exclude future timestamps, and measure gaps in local calendar days across daylight-saving changes. They describe recorded history: pauses in the collector or missing records can appear as breaks. Native statistics stay read-only; Kindlevel does not add a second activity collector. Refresh statistics refreshes the journey data too.

`tests/journeys.lua` checks the native SQLite schema, layout normalization, global/book scope, break boundaries, daylight-saving dates, confirmed finishes, legacy databases, refresh, and native UI navigation. With the preview running, `python3 tests/journeys_preview.py` exercises the new screens interactively.

## Achievements (development)

The development source includes **42 achievements** and **19 original monochrome badge icons**. These changes are not in the linked v0.3.0 release. Tap the badge beside Settings or choose **Tools → Kindlevel achievements**. Use **All**, **Earned**, **Locked**, or **Book quests**; swipe or use arrows to browse. Tap a badge's text for its full description and recognition date, or **Preview →** to replay its notification without unlocking it. **Try over a book →** still demonstrates a notification on the actual reader. The Tools preview chooser has its own paginated list.

Milestones cover reading time, pages, confirmed finishes, historical best streaks, reading days, single-day records, returns, highlights, notes, authors and time windows. Book quests include **Don't Panic** (Hitchhiker's Guide), **The Spice Must Flow** (Dune), **Big Reader Is Watching** (1984), **There and Back Again** (The Hobbit), **One Does Not Simply Finish** (Lord of the Rings), **The White Whale** (Moby-Dick), a bundled-book starter badge, and **Dude...** for actually opening Mein Kampf. Read-specific-book conditions require recorded reading time; `open` quests trigger on ReaderReady with the document’s metadata, even with no statistics database. Opening quests are tracked from this version onward and are not inferred from files on the shelf or old reading totals. Having the file on your device does not qualify. Finish conditions require a confirmed finish, never a page-percentage guess.

Unlocks persist in Kindlevel's own `achievement_unlocks` ledger and are never revoked when a streak ends, a finish is removed, or history disappears. Existing history is recognized quietly on the first check, and eligible definitions added later are also backfilled quietly. Newly reached conditions display a corner notification. Recognition timestamps show when Kindlevel observed the condition, not the original date a historical milestone happened. XP is stored only in definitions and displayed as **reserved**; it is not awarded, totaled or used for levels.

Checks run when Kindlevel opens, history refreshes, a finish is recorded, and after native reader events. Page-driven checks run at most once every 30 seconds; annotation and save/resume events can check sooner. Kindlevel asks the default collector to flush its recorded page intervals, then reads the database through its existing read-only adapter. It does not time an idle reader or count rapid page tapping itself. Pending checks and notifications are cancelled on sleep/close as appropriate.

Page milestones use native normalized book/page counts per local day, including another day's rereading. Time uses original recorded durations so layout rescaling does not multiply intervals. Time-window rules use the local start hour of each recorded interval; overnight windows support midnight crossings. A `per_day` overnight rule groups by calendar date, not a night spanning two dates. Returns count full days without activity and have their own fixed trigger thresholds, independent of the statistics screen's break selector. Author variety counts distinct metadata author credits from books with at least 15 minutes of recorded reading. Unknown authors are excluded.

**Marathon Reader** requires three recorded hours in one session. A book switch, sleep, closing the reader, or a gap of more than 60 seconds ends the session. Short gaps contribute no reading time, and overlapping records count once. Original page intervals are streamed through the session calculation, so layout rescaling does not multiply time and the plugin does not keep all page events in memory. Kindlevel stores open-book metadata and session-boundary timestamps in its own settings. Intervals spanning an explicit pause are excluded because their before/after reading allocation is unknown. Older history infers sessions from book IDs and gaps; historical sleep/close boundaries cannot be recovered before this feature was installed.

### Add your own achievements

Edit `kindlevel_achievement_catalog.lua`, or copy **`custom_achievements.example.lua` → `custom_achievements.lua`** inside `kindlevel.koplugin`. The optional file returns a list of definitions and does not require changes to the engine, UI or notification code. Restart KOReader, or click Reload Lua in the Mac preview, after editing. Keep your custom file and icons when replacing the plugin during an upgrade.

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

Tests: `tests/achievement_rules.lua` covers rules, title matching, backfill, persistence, custom definitions and every catalog page/icon. `tests/achievements.lua` checks actual timers, queues, previews, native page turns and automatic unlock notifications with XP unused. With the Mac preview running, `python3 tests/achievements_preview.py` checks paging, filters, automatic repaint, clean dismissal and the reading overlay.

## Preview and debug on a Mac

Requires **Python 3.12+** and a running **Docker Desktop**. Run from the repository root:

```sh
python3 scripts/preview.py
```

The first run downloads a pinned official KOReader Linux runtime (about 28 MB), checks its SHA-256, and runs it in Docker. Open **http://127.0.0.1:8765** if the browser does not open automatically.

- The screen is rendered by the actual Kindlevel Lua code, KOReader widgets, fonts, and document engines.
- Click to tap; drag to swipe. Arrow keys navigate and Escape goes back.
- Edit the Lua files, then click **Reload Lua** to restart the renderer.
- The default is a clearly labeled, disposable demo history. These demo rows are never included in the Kindle plugin ZIP.
- Renderer errors appear in the browser; the full log is `.cache/preview/renderer.log`.
- Stop the preview with **Ctrl+C** in its terminal.

You can choose another port with `--port`, suppress automatic browser opening with `--no-open`, or supply an extracted runtime with `--runtime /path/to/runtime`.

To view your own history later, exit KOReader on Kindle, copy `settings/statistics.sqlite3` to your Mac, then run:

```sh
python3 scripts/preview.py --database /path/to/statistics.sqlite3
```

The preview uses SQLite’s backup API to make a separate local copy; the supplied database is opened read-only. Full book reading in the preview uses the bundled samples unless you add your own files to its disposable `.cache/preview/books/` folder. The browser is a desktop input/display bridge; e-ink refresh, suspend, and physical touch still need a Kindle check.

## Validation

Tested with the official **KOReader v2026.07.1 Linux ARM64 runtime**, using its real widgets, document engines, plugin loader, and reader navigation. Previews are rendered at **1072 × 1448**, matching the Paperwhite 10th generation's portrait resolution.

Integration checks cover the reader flow with the default statistics plugin enabled, native daily-query parity, pagination rescaling, rereading, streaks, the capped per-page estimate, Unicode metadata, read-only database protection, and touch-driven statistics navigation. Additional checks cover native completion-date import, yearly deduplication and persistence, removal/reimport behavior, leap years, overlapping ribbons, four-/six-week months, and the native goal editor. The live preview is also checked through HTTP for Lua reload, taps, swipes, keyboard navigation, and PNG rendering. Actual Kindle touch responsiveness, sleep behavior, and screen refresh still need your device check. Earlier KOReader versions have not been validated.

If a problem occurs, KOReader's `crash.log` in its installation directory is useful for diagnosis. The plugin can be disabled in the plugin manager or uninstalled by removing its folder after exiting KOReader.

## Development

Plugin source is in `kindlevel.koplugin/`. Its local preferences are stored in `kindlevel.lua` inside KOReader's settings directory. Reading positions remain in KOReader's normal document sidecars.

Build the installable archive with Python 3:

```sh
python3 scripts/build.py
```

The checked-in sample files and covers are already generated. `scripts/make_samples.py` rebuilds the original EPUB/TXT examples. `scripts/render_covers.lua` generates the covers using KOReader's fonts and framebuffer.

To run `tests/koreader_smoke.lua`, use an extracted official KOReader Linux ARM64 runtime in an ARM64 Linux environment. From the runtime's directory containing `luajit`, `reader.lua`, and `setupkoenv.lua`, run:

```sh
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./luajit /workspace/tests/koreader_smoke.lua
```

Run `tests/statistics.lua` the same way to check statistics calculations and UI. Mount this repository at `/workspace`, create `/workspace/dist/previews` first, and set `KO_HOME` to a disposable test directory. Tests use temporary copies of the books to keep reading state out of the install package. PNG previews are written to `dist/previews/`.

Licensed under AGPL-3.0-or-later. The sample stories and icon designs are original to this project.

With the preview running, verify the browser-to-renderer bridge with `python3 tests/preview_http.py`.
