# Set up Kindlevel on a VPS

This guide starts from a fresh **Ubuntu 24.04 VPS** and serves the dashboard directly at `http://YOUR_VPS_IP`. It uses one container and keeps the project, configuration and data together. HTTP does not encrypt login or sync traffic.

The dashboard and server sync are included from v0.6.0; v0.7.0 adds automatic Wi-Fi sync in the plugin. These instructions use the release tag for a repeatable installation; ongoing development is on `develop`. The v0.5.0 plugin release does not include server sync.

## 1. Install the requirements

Connect using the account supplied by your VPS provider:

```sh
ssh your-user@YOUR_VPS_IP
```

If Docker is already installed, skip its installation. Otherwise, use the official Docker repository on Ubuntu:

<details>
<summary>Install Docker Engine and Compose on Ubuntu</summary>

```sh
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && printf '%s' "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

For other distributions or an existing Docker installation, see [Docker's installation guide](https://docs.docker.com/engine/install/ubuntu/).

</details>

Enable the daemon:

```sh
sudo systemctl enable --now docker
```

Install Git and Python 3, and check Compose:

```sh
sudo apt update
sudo apt install -y git python3
docker compose version
```

No Go, Node, database server or domain is required on the VPS. Docker builds the application inside its build containers.

## 2. Download the project

Use a separate directory for personal projects:

```sh
sudo mkdir -p /srv/personal-projects
sudo git clone --branch v0.7.0 --depth 1 https://github.com/senketsukamui/kindlevel.git /srv/personal-projects/kindlevel
cd /srv/personal-projects/kindlevel
```

## 3. Start the dashboard

Replace `YOUR_VPS_IP` with your server's actual IPv4 address:

```sh
sudo ./scripts/setup-server.sh http://YOUR_VPS_IP
```

The helper writes `.env`, builds the image, prepares `data/` for the container user, and waits for the dashboard to become healthy. It prints the address and **one-time setup code**. On a later run it reuses your existing configuration and data; it will not overwrite an existing address.

Open **http://YOUR_VPS_IP** in a browser. Enter the setup code and choose your dashboard username and password. The setup code is removed after account creation.

If needed, retrieve the code again:

```sh
sudo docker compose exec -T kindlevel cat /data/setup-code
```

If that file is gone, an owner account has already been created: sign in with that account. The dashboard password is separate from your VPS SSH password.

Make TCP port **80** reachable in your provider's firewall. If port 80 is already occupied, use a different port in the setup address, such as `http://YOUR_VPS_IP:8080`. The helper maps the matching port automatically.

## 4. Connect your Kindle

1. Install **v0.7.0 or newer** for automatic sync, using the plugin release ZIP or `python3 scripts/build.py` from a source checkout. Copy the ZIP's plugin files to the Kindle over USB. Fully exit KOReader before copying, then restart it and verify the version in Settings.
2. In the dashboard, open **Your Kindle → Pair a Kindle**.
3. On Kindle, open **Kindlevel → Settings → Web dashboard → Connect to server**.
4. Enter `http://YOUR_VPS_IP` (including a custom port if configured), the pairing code and a device name. Choose **Allow HTTP** when prompted.
5. Statistics sync automatically while KOReader is awake and Wi-Fi is connected. You can also choose **Sync now**. The dashboard refreshes automatically, or you can press **Refresh**.

Pairing codes expire after ten minutes. Use **Revoke access** in the dashboard to disable a device token. [What syncs and how retries work](DASHBOARD.md).

## Everyday commands

Run from `/srv/personal-projects/kindlevel`:

```sh
sudo docker compose ps                    # Status
sudo docker compose logs --tail 50        # Recent logs
sudo docker compose restart kindlevel    # Restart
sudo docker compose stop                 # Stop
sudo docker compose up -d                # Start again
```

Docker's restart policy starts the container after server reboots. No application-specific systemd service is required.

To update:

```sh
sudo python3 scripts/backup-server.py
sudo git fetch origin tag vNEXT
sudo git checkout vNEXT
sudo docker compose up --build -d
```

Replace `vNEXT` with the new release tag. Keep `.env` and `data/`; rebuilding the image preserves accounts, device registrations, goals and history. If Git reports local changes, review them before switching releases. Check out `develop` only when you want development builds rather than a tagged release.

## Configuration

The setup helper creates a private `.env` file. For manual configuration, start with `.env.example`:

| Setting | Purpose |
| --- | --- |
| `KINDLEVEL_PUBLIC_URL` | Exact address used by the browser and Kindle |
| `KINDLEVEL_BIND_ADDRESS` | `0.0.0.0` for direct access; `127.0.0.1` behind a host reverse proxy |
| `KINDLEVEL_PORT` | Host port, normally `80` for this setup |
| `KINDLEVEL_DATA_PATH` | `./data` keeps the database in this project folder |
| `TZ` | Server timezone, default `UTC` |

Apply changes with `sudo docker compose up -d`. If the address changes, use the new address and pair the Kindle again. The container runs as UID/GID `10001:10001`; its data folder must be writable by that user. The setup helper handles permissions.

Without `.env`, Compose defaults to a localhost preview on port 8080 with a named Docker volume. The helper refuses to silently switch an existing preview to a new data folder. To retain a named-volume installation, configure `.env` manually with `KINDLEVEL_DATA_PATH=kindlevel-data`.

For HTTPS through an existing reverse proxy, use a domain, forward to the application, and set `KINDLEVEL_PUBLIC_URL=https://your-domain`. HTTPS requires a certificate the Kindle can verify.

## Back up your reading data

The setup's `data/` folder contains the SQLite database. Create a consistent backup while the application runs:

```sh
sudo python3 scripts/backup-server.py
```

Archives are written to `backups/` with private permissions. Each includes an integrity-checked database and the deployment configuration. Copy backups to a different machine to protect against loss of the VPS. To schedule backups, run that command from your existing cron or backup system.

To restore, stop the container, rename the existing `data/` folder so it is kept as a fallback, and extract `data/kindlevel.sqlite3` from the chosen archive into a new `data/` folder. Restore `data/setup-code` too if present. Set ownership to `10001:10001`, then start the container. Use a clean folder so old SQLite WAL files cannot accompany the restored database.

## Troubleshooting

- **Address does not open:** check `docker compose ps`, the public IP, configured port and provider firewall. Test `http://YOUR_VPS_IP/healthz`; it should return `{"status":"ok"}`.
- **Permission denied writing the database:** rerun the setup helper with the same address, or correct the data folder's UID/GID to `10001:10001`.
- **Kindle asks for a trusted local network:** it is loading older plugin code. Fully exit KOReader, replace files in the existing plugin folder, and verify the footer shows v0.6.0 or newer.
- **Connection fails:** use the same address shown in the dashboard, including `http://` and any custom port. “localhost” on Kindle means the Kindle itself.
- **Pairing code fails:** generate a new code; each code is valid once for ten minutes.

[Project overview](../README.md) · [Connection details](DASHBOARD.md)
