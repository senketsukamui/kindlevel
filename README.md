# Kindlevel for KOReader

A local Kindle app inspired by the reel, with reading statistics, an activity calendar, a cover carousel, and a local book library. Book rendering, saved positions, and activity recording are handled by KOReader.

**[Download v0.2.0](https://github.com/senketsukamui/kindlevel/releases/download/v0.2.0/kindlevel-0.2.0.zip)** · [Release and installation notes](https://github.com/senketsukamui/kindlevel/releases/tag/v0.2.0)

## Install on your Paperwhite 10th generation

KOReader must already be installed. This package is a plugin; it does not include KOReader or require a new jailbreak.

1. Download **`kindlevel-0.2.0.zip`** from the [GitHub release](https://github.com/senketsukamui/kindlevel/releases/tag/v0.2.0) and unzip it on your computer. The installable ZIP is in the release assets; GitHub's automatic **Source code** archives are for development.
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
- **Statistics** shows period totals and a daily chart. Select **Year** for the activity calendar; tap a day to view its sessions, then tap a session to view that book.
- Tap the book-history count beneath the overview metrics to browse all books in your statistics history.
- **Book statistics** beneath a cover shows that book’s recorded history.
- **Library** shows a grid of books. Tap a book to select it; swipe to move between library pages.
- The sliders icon at the top opens **Settings**.
- **Settings → Choose books folder** lets you use your own books. Navigate to a folder and **long-press its name**, or the current-folder entry, then confirm **Choose**.
- **Settings → Refresh library** picks up files added over USB.
- **Settings → Daily reading goal** sets a minutes-per-day target; 0 turns it off.
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

Integration checks cover the reader flow with the default statistics plugin enabled, native daily-query parity, pagination rescaling, rereading, streaks, the capped per-page estimate, Unicode metadata, read-only database protection, and touch-driven statistics navigation. The live preview is also checked through HTTP for Lua reload, taps, swipes, keyboard navigation, and PNG rendering. Actual Kindle touch responsiveness, sleep behavior, and screen refresh still need your device check. Earlier KOReader versions have not been validated.

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
