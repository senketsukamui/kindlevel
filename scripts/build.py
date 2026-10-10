#!/usr/bin/env python3
"""Build a portable KOReader plugin archive using only the Python standard library."""
from pathlib import Path
import hashlib
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / "kindlevel.koplugin"
VERSION = "0.1.1"


def main():
    output = ROOT / "dist"
    output.mkdir(exist_ok=True)
    target = output / f"kindlevel-{VERSION}.zip"
    files = sorted(p for p in PLUGIN.rglob("*") if p.is_file() and p.name != ".DS_Store"
                   and not any(part.endswith(".sdr") for part in p.parts))
    if not files or not (PLUGIN / "books" / "A Quiet Beginning.epub").exists():
        raise SystemExit("Plugin or sample books missing. Run scripts/make_samples.py first.")
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            archive.write(path, path.relative_to(ROOT))
        archive.write(ROOT / "README.md", "INSTALL.txt")
        archive.write(ROOT / "LICENSE", "kindlevel.koplugin/LICENSE")
    checksum = hashlib.sha256(target.read_bytes()).hexdigest()
    target.with_suffix(".zip.sha256").write_text(f"{checksum}  {target.name}\n")
    print(f"Built {target}: {len(files)} plugin files, {target.stat().st_size:,} bytes")
    print(f"SHA256 {checksum}")


if __name__ == "__main__":
    main()
