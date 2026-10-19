# Kindlevel

A reading home for KOReader: browse your library, follow your reading habits, and collect achievements. Add an optional self-hosted dashboard to see your reading history in a browser.

The plugin works offline. KOReader handles document rendering, saved positions and reading activity.

[Stable plugin release](https://github.com/senketsukamui/kindlevel/releases/latest) · [VPS setup](docs/VPS.md) · [Development](docs/DEVELOPMENT.md)

## Features

- A cozy pixel reading home, searchable local library and one-tap resume.
- Reading time, pages, streaks, daily journals and book details.
- Yearly heatmaps, monthly book timelines and reading goals.
- Book journeys, breaks and returns.
- 42 achievements with corner notifications and custom definitions.
- EPUB, PDF, MOBI, FB2, TXT and other formats supported by KOReader.
- Optional Go/Svelte dashboard with device pairing and automatic statistics sync over Wi-Fi.

**Release status:** v1.0.0 brings the Pocket Ledger design to the plugin and dashboard, with a separate recovery updater for Wi-Fi repair. Automatic statistics sync remains available. Ongoing development is on [`develop`](https://github.com/senketsukamui/kindlevel/tree/develop). XP, levels and character outfits are planned.

## Install on Kindle

Requires a jailbroken Kindle with KOReader. Keep its **Reading statistics** plugin enabled. Other KOReader platforms have not been verified.

1. Download the plugin release ZIP, or build a source checkout with `python3 scripts/build.py`.
2. **Fully exit KOReader**, then connect the Kindle over USB.
3. Copy both `kindlevel.koplugin` and `kindlevel-recovery.koplugin` from the ZIP into `koreader/plugins/`. For an existing installation, replace shipped files inside those folders while keeping personal files. Avoid nesting another plugin folder inside either one.
4. Start KOReader and open **Tools → Kindlevel**. Check the version in Kindlevel's Settings footer.

Keep both plugins enabled. **Tools → Kindlevel recovery** provides Wi-Fi repair and offline rollback, even if the main plugin cannot load. If an older updater rejects modified Lua files, install both folders over USB once. See [updates and recovery](docs/UPDATES.md).

Three original sample books are included. Select your library through **Settings → Library → Choose books folder**. For automatic opening, turn **Settings → Reading preferences → Startup home** on and set KOReader's **Start with** option to **file browser**.

Kindlevel reads native statistics through read-only connections. Its goals and unlocks are stored separately; reading positions stay in KOReader's document settings.

## Self-host the dashboard

On a VPS with Docker, Compose and Python 3, from a v1.0.0 source checkout:

```sh
sudo ./scripts/setup-server.sh http://YOUR_VPS_IP
```

Open the displayed address, create your account using the printed setup code, and select **Your Kindle → Pair a Kindle**. Install v0.7.0 or newer on the Kindle, then connect through **Settings → Web dashboard**. Statistics sync automatically while KOReader is awake and Wi-Fi is connected.

The server runs in one container with SQLite. HTTP does not encrypt login or sync traffic. [Fresh-server setup, backups and troubleshooting](docs/VPS.md).

Sync currently uploads book metadata, statistics and achievements. Book files, covers and highlights are planned. [Connection details](docs/DASHBOARD.md).

## Updates and development

From v0.5.0, the plugin can install newer stable GitHub releases over Wi-Fi. In v1.0.0, use **Settings → Updates & recovery → Check for updates**. Older versions need one USB upgrade. [Update guide](docs/UPDATES.md).

Preview the actual plugin with Python 3.12+ and Docker:

```sh
python3 scripts/preview.py
```

Open **http://127.0.0.1:8765**. For a local dashboard preview, run `docker compose up --build -d` and open **http://localhost:8080**.

Native reader flows are tested in KOReader's Linux ARM64 runtime; the dashboard is checked on desktop and mobile browsers. Physical device behavior still needs testing.

## Roadmap

- [ ] Device testing and touch/e-ink tuning.
- [ ] Book files, covers and highlights synced with the self-hosted web app.
- [ ] Highlight review.
- [ ] XP, levels and character outfits.
- [ ] Reading suggestions based on available time.

## Contributing

Include your device, KOReader version, reproduction steps and relevant `crash.log` output in bug reports. Do not include device tokens, setup codes or personal databases.

[Custom achievements](docs/ACHIEVEMENTS.md) · [Developer guide](docs/DEVELOPMENT.md)

## License

[AGPL-3.0-or-later](LICENSE). Sample stories and badge artwork are original to this project. See [NOTICE](kindlevel.koplugin/NOTICE.md) for attribution.
