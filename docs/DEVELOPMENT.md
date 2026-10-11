# Development guide

Run commands from the repository root unless noted otherwise.

Kindlevel v0.5.0 includes [Wi-Fi updates](UPDATES.md). The current development version, `0.6.0-dev`, adds [dashboard pairing and statistics sync](DASHBOARD.md). The installed version and release filenames come from `kindlevel.koplugin/kindlevel_version.lua`.

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

## Existing Reading Statistics data

Keep KOReader’s default **Reading statistics** plugin enabled. Kindlevel reads its existing `settings/statistics.sqlite3` directly through read-only SQLite connections. No import, duplicate collector, or replacement database is needed. Opening Kindlevel from a book uses KOReader’s normal save/close path, so its collector flushes the current activity first.

Overview pages count distinct book/page combinations **within each local calendar day**, matching KOReader’s daily grouping. Rereading on another day counts in that day’s total. Book lifetime totals count distinct pages across the whole book history. Reading time includes rereading; the per-page estimate uses KOReader’s configured maximum seconds per page. The `page_stat` view preserves KOReader’s adjustment when pagination changes after font or layout edits.

Session intervals come from the original activity records, merged when consecutive events in the same book have a gap of at most `max(30 seconds, min_sec)`, following the default timeline behavior. Counts use local calendar days; KOReader’s custom shifted-day calendar remains available in its original calendar tools. History outside your selected library folder is included. Empty, unavailable, or paused history is not replaced with demo data on Kindle.

## Yearly goals and the book calendar

The monthly calendar follows the reference layout: Monday-first weeks, day numbers, ribbons across consecutive days a book was read, and hourly duration histograms. Ribbons break at week boundaries and gaps with no recorded reading. Overlapping titles occupy separate lanes. Four-, five-, and six-week months are supported; a `+N` badge shows additional books when the cell has no room for another lane. The hourly bars are scaled against the busiest hour in the displayed month.

The year goal counts **confirmed finished books**, once per book per calendar year. KOReader’s statistics database does not contain completion dates. Kindlevel imports the `Finished` status and its recorded date from available document sidecars in your selected library and reading history, and saves those observed dates in its own settings. Books with an unknown finish date are not inferred from page counts. Use **Record finish** to backfill a date or record a finish for a book without statistics. Past-year targets and completions are retained.

Tap `×` next to a finished book in the goal view to remove it from that year, then confirm. That exclusion prevents automatic reimport; an explicit Record finish adds it back. Changing dates or removing a goal entry does not modify KOReader’s statistics database or its original Finished status. Previously unobserved completions cannot be recovered automatically if their sidecars have been deleted or their status/date has since changed.

## Book journeys and returns

These features are included in Kindlevel v0.4.0 and the Mac preview.

A return is recorded when reading resumes after at least **3 full local calendar days** without recorded activity. The shared break selector offers 3, 7, or 14 days and saves the choice in Kindlevel’s preferences. An ongoing break does not count as a return. **Returning to reading** checks activity across every book; **Returning to books** checks each book independently, so reading another book does not end that book’s break. Counts cover all recorded history, with a separate last-30-days count. Typical break is the median length of completed qualifying breaks.

A book journey groups recorded reading days into periods separated by qualifying breaks. Reading days and the inclusive calendar span from the first to latest entry are shown separately. The curve shows the **furthest recorded position on each reading day**, normalized by the page count stored with that event, so font changes do not multiply events. Backward movement can appear on the curve. A position is not proof that earlier pages were read; periods are not automatically labeled as rereads. Shaded gaps show breaks, and finishes come only from the existing confirmed-completion ledger. Older databases without per-event page counts still show reading periods and returns, with position history marked unavailable.

Calculations use positive-duration activity, exclude future timestamps, and measure gaps in local calendar days across daylight-saving changes. They describe recorded history: pauses in the collector or missing records can appear as breaks. Native statistics stay read-only; Kindlevel does not add a second activity collector. Refresh statistics refreshes the journey data too.

`tests/journeys.lua` checks the native SQLite schema, layout normalization, global/book scope, break boundaries, daylight-saving dates, confirmed finishes, legacy databases, refresh, and native UI navigation. With the preview running, `python3 tests/journeys_preview.py` exercises the new screens interactively.


[Achievement definitions and trigger reference](ACHIEVEMENTS.md) · [Project overview](../README.md).
