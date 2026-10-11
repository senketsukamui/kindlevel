# Kindlevel

A reading home for KOReader, built for jailbroken Kindles. Browse your library, follow your reading habits, and unlock achievements as you read.

Works offline. No account or server required. KOReader handles document rendering, saved positions and reading activity.

[Download v0.5.0](https://github.com/senketsukamui/kindlevel/releases/download/v0.5.0/kindlevel-0.5.0.zip) · [Current source](https://github.com/senketsukamui/kindlevel/archive/refs/heads/main.zip)

## Features

- **Reading home:** cover carousel, local library, reading progress and resume.
- **Statistics:** reading time, pages, streaks, daily journals and book details using your existing KOReader history.
- **Calendars:** yearly heatmaps and monthly book timelines with reading activity bars.
- **Goals:** daily reading targets and yearly goals based on confirmed finished books.
- **Book journeys:** reading periods, breaks and returns to individual books or reading in general.
- **Achievements:** 42 badges covering milestones, habits and book quests, with corner notifications and support for custom definitions.
- **Multiple formats:** EPUB, PDF, MOBI, FB2, TXT and other documents supported by your KOReader installation.

**Early development:** v0.5.0 includes all the features listed above and Wi-Fi updates. XP is reserved for future progression.

## Install

Requires a jailbroken Kindle with KOReader installed. Keep KOReader’s **Reading statistics** plugin enabled to collect reading history.

1. Download the release ZIP, or the current source ZIP for development features, and extract it.
2. Exit KOReader and connect your Kindle over USB.
3. Copy the entire `kindlevel.koplugin` folder into `koreader/plugins/` on the Kindle. `main.lua` must be directly inside `koreader/plugins/kindlevel.koplugin/`.
4. Eject the Kindle, start KOReader, and open **Tools → Kindlevel**. Enable the plugin in KOReader’s plugin manager if needed.

Three original sample books are included. To use your own library, open **Settings → Choose books folder**, long-press the folder name and confirm **Choose**.

To open Kindlevel automatically, enable **Show home on file browser entry** in its settings and set KOReader’s **Start with** option to **file browser**.

Kindlevel reads the existing statistics database through read-only connections and stores its goals and achievement unlocks separately. Reading positions stay in KOReader’s document settings.

## Wi-Fi updates

Install v0.5.0 over USB once if you use v0.4.0 or earlier. After that, use **Settings → Check for updates** or **Tools → Kindlevel updates** to install newer stable GitHub releases over Wi-Fi. Downloads are verified, custom achievements and icons are preserved, and KOReader restarts after installation. [Update guide](docs/UPDATES.md).

## Development

### Web dashboard preview

A Go/Svelte dashboard with owner login and Kindle statistics sync is available as one Docker container:

```sh
docker compose up --build -d
```

Open **http://localhost:8080** and create your account using the setup code from `docker compose exec kindlevel cat /data/setup-code`. Pair a Kindle from **Your Kindle** to replace demo data with your books, statistics and achievements. Server sync requires the current development plugin; v0.5.0 does not include it. [Setup, LAN testing and HTTPS deployment](docs/DASHBOARD.md).

### Kindle plugin preview

Preview the actual KOReader interface on your computer with Python 3.12+ and Docker:

```sh
python3 scripts/preview.py
```

Open **http://127.0.0.1:8765**. The preview uses demo history; click to tap, drag to swipe and use **Reload Lua** after edits.

Build a local install ZIP from your working tree with `python3 scripts/build.py`.

The interface and reader flow have been tested in the official KOReader v2026.07.1 Linux ARM64 runtime at the Paperwhite 10th generation’s resolution. Physical Kindle testing is pending.

[Development and testing guide](docs/DEVELOPMENT.md) · [Custom achievements and trigger reference](docs/ACHIEVEMENTS.md)

## Roadmap

- [ ] Kindle testing and tuning for touch, sleep and screen refresh.
- [ ] XP, levels and character outfits that evolve with reading progress.
- [ ] Reading suggestions based on available time: “I have 15 minutes.”
- [ ] A web app for books, statistics and highlights, self-hosted on your own server.
- [ ] Book and highlight synchronization between the Kindle and web app, with offline support.
- [ ] Highlight review.

## Contributing

Bug reports, ideas and pull requests are welcome. For bugs, include your Kindle model, KOReader version, steps to reproduce and relevant `crash.log` output.

## License

[AGPL-3.0-or-later](LICENSE). Sample stories and badge artwork are original to this project. See [NOTICE](kindlevel.koplugin/NOTICE.md) for attribution.
