# Web dashboard and Kindle connection

Kindlevel's dashboard uses Go, Svelte and SQLite in one Docker container. It supports owner login, Kindle pairing, and manual uploads of books, reading statistics and achievements. Node is used only during the build.

## Start and create your account

From the repository root:

```sh
docker compose up --build -d
docker compose exec kindlevel cat /data/setup-code
```

Open **http://localhost:8080**, enter the setup code, and choose an owner username and password. The setup code is generated on the first start and removed after account creation. Passwords are hashed; browser sessions expire after seven days and signing out invalidates the session.

The `kindlevel-data` volume holds the account, device registrations, goals and reading snapshots. Container upgrades retain it. Keep this volume in your server backups; do not remove it when upgrading. Databases from the initial demo dashboard are migrated automatically.

## Pair your Kindle

1. Install **v0.6.0 or newer**, which includes sync and public HTTP after approval. v0.5.0 does not contain sync. Use the release ZIP or build with `python3 scripts/build.py`, fully exit KOReader, then copy the contents of the ZIP's `kindlevel.koplugin` folder into the existing `koreader/plugins/kindlevel.koplugin/` over USB, replacing shipped files. Keep personal files. Start KOReader again and confirm the new version in Kindlevel's Settings footer.
2. In the web dashboard, open **Your Kindle → Pair a Kindle**. The code expires after ten minutes and can be used once.
3. On Kindle, open **Kindlevel → Settings → Web dashboard → Connect to server**, or **Tools → Kindlevel web dashboard**.
4. Enter the reachable server address, pairing code and Kindle name.
5. Choose **Sync now**. Connect through KOReader's Wi-Fi prompt. The dashboard refreshes every thirty seconds; **Refresh** updates it immediately.

The server gives each Kindle a separate token. **Revoke access** in the dashboard prevents further uploads while retaining its reading history. **Forget connection** on Kindle removes local credentials; it does not revoke the old token on the server.

### Test on your Mac or local network

Both devices must be on the same trusted network. Start the container with a LAN binding:

```sh
KINDLEVEL_BIND_ADDRESS=0.0.0.0 docker compose up --build -d
```

Find your Mac's Wi-Fi address in macOS Network settings. If it is `192.168.1.50`, enter **http://192.168.1.50:8080** on Kindle. Allow macOS firewall access if prompted. “localhost” on Kindle refers to the Kindle itself.

The plugin asks you to explicitly approve unencrypted HTTP and saves that choice for the paired server. Public IP addresses and hostnames are supported too. HTTP does not encrypt login or sync traffic. [Simple VPS setup](VPS.md).

### Host on a VPS

Follow the [VPS setup guide](VPS.md) for a fresh-server installation with one container and a persistent data folder. The setup helper prints the address and first-run account code.

For an existing HTTPS reverse proxy, set `KINDLEVEL_PUBLIC_URL` to the final HTTPS domain. The plugin verifies certificate chains and hostnames; self-signed certificates, HTTP proxies and server subpaths are not supported. Sync requests do not follow redirects.

## What syncs

- Books present in KOReader's statistics database, with titles, authors, page counts and confirmed completion dates.
- Reading position and format when matching document sidecars are available. Unknown positions are not estimated from pages read.
- Daily book activity using KOReader's normalized `page_stat` view, matching the plugin's daily time/page metrics.
- The full expandable achievement catalogue, progress and existing unlocks. Custom artwork uses a built-in fallback until icon uploads are added.
- Daily/yearly goals on the first successful sync, unless you have already edited the dashboard goals.

Each Kindle has its own complete snapshot. The dashboard initially shows demo data; after a device's first upload it shows that device's history. Select a Kindle on the device page to switch histories. Separate devices are not summed together.

Sync is manual. It saves the open book's position and flushes native statistics without closing the reader. KOReader normally records the current page's time when you turn the page or close the book, so an ongoing page interval may appear on your next sync.

A pending snapshot is saved locally before uploading. Interrupted or failed requests retry the identical snapshot; after it is acknowledged, a retry also uploads the current history. The server checks increasing sequences and replaces the previous snapshot transactionally. Repeated requests do not add reading time twice; newer snapshots also remove records deleted from the Kindle.

The current limits are 8 MiB per snapshot, 5,000 statistics books, 100,000 book-day records and 2,000 achievement definitions. Native KOReader data remains unchanged by the exporter. Local credentials are in `settings/kindlevel-sync.json`, and pending uploads are in `kindlevel-sync/pending.json` under KOReader's data directory. Do not share the credential file when reporting bugs.

Book files, cover uploads, highlights, web reading and changes from the dashboard back to Kindle are not implemented yet. Dashboard goals remain independent after their initial import. XP remains reserved metadata. A missing statistics database can upload empty history; an unreadable database stops the upload and retains the server copy.

## Develop and verify

Requires Go 1.26+ and Node 22.12+ (or 24+):

```sh
cd server/web
npm ci
npm run build
cd ..
go run .
```

Native data is stored in `server/data/`; the setup code is `server/data/setup-code`. For frontend hot reload, run `npm run dev` in `server/web` while Go runs on port 8080.

| Variable | Native default | Docker default |
| --- | --- | --- |
| `KINDLEVEL_ADDR` | `:8080` | `:8080` |
| `KINDLEVEL_DATA_DIR` | `data` | `/data` |
| `KINDLEVEL_WEB_DIR` | `web/dist` | `/app/web` |
| `KINDLEVEL_PUBLIC_URL` | Empty | Empty (set by the VPS helper) |
| `TZ` | Host timezone | `UTC` |

`KINDLEVEL_BIND_ADDRESS` controls Compose's host binding, defaulting to `127.0.0.1`. The container runs as a non-root user with a read-only root filesystem and a writable data volume. `/healthz` checks database availability. Real calendar dates use the Kindle's reported timezone offset; demo dates use the server timezone.

```sh
cd server
go test ./...
cd web
npm run check
npm test
npx playwright install chromium
npx playwright test
```

Browser tests launch an isolated backend on port 8083 with disposable credentials and history. They cover login, goal persistence, desktop/mobile layouts, pairing, real history, revocation and empty devices. Screenshots go to the ignored `dist/previews/` directory.

`tests/sync.lua` and `tests/sync_ui.lua` run in the official KOReader runtime, with the repository mounted at `/workspace`. They verify statistics parity, durable retries, address validation, actual pairing dialogs, open-book saving and subprocess uploads. `tests/sync_live.lua` verifies actual LuaSocket requests against a local Go backend; `tests/sync_server_fixture.py` prepares and checks its disposable account and pairing code on port 8082.

Physical Kindle Wi-Fi, sleep and TLS behavior still need device testing. The plugin remains usable offline without a server.

[Project overview](../README.md)
