# Kindlevel — Reading Home for KOReader

A first local Kindle app inspired by the reel: a quiet reading home with a cover carousel, a local book library, and settings. Book rendering and saved reading positions are handled by KOReader.

**[Download v0.1.0](https://github.com/senketsukamui/kindlevel/releases/download/v0.1.0/reading-home-0.1.0.zip)** · [Release and installation notes](https://github.com/senketsukamui/kindlevel/releases/tag/v0.1.0)

## Install on your Paperwhite 10th generation

KOReader must already be installed. This package is a plugin; it does not include KOReader or require a new jailbreak.

1. Download **`reading-home-0.1.0.zip`** from the [GitHub release](https://github.com/senketsukamui/kindlevel/releases/tag/v0.1.0) and unzip it on your computer. The installable ZIP is in the release assets; GitHub's automatic **Source code** archives are for development.
2. Exit KOReader, then connect the Kindle over USB.
3. Copy the **entire `readinghome.koplugin` folder** into the `plugins` directory inside your KOReader installation. For a typical installation, the USB drive should contain:

   ```text
   koreader/
     reader.lua
     plugins/
       readinghome.koplugin/
         main.lua
         _meta.lua
         readinghome_library.lua
         readinghome_screen.lua
         assets/
         books/
   ```

   On the Kindle, that is usually `/mnt/us/koreader/plugins/readinghome.koplugin/`. If your installation is elsewhere, use the directory containing KOReader's `reader.lua`.

4. Safely eject the Kindle, disconnect USB, and start KOReader.
5. Open the main menu, go to the **Tools** section, and choose **Reading Home**. If it is missing, open KOReader's plugin manager, enable **Reading Home**, and restart KOReader. External plugins must be allowed in KOReader's plugin settings.

**Do not create an extra nesting level.** `main.lua` must be directly inside `plugins/readinghome.koplugin/`.

## Try it

The first launch shows three original sample books: two EPUBs and one plain-text document.

- Swipe left/right or tap a neighboring cover to select a book.
- Tap the large cover or **Start reading** to open it in KOReader.
- Turn pages using KOReader's usual gestures and controls.
- To return, open KOReader's main menu and choose **Reading Home**. This saves and closes the book, then restores the custom home.
- The selected book's saved completion percentage appears beneath its cover. Tap **Continue reading** to resume.
- **Library** shows a grid of books. Tap a book to select it; swipe to move between library pages.
- **Settings → Choose books folder** lets you use your own books. Navigate to a folder and **long-press its name**, or the current-folder entry, then confirm **Choose**.
- **Settings → Refresh library** picks up files added over USB.
- **Settings → Open sample library** returns to the bundled examples.
- **Show home on file browser entry** displays the custom home whenever KOReader enters its file browser. KOReader can still reopen its last book directly if that is your startup preference.
- Tap **×** to close the custom screen and use KOReader's normal file browser.

The plugin registers a **Reading Home** gesture action too. You can assign it through KOReader's gesture settings for quicker access from a book.

## Formats and scope

The library asks KOReader which documents it supports. It scans nested folders and includes readable EPUB, PDF, MOBI, FB2, DJVU, TXT, and other formats supported by your KOReader installation. Format support depends on the installed reader and the document itself.

Books use embedded covers or KOReader custom covers when available. A document with no cover receives a typographic fallback. An optional adjacent `Book title.cover.png`, `.jpg`, or `.svg` can also supply its cover.

This version has local library browsing, covers, reading, and resume. Server connections, synchronization, statistics, and vocabulary review are future work. It makes no network requests. It does not change KOReader's reading or statistics settings.

The scan skips hidden folders, symbolic links, and Kindle `.sdr` directories. It stops at 1,000 books, 20,000 entries, or ten nested folder levels; a notice in Settings explains when some folders were skipped. Choose a smaller books folder if needed.

## Validation

Tested with the official **KOReader v2026.07.1 Linux ARM64 runtime**, using its real widgets, document engines, plugin loader, and reader navigation. Previews are rendered at **1072 × 1448**, matching the Paperwhite 10th generation's portrait resolution.

The integration checks cover scanning, metadata, cover rendering, touch areas, carousel and library navigation, empty folders, EPUB and TXT opening, saving reading position, returning to the custom home, and resuming. Actual Kindle touch responsiveness, sleep behavior, and screen refresh still need your device check. Earlier KOReader versions have not been validated.

If a problem occurs, KOReader's `crash.log` in its installation directory is useful for diagnosis. The plugin can be disabled in the plugin manager or uninstalled by removing its folder after exiting KOReader.

## Development

Plugin source is in `readinghome.koplugin/`. Its local preferences are stored in `readinghome.lua` inside KOReader's settings directory. Reading positions remain in KOReader's normal document sidecars.

Build the installable archive with Python 3:

```sh
python3 scripts/build.py
```

The checked-in sample files and covers are already generated. `scripts/make_samples.py` rebuilds the original EPUB/TXT examples. `scripts/render_covers.lua` generates the covers using KOReader's fonts and framebuffer.

To run `tests/koreader_smoke.lua`, use an extracted official KOReader Linux ARM64 runtime in an ARM64 Linux environment. From the runtime's directory containing `luajit`, `reader.lua`, and `setupkoenv.lua`, run:

```sh
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./luajit /workspace/tests/koreader_smoke.lua
```

Mount this repository at `/workspace` and create `/workspace/dist/previews` first. Tests use temporary copies of the books to keep reading state out of the install package. PNG previews are written to `dist/previews/`.

Licensed under AGPL-3.0-or-later. The sample stories and icon designs are original to this project.
