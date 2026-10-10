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


if __name__ == "__main__":
    request("/api/reload", {})
    state_after()
    capture("demo-statistics.png")
    action({"type": "tap", "x": 730, "y": 270})
    capture("demo-year.png")
    today = dt.date.today()
    index = (today-dt.date(today.year, 1, 1)).days + dt.date(today.year, 1, 1).weekday()
    week, weekday = index//7, index % 7
    panel, column = week//27, week % 27
    scale = min(1072/600, 1448/800)
    px = lambda value: int(value*scale+0.5)
    step = (1072-2*px(28))//27
    x = px(28)+column*step+px(7)
    y = px(452+panel*137)+weekday*px(16)+px(7)
    action({"type": "tap", "x": x, "y": y})
    capture("demo-day.png")
    action({"type": "tap", "x": 250, "y": px(510)})
    capture("demo-book.png")
    action({"type": "key", "key": "Esc"})
    action({"type": "key", "key": "Esc"})
    action({"type": "swipe", "x": 500, "y": 700, "direction": "east"})
    # Calendar uses the same native Lua screen, with ribbons and month navigation.
    request("/api/reload", {})
    state_after()
    action({"type": "tap", "x": 500, "y": px(715)})
    action({"type": "tap", "x": px(88), "y": px(696)})
    capture("demo-book-calendar.png")
    action({"type": "tap", "x": 850, "y": px(85)})
    capture("demo-year-goal.png")
    # Exercise the actual numeric InputDialog and persistence, then restore the demo target.
    for target in (12, 24):
        action({"type": "tap", "x": 500, "y": px(415)})
        for _ in range(2):
            action({"type": "key", "key": "Backspace"})
        action({"type": "text", "text": str(target)})
        action({"type": "tap", "x": 750, "y": 855})
        preferences = (OUTPUT.parents[1]/".cache/preview/data/settings/kindlevel.lua").read_text()
        import re
        assert re.search(r'\["'+str(today.year)+r'"\]\s*=\s*'+str(target), preferences), "native goal editor persisted target"
    # End on the initial dashboard, ready for the user to explore.
    request("/api/reload", {})
    state_after()
    print("Preview reload, native touch, calendars, yearly goal editor, keyboard, and swipe passed.")
