#!/usr/bin/env python3
"""Build a portable KOReader plugin archive using only the Python standard library."""
from pathlib import Path
import hashlib
import json
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / "kindlevel.koplugin"
VERSION = re.fullmatch(r'\s*return "([0-9A-Za-z.+-]+)"\s*', (PLUGIN / "kindlevel_version.lua").read_text()).group(1)


def main():
    output = ROOT / "dist"
    output.mkdir(exist_ok=True)
    target = output / f"kindlevel-{VERSION}.zip"
    files = sorted(p for p in PLUGIN.rglob("*") if p.is_file() and p.name not in {".DS_Store", "custom_achievements.lua", "update-manifest.json"}
                   and not any(part.endswith(".sdr") for part in p.parts))
    if not files or not (PLUGIN / "books" / "A Quiet Beginning.epub").exists():
        raise SystemExit("Plugin or sample books missing. Run scripts/make_samples.py first.")
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        manifest_files = []
        for path in files:
            archive.write(path, path.relative_to(ROOT))
            data = path.read_bytes()
            manifest_files.append({"path": path.relative_to(PLUGIN).as_posix(), "size": len(data), "sha256": hashlib.sha256(data).hexdigest()})
        archive.write(ROOT / "README.md", "INSTALL.txt")
        archive.write(ROOT / "README.md", "README.md")
        for path in sorted((ROOT / "docs").rglob("*.md")):
            archive.write(path, path.relative_to(ROOT))
        archive.write(ROOT / "LICENSE", "LICENSE")
        archive.write(ROOT / "LICENSE", "kindlevel.koplugin/LICENSE")
        license_data = (ROOT / "LICENSE").read_bytes()
        manifest_files.append({"path": "LICENSE", "size": len(license_data), "sha256": hashlib.sha256(license_data).hexdigest()})
        archive.writestr("kindlevel.koplugin/update-manifest.json", json.dumps({"schema": 1, "version": VERSION, "files": manifest_files}, indent=2)+"\n")
    checksum = hashlib.sha256(target.read_bytes()).hexdigest()
    target.with_suffix(".zip.sha256").write_text(f"{checksum}  {target.name}\n")
    print(f"Built {target}: {len(files)} plugin files, {target.stat().st_size:,} bytes")
    print(f"SHA256 {checksum}")


if __name__ == "__main__":
    main()
