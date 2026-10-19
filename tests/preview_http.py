"""Exercise a running real-UI preview: reload, touch, keys, and screenshots."""
import datetime as dt
import json
from pathlib import Path
import time
from urllib.request import Request, urlopen

BASE = "http://127.0.0.1:8765"
OUTPUT = Path(__file__).resolve().parents[1] / "dist/previews"


def request(path, data=None):
    headers = {"Content-Type": "application/json"}
    req = Request(BASE+path, data=json.dumps(data).encode() if data is not None else None, headers=headers)
    with urlopen(req, timeout=15) as response:
        body = response.read()
        return body if path.startswith("/screen.png") else json.loads(body)


def state_after(previous=None):
    limit = time.monotonic()+15
    while time.monotonic() < limit:
        state = request("/api/state")
        assert not state.get("error"), state.get("error")
        if "sequence" in state and (previous is None or state["sequence"] > previous):
            return state
        time.sleep(0.1)
    raise AssertionError("Renderer did not finish the action")


def action(command):
    previous = state_after()["sequence"]
    request("/api/action", command)
    return state_after(previous)


def capture(name):
    png = request("/screen.png")
    assert png.startswith(b"\x89PNG\r\n\x1a\n")
    (OUTPUT/name).write_bytes(png)


def tap(target):
    """Use a rendered tap target so tests survive layout and density changes."""
    state = state_after()
    hit = next((item for item in state.get("hit_targets", []) if item["id"] == target), None)
    assert hit is not None, f"Missing rendered target: {target}"
    return action({"type": "tap", "x": hit["x"] + hit["w"] / 2,
                   "y": hit["y"] + hit["h"] / 2})


if __name__ == "__main__":
    request("/api/reload", {})
    state_after()
    assert state_after()["tab"] == "read"
    capture("demo-reading-home.png")
    tap("tab-stats")
    capture("demo-statistics.png")
    tap("period-year")
    capture("demo-year.png")
    today = dt.date.today().isoformat()
    assert tap("calendar-" + today)["stats_view"] == "day"
    capture("demo-day.png")
    action({"type": "key", "key": "Esc"})
    tap("book-calendar")
    capture("demo-book-calendar.png")
    target = next((h["id"] for h in state_after()["hit_targets"] if h["id"].startswith("month-book-")), None)
    if target:
        assert tap(target)["stats_view"] == "book"
        capture("demo-book.png")
        action({"type": "key", "key": "Esc"})
    tap("tab-read")
    assert tap("year-goal")["stats_view"] == "goal"
    capture("demo-year-goal.png")
    # Exercise KOReader's unchanged numeric dialog and restore the demo target.
    for target in (12, 24):
        tap("set-year-goal")
        for _ in range(2):
            action({"type": "key", "key": "Backspace"})
        action({"type": "text", "text": str(target)})
        action({"type": "tap", "x": 750, "y": 855})
        preferences = (OUTPUT.parents[1]/".cache/preview/data/settings/kindlevel.lua").read_text()
        import re
        assert re.search(r'\["'+str(dt.date.today().year)+r'"\]\s*=\s*'+str(target), preferences), "native goal editor persisted target"
    tap("tab-settings")
    assert tap("settings-reading")["settings_group"] == "reading"
    assert action({"type": "key", "key": "Esc"}).get("settings_group") is None
    assert tap("settings-library")["settings_group"] == "library"
    tap("settings-back")
    assert tap("settings-connection")["settings_group"] == "connection"
    capture("demo-connection.png")
    tap("tab-library")
    capture("demo-library.png")
    assert tap("book-1")["tab"] == "read"
    action({"type": "swipe", "x": 500, "y": 700, "direction": "west"})
    capture("demo-reading-next.png")
    print("Real preview reload, tap targets, journals, calendar ribbons, goals, grouped settings and swipes passed.")
