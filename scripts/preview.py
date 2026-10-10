#!/usr/bin/env python3
"""Interactive Mac/Linux preview of the actual Kindlevel Lua UI. Requires Docker."""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import platform
import shutil
import sqlite3
import subprocess
import tarfile
import threading
import time
from urllib.parse import quote, urlparse
import webbrowser

from demo_stats import make_demo

ROOT = Path(__file__).resolve().parents[1]
VERSION = "2026.07.1"
HASHES = {"arm64": "68b399a99a88bf3f036f5e8b67d043215a28e11d375cf0823900aef7b1523a0b",
          "x86_64": "299aadb28147a25e9432ced1214ea444a4184393b5ae97cf42402c8a61b1a1b0"}


def timezone_name():
    if os.environ.get("TZ"):
        return os.environ["TZ"]
    localtime = str(Path("/etc/localtime").resolve())
    if "/zoneinfo/" in localtime:
        return localtime.split("/zoneinfo/", 1)[1]
    offset = getattr(time.localtime(), "tm_gmtoff", -time.timezone)
    return f"UTC{'-' if offset >= 0 else '+'}{abs(offset)//3600}:{abs(offset)%3600//60:02d}"
PAGE = r'''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Kindlevel preview</title>
<style>*{box-sizing:border-box}body{margin:0;background:#e9e8e4;color:#242421;font:14px system-ui,sans-serif}header{padding:16px 22px;display:flex;gap:16px;align-items:center;flex-wrap:wrap;background:#fff;border-bottom:1px solid #d7d6d2}strong{font-size:18px}button{padding:9px 13px;background:#fff;border:1px solid #ccc;border-radius:6px;cursor:pointer}button:hover{background:#f3f3f0}.muted{color:#73736d}main{display:flex;justify-content:center;padding:20px}.device{padding:18px 18px 28px;background:#252525;border-radius:20px;box-shadow:0 12px 35px #0002}img{display:block;height:calc(100vh - 164px);max-height:1100px;max-width:calc(100vw - 70px);width:auto;object-fit:contain;background:white;touch-action:none;user-select:none;cursor:pointer}.label{text-align:center;padding-top:16px;color:#888;letter-spacing:2px;font-size:12px}pre{white-space:pre-wrap;max-width:900px;padding:20px;background:#fff;margin:20px auto;display:none}#status{margin-left:auto}.help{text-align:center;margin:0 20px 16px;color:#777}@media(max-height:600px){img{height:70vh}}</style></head><body>
<header><strong>Kindlevel</strong><span class="muted">KOReader preview</span><button id="back">Back</button><button id="previous">←</button><button id="next">→</button><button id="reload">Reload Lua</button><span id="source" class="muted"></span><span id="status">Starting renderer…</span></header>
<main><div class="device"><img id="screen" draggable="false" alt="Kindlevel rendered by KOReader"><div class="label">KINDLEVEL</div></div></main><p class="help">Click to tap · Drag to swipe · Arrow keys to navigate · Escape to go back · Reload Lua after editing</p><pre id="error"></pre>
<script>let state={},last=-1,start=null,pending=false;const screen=document.querySelector('#screen'),status=document.querySelector('#status');
async function action(command){try{await fetch('/api/action',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(command)});}catch(e){status.textContent=e.message;}}
function position(e){let r=screen.getBoundingClientRect();return{x:Math.round((e.clientX-r.left)*state.width/r.width),y:Math.round((e.clientY-r.top)*state.height/r.height)};}
screen.addEventListener('pointerdown',e=>{if(!state.width)return;start={...position(e),cx:e.clientX,cy:e.clientY};screen.setPointerCapture(e.pointerId)});
screen.addEventListener('pointerup',e=>{if(!start)return;let p=position(e),dx=e.clientX-start.cx,dy=e.clientY-start.cy;if(Math.max(Math.abs(dx),Math.abs(dy))>35){action({type:'swipe',x:start.x,y:start.y,direction:Math.abs(dx)>Math.abs(dy)?(dx<0?'west':'east'):(dy<0?'north':'south')});}else action({type:'tap',...p});start=null});
document.querySelector('#back').onclick=()=>action({type:'key',key:'Esc'});document.querySelector('#previous').onclick=()=>action({type:'key',key:'Left'});document.querySelector('#next').onclick=()=>action({type:'key',key:'Right'});
document.querySelector('#reload').onclick=async()=>{status.textContent='Reloading…';await fetch('/api/reload',{method:'POST'});last=-1};
document.addEventListener('keydown',e=>{const keys={ArrowLeft:'Left',ArrowRight:'Right',Escape:'Esc',Enter:'Enter',Backspace:'Backspace'};if(keys[e.key]){e.preventDefault();action({type:'key',key:keys[e.key]})}else if(e.key.length===1&&!e.metaKey&&!e.ctrlKey)action({type:'text',text:e.key})});
async function poll(){try{let response=await fetch('/api/state',{cache:'no-store'});state=await response.json();if(state.error){let error=document.querySelector('#error');error.style.display='block';error.textContent=state.error;status.textContent='Renderer stopped';}else if(state.sequence!==undefined){document.querySelector('#error').style.display='none';status.textContent='Ready';document.querySelector('#source').textContent=state.demo?'Demo reading history':'Your copied reading history';if(state.frame!==last){last=state.frame;screen.src='/screen.png?frame='+last+'&t='+Date.now()}}}catch(e){status.textContent='Waiting for renderer…'}setTimeout(poll,350)}poll();</script></body></html>'''


def runtime_path(provided):
    if provided:
        candidate = Path(provided).expanduser().resolve()
        if (candidate / "reader.lua").exists():
            return candidate
        if (candidate / "lib/koreader/reader.lua").exists():
            return candidate / "lib/koreader"
        raise SystemExit("Runtime must contain reader.lua and luajit, or lib/koreader/.")
    arch = "arm64" if platform.machine().lower() in ("arm64", "aarch64") else "x86_64"
    cache = ROOT / ".cache" / "koreader" / f"{VERSION}-{arch}"
    candidate = cache / "lib/koreader"
    if candidate.joinpath("reader.lua").exists():
        return candidate
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / "runtime.tar.xz"
    url = f"https://github.com/koreader/koreader/releases/download/v{VERSION}/koreader-linux-{arch}-v{VERSION}.tar.xz"
    print(f"Downloading official KOReader {VERSION} ({arch})…", flush=True)
    subprocess.run(["curl", "--fail", "--location", "--max-time", "180", url, "--output", str(archive)], check=True)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != HASHES[arch]:
        raise SystemExit("KOReader archive checksum does not match the official release.")
    with tarfile.open(archive) as tar:
        tar.extractall(cache, filter="data")
    return candidate


class Renderer:
    def __init__(self, args):
        self.args, self.runtime = args, runtime_path(args.runtime)
        self.ipc = ROOT / ".cache/preview"
        self.ipc.mkdir(parents=True, exist_ok=True)
        (self.ipc / "commands").mkdir(exist_ok=True)
        (self.ipc / "data/settings").mkdir(parents=True, exist_ok=True)
        self.lock = threading.RLock()
        self.sequence = 0
        self.process = None
        self.log = None
        self.error = None
        books = self.ipc / "books"
        books.mkdir(exist_ok=True)
        for path in (ROOT / "kindlevel.koplugin/books").iterdir():
            if path.is_file():
                shutil.copy2(path, books / path.name)
        database = self.ipc / "data/settings/statistics.sqlite3"
        if args.database:
            source = Path(args.database).expanduser().resolve()
            if not source.is_file():
                raise SystemExit(f"Statistics database does not exist: {source}")
            with sqlite3.connect(f"file:{quote(str(source))}?mode=ro", uri=True) as src:
                with sqlite3.connect(database) as dst:
                    src.backup(dst)
        else:
            make_demo(database)
        self.atomic("config.json", {"width": args.width, "height": args.height, "demo": not bool(args.database)})
        self.start()

    def atomic(self, name, value):
        target = self.ipc / name
        temporary = target.with_suffix(target.suffix + ".next")
        temporary.write_text(json.dumps(value))
        temporary.replace(target)

    def stop(self):
        if self.process and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        if self.log:
            self.log.close()
            self.log = None

    def start(self):
        with self.lock:
            self.stop()
            self.error = None
            for path in (self.ipc / "commands").glob("*.json"):
                path.unlink()
            for name in ("state.json", "screen.png"):
                (self.ipc / name).unlink(missing_ok=True)
            self.log = (self.ipc / "renderer.log").open("w")
            command = ["docker", "run", "--rm", "--network=none",
                       "-v", f"{self.runtime}:/opt/koreader",
                       "-v", f"{ROOT}:/workspace:ro", "-v", f"{self.ipc}:/preview",
                       "-w", "/opt/koreader", "-e", "SDL_VIDEODRIVER=dummy", "-e", "SDL_AUDIODRIVER=dummy",
                       "-e", "KO_HOME=/preview/data", "-e", "TZ=" + timezone_name(),
                       "python:3.10-slim", "./luajit", "/workspace/scripts/preview_runner.lua"]
            self.process = subprocess.Popen(command, stdout=self.log, stderr=subprocess.STDOUT)

    def state(self):
        if self.process.poll() is not None:
            return {"error": (self.ipc / "renderer.log").read_text()[-10000:]}
        try:
            return json.loads((self.ipc / "state.json").read_text())
        except (OSError, json.JSONDecodeError):
            return {"starting": True}

    def action(self, command):
        allowed_keys = {"Left", "Right", "Esc", "Enter", "Backspace"}
        kind = command.get("type")
        if kind in ("tap", "swipe"):
            for key, limit in (("x", self.args.width), ("y", self.args.height)):
                if not isinstance(command.get(key), (int, float)) or not 0 <= command[key] < limit:
                    raise ValueError("Touch position is outside the screen.")
            if kind == "swipe" and command.get("direction") not in ("west", "east", "north", "south"):
                raise ValueError("Invalid swipe direction.")
        elif kind == "key":
            if command.get("key") not in allowed_keys:
                raise ValueError("Unsupported key.")
        elif kind == "text":
            if not isinstance(command.get("text"), str) or len(command["text"]) > 100:
                raise ValueError("Invalid text input.")
        else:
            raise ValueError("Unknown action.")
        with self.lock:
            self.sequence += 1
            command["sequence"] = self.sequence
            self.atomic(f"commands/{self.sequence:016d}.json", command)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", help="Path to an extracted official KOReader Linux runtime")
    parser.add_argument("--database", help="Optional KOReader statistics.sqlite3; preview uses a local backup")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--width", type=int, default=1072)
    parser.add_argument("--height", type=int, default=1448)
    parser.add_argument("--no-open", action="store_true", help="Do not open the browser automatically")
    args = parser.parse_args()
    if not shutil.which("docker"):
        raise SystemExit("Install and start Docker Desktop before running the preview.")
    if not 400 <= args.width <= 2500 or not 600 <= args.height <= 3000:
        raise SystemExit("Unsupported preview dimensions.")
    renderer = Renderer(args)

    class Handler(BaseHTTPRequestHandler):
        def send(self, data, mime="application/json", code=200):
            if isinstance(data, dict):
                data = json.dumps(data).encode()
            elif isinstance(data, str):
                data = data.encode()
            self.send_response(code)
            self.send_header("Content-Type", mime)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            path = urlparse(self.path).path
            if path == "/":
                self.send(PAGE, "text/html; charset=utf-8")
            elif path == "/api/state":
                self.send(renderer.state())
            elif path == "/screen.png" and (renderer.ipc / "screen.png").exists():
                self.send((renderer.ipc / "screen.png").read_bytes(), "image/png")
            else:
                self.send({"error": "Not found"}, code=404)

        def do_POST(self):
            try:
                if self.headers.get("Origin") not in (None, f"http://127.0.0.1:{args.port}", f"http://localhost:{args.port}"):
                    self.send({"error": "Origin not allowed"}, code=403)
                    return
                if self.path == "/api/reload":
                    renderer.start()
                elif self.path == "/api/action":
                    length = int(self.headers.get("Content-Length", "0"))
                    if length > 2048:
                        raise ValueError("Request is too large.")
                    renderer.action(json.loads(self.rfile.read(length)))
                else:
                    self.send({"error": "Not found"}, code=404)
                    return
                self.send({"ok": True})
            except (ValueError, TypeError, KeyError) as error:
                self.send({"error": str(error)}, code=400)

        def log_message(self, *_):
            pass

    server = None
    try:
        server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
        address = f"http://127.0.0.1:{args.port}"
        print(f"Kindlevel preview: {address}\nClick/drag to interact. Reload Lua after edits. Ctrl+C to stop.", flush=True)
        if not args.no_open:
            webbrowser.open(address)
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping preview…", flush=True)
    finally:
        if server:
            server.server_close()
        renderer.stop()


if __name__ == "__main__":
    main()
