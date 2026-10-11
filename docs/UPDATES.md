# Wi-Fi updates

The updater is included from v0.5.0. If you use v0.4.0 or earlier, install v0.5.0 over USB once; later stable releases can then be installed from the Kindle.

## Use it

1. Open **Kindlevel → Settings → Check for updates**, or **Tools → Kindlevel updates**.
2. Connect to Wi-Fi using KOReader's normal prompt.
3. If a newer stable release is available, review the installed and available versions and choose **Install & restart**.
4. Wait for the download and verification to finish. KOReader saves the open book and restarts after installation.

Checks run only when requested. There is no automatic installation, startup network check or GitHub account requirement. GitHub's public release page and checksum file provide a fallback when its anonymous REST API is unavailable or rate-limited. Development builds may be newer than the latest published release; the updater does not downgrade them.

You can cancel during downloading and staging. The brief final installation phase is not cancellable.

## Files and recovery

Reading statistics, goals and achievement preferences remain in KOReader's settings directories. The updater preserves `custom_achievements.lua`, custom icons, other unmanaged plugin files and sample-book sidecars, including changes saved immediately before installation. Modified built-in assets are preserved when the previous package's manifest identifies them. Modified built-in Lua files stop the update instead of being overwritten; keep personal achievements in `custom_achievements.lua`, or upgrade edited code manually using USB.

The install ZIP and each managed plugin file are checked against SHA-256 digests. Downloads use verified HTTPS with certificate-chain and hostname checks. Archive paths, file types, sizes, manifest entries, Lua syntax and the declared version are checked before activation. The bundled Mozilla certificate data is under MPL-2.0; see [NOTICE](../kindlevel.koplugin/NOTICE.md).

The previous plugin directory is retained as `koreader/plugins/.kindlevel-backup`. If activation fails, the updater attempts to restore it. Staging uses a separate folder on the same filesystem. The directory swap requires two renames: a power loss between them may require restoring the backup over USB. Exit KOReader before a manual restore, and rename `.kindlevel-backup` back to `kindlevel.koplugin` if the active folder is missing.

Keep Wi-Fi connected during the download. If HTTPS verification fails, check the Kindle's date and time. The updater supports direct HTTPS connections; custom HTTP proxies are not supported.

## Building releases

`kindlevel.koplugin/kindlevel_version.lua` is the source for the installed version and build filenames. Set it to the new version, then run:

```sh
python3 scripts/build.py
```

The ZIP contains `update-manifest.json` with the version, managed filenames, sizes and SHA-256 digests. User-side `custom_achievements.lua` and `.sdr` files are excluded. Publish a stable GitHub release with the matching version tag, `kindlevel-VERSION.zip` and `kindlevel-VERSION.zip.sha256`. Keep the manifest and checksum files intact. The updater installs the plugin folder and leaves root-level documentation outside KOReader's own installation files.

## Validation

Generate disposable fixtures with `python3 tests/updater_fixtures.py`. In the official KOReader runtime with the repository mounted at `/workspace`, run `tests/updater.lua` to check version ordering, malformed packages, checksums, protected paths, custom-file preservation and rollback. `tests/updater_ui.lua` uses actual widgets and subprocesses to verify the confirmation, installation, open-book saving and restart request. Its incoming release is simulated; it does not publish to GitHub or replace the source checkout.

`tests/updater_network.lua` performs a read-only live HTTPS check against the official public repository and downloads its checksum. It requires internet access. Physical Kindle Wi-Fi, restart and storage behavior still need device testing.

[Project overview](../README.md) · [Development guide](DEVELOPMENT.md)
