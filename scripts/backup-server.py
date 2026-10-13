#!/usr/bin/env python3
"""Back up a bind-mounted server database using SQLite's online backup API."""
import argparse
import datetime as dt
import os
from pathlib import Path
import sqlite3
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-dir', type=Path, default=ROOT / 'data')
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'backups')
    args = parser.parse_args()
    database = args.data_dir.resolve() / 'kindlevel.sqlite3'
    if not database.is_file():
        parser.error(f'No database at {database}. Use --data-dir for a different bind-mounted folder.')
    os.umask(0o077)
    args.output_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.snapshot-', dir=args.output_dir) as directory:
        temporary = Path(directory) / 'kindlevel.sqlite3'
        source = sqlite3.connect(database.as_uri() + '?mode=ro', uri=True, timeout=30)
        target = sqlite3.connect(temporary)
        try:
            source.backup(target, pages=100, sleep=0.1)
            if target.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
                raise RuntimeError('Backup database failed integrity verification')
        finally:
            target.close()
            source.close()
        name = 'kindlevel-' + dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ') + '.tar.gz'
        pending = args.output_dir / (name + '.tmp')
        with tarfile.open(pending, 'w:gz') as archive:
            archive.add(temporary, arcname='data/kindlevel.sqlite3')
            for name in ['compose.yaml', '.env']:
                path = ROOT / name
                if path.exists():
                    archive.add(path, arcname=name)
            setup_code = args.data_dir / 'setup-code'
            if setup_code.exists():
                archive.add(setup_code, arcname='data/setup-code')
        output = pending.with_suffix('')
        pending.replace(output)
        print(output.resolve())


if __name__ == '__main__':
    main()
