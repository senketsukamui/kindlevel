#!/bin/sh
# Configure and start one dashboard container from a fresh checkout.
set -eu
umask 077

usage() {
    printf 'Usage: %s http://YOUR_VPS_IP[:PORT]\n' "$0" >&2
    exit 2
}
[ "$#" -eq 1 ] || usage
command -v python3 >/dev/null 2>&1 || { printf 'Install Python 3 first.\n' >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { printf 'Install Docker Engine and its Compose plugin first. See docs/VPS.md.\n' >&2; exit 1; }
docker compose version >/dev/null
docker info >/dev/null 2>&1 || { printf 'Docker is not available. Start Docker and run this command with Docker access (sudo on a VPS).\n' >&2; exit 1; }

task_project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$task_project_dir"
task_public_url=$1
if [ ! -f .env ] && [ -n "$(docker compose ps -q kindlevel 2>/dev/null)" ]; then
    printf 'An existing Kindlevel container was found. Configure .env manually to preserve its current data mount; see docs/VPS.md.\n' >&2
    exit 1
fi

python3 - "$task_public_url" <<'PY'
from pathlib import Path
import ipaddress
import sys
from urllib.parse import urlsplit

address = sys.argv[1].rstrip('/')
try:
    url = urlsplit(address)
    if (url.scheme != 'http' or not url.hostname or url.username or url.password
            or url.path or url.query or url.fragment or '?' in address or '#' in address
            or any(character.isspace() or ord(character) < 32 for character in address)):
        raise ValueError()
    host = url.hostname
    if ':' in host:
        ipaddress.IPv6Address(host)
    elif all(character in '0123456789.' for character in host):
        ipaddress.IPv4Address(host)
    elif any(not (character.isascii() and (character.isalnum() or character in '.-')) for character in host):
        raise ValueError()
    port = url.port or 80
    if not 1 <= port <= 65535:
        raise ValueError()
except ValueError:
    sys.exit('Use an HTTP address without a path, for example http://203.0.113.10 or http://203.0.113.10:8080.')

env = Path('.env')
if env.exists():
    settings = dict(line.split('=', 1) for line in env.read_text().splitlines()
                    if '=' in line and not line.lstrip().startswith('#'))
    if settings.get('KINDLEVEL_PUBLIC_URL') != address:
        sys.exit('.env already exists with a different address. Edit it explicitly; setup will not overwrite your configuration.')
    print('Using existing .env and data configuration.')
else:
    if Path('data').is_symlink():
        sys.exit('The data folder must not be a symbolic link.')
    bind = '[::]' if ':' in host else '0.0.0.0'
    if host == 'localhost' or host.startswith('127.'):
        bind = '127.0.0.1'
    elif ':' in host and ipaddress.IPv6Address(host).is_loopback:
        bind = '[::1]'
    env.write_text(f'KINDLEVEL_PUBLIC_URL={address}\nKINDLEVEL_BIND_ADDRESS={bind}\n'
                   f'KINDLEVEL_PORT={port}\nKINDLEVEL_DATA_PATH=./data\nTZ=UTC\n')
    env.chmod(0o600)
    Path('data').mkdir(mode=0o700, exist_ok=True)
PY

docker compose build kindlevel
# The same image prepares its data directory; only the dashboard stays running.
docker compose run --rm --no-deps --user 0 --cap-add CHOWN --cap-add FOWNER --entrypoint /bin/sh kindlevel \
    -c 'chown 10001:10001 /data && chmod 0700 /data'
docker compose up -d --no-build --wait --wait-timeout 90 kindlevel

printf '\nDashboard: %s\n' "$task_public_url"
if task_setup_code=$(docker compose exec -T kindlevel cat /data/setup-code 2>/dev/null); then
    printf 'One-time setup code: %s\nCreate your owner account in the dashboard, then pair your Kindle.\n' "$task_setup_code"
else
    printf 'An owner account already exists. Sign in with your existing credentials.\n'
fi
