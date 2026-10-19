# Wi-Fi updates

The updater is included from v0.5.0. If you use v0.4.0 or earlier, install v0.5.0 over USB once; later stable releases can then be installed from the Kindle.

## Use it

1. Open **Kindlevel → Settings → Updates & recovery → Check for updates**, or **Tools → Kindlevel updates**.
2. Connect to Wi-Fi using KOReader's normal prompt.
3. If a newer stable release is available, review the installed and available versions and choose **Install & restart**.
4. Wait for the download and verification to finish. KOReader saves the open book and restarts after installation.

### Repair and recovery (v1.0.0)

Version 1.0.0 separates the reading app from its recovery updater:

- `kindlevel.koplugin/main.lua` is a small bootstrap; the reading app lives in `kindlevel_app.lua`.
- **`kindlevel-recovery.koplugin`** has its own updater, networking code, certificate bundle and UI. It does not import Kindlevel's app modules. App updates never replace this helper.
- **Tools → Kindlevel recovery → Update or reinstall over Wi-Fi** works if the app fails to load, or an interrupted install left its folder missing. When the latest release is already installed, the confirmation offers **Reinstall & restart**.
- **Restore previous version (offline)** restores the saved backup without downloading anything, while retaining current custom achievements and saved positions. The displaced plugin is kept in `.kindlevel-replaced-TIMESTAMP` beside the plugin folders.

For a USB installation, copy **both** plugin folders from the release ZIP into `koreader/plugins/`, then restart KOReader. When a working older updater installs this version over Wi-Fi, the bootstrap installs the recovery helper alongside the app on its next launch. The helper becomes independently discoverable on the following KOReader restart. A load failure during that first launch also exposes its recovery menu through the bootstrap. Keep both plugins enabled in KOReader's plugin manager.

**If your current version says a built-in Lua file was modified:** its old updater deliberately blocks that installation. Fully exit KOReader and install v1.0.0's two folders over USB once, replacing shipped files while keeping personal files. That installs the new update policy and recovery helper. Future verified updates replace modified built-in code after confirmation and retain your edits in the complete previous-plugin backup.

Recovery still needs a working KOReader installation, writable storage and, for downloads, a reachable GitHub release over verified HTTPS. It cannot guarantee updates through a failed network, damaged recovery files or incompatible KOReader. Updating the recovery helper itself is a separate USB maintenance operation; normal app upgrades preserve it.

Checks run only when requested. There is no automatic installation, startup network check or GitHub account requirement. GitHub's public release page and checksum file provide a fallback when its anonymous REST API is unavailable or rate-limited. Development builds may be newer than the latest published release; the updater does not downgrade them.

You can cancel during downloading and staging. The brief final installation phase is not cancellable.

## Files and recovery

Reading statistics, goals and achievement preferences remain in KOReader's settings directories. The updater preserves `custom_achievements.lua`, custom icons, other unmanaged plugin files and sample-book sidecars, including changes saved immediately before installation. Modified built-in assets are preserved when a readable installed manifest identifies them. From v1.0.0, modified built-in Lua files are replaced by verified release files and retained in the full backup. A damaged installed manifest no longer blocks repair. Stable v0.7.0 and older updaters still reject modified built-in Lua files.

The backup is the previous installation, not a permanent archive. Save any built-in code edits you want to keep before another update replaces that backup. Keep personal achievements in `custom_achievements.lua`.

The install ZIP and each managed plugin file are checked against SHA-256 digests. Downloads use verified HTTPS with certificate-chain and hostname checks. Archive paths, file types, sizes, manifest entries, Lua syntax and the declared version are checked before activation. The bundled Mozilla certificate data is under MPL-2.0; see [NOTICE](../kindlevel.koplugin/NOTICE.md).

The previous plugin directory is retained as `koreader/plugins/.kindlevel-backup`. If activation fails, the updater attempts to restore it. Staging uses a separate folder on the same filesystem. The directory swap requires two renames. If a power loss leaves the main folder missing, the independent recovery plugin can install the latest release over Wi-Fi or restore the backup offline. On older installations without recovery, exit KOReader and rename `.kindlevel-backup` back to `kindlevel.koplugin` over USB.

Keep Wi-Fi connected during the download. The updater retries transient download failures once, starts failed downloads afresh, and distinguishes DNS, timeout and TLS failures. If HTTPS verification fails, check the Kindle's date and time. The updater supports direct HTTPS connections; custom HTTP proxies are not supported.

## Building releases

`kindlevel.koplugin/kindlevel_version.lua` is the source for the installed version and build filenames. Set it to the new version, then run:

```sh
python3 scripts/build.py
```

The ZIP contains `update-manifest.json` with the version, managed filenames, sizes and SHA-256 digests. User-side `custom_achievements.lua` and `.sdr` files are excluded. Publish a stable GitHub release with the matching version tag, `kindlevel-VERSION.zip` and `kindlevel-VERSION.zip.sha256`. Keep the manifest and checksum files intact. The ZIP also contains a separate recovery plugin, assembled from the canonical updater sources by `scripts/build.py`. Its templates are in `kindlevel.koplugin/recovery/`; the bootstrap copies the same sources for Wi-Fi migrations. Root-level documentation remains outside KOReader's installation files.

## Validation

Generate disposable fixtures with `python3 tests/updater_fixtures.py`. In the official KOReader runtime with the repository mounted at `/workspace`, run `tests/updater.lua` to check version ordering, malformed packages, checksums, protected paths, modified-code updates, reinstall, missing-folder recovery, offline rollback, download retries and custom-file preservation. `tests/updater_ui.lua` uses actual widgets and subprocesses to verify the confirmation, installation, open-book saving and restart request. `tests/recovery_ui.lua` verifies helper installation and independent Wi-Fi repair with deliberately broken app, version and updater files. These tests use simulated releases; they do not publish to GitHub or replace the source checkout.

`tests/updater_network.lua` performs a read-only live HTTPS check against the official public repository and downloads its checksum. It requires internet access. Physical Kindle Wi-Fi, restart and storage behavior still need device testing.

[Project overview](../README.md) · [Development guide](DEVELOPMENT.md)
