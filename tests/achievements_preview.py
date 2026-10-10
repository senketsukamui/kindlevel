"""Check that the live Mac preview shows and automatically removes real toasts."""
import time
from preview_http import request, action, state_after, capture


def wait_for_toast(visible, timeout=10):
    end = time.monotonic()+timeout
    while time.monotonic() < end:
        state = request("/api/state")
        assert not state.get("error"), state.get("error")
        if bool(state.get("achievement_toast")) == visible:
            return state
        time.sleep(0.1)
    raise AssertionError("Toast visibility did not update")


if __name__ == "__main__":
    request("/api/reload", {})
    state_after()
    action({"type": "tap", "x": 790, "y": 60})
    capture("demo-achievements.png")
    before = request("/screen.png")
    action({"type": "tap", "x": 450, "y": 510})
    shown = wait_for_toast(True)
    assert shown["achievement_toast"] == "first_pages"
    capture("demo-achievement-toast.png")
    hidden = wait_for_toast(False)
    assert hidden["frame"] > shown["frame"], "preview publishes the timer-driven repaint without another input"
    assert request("/screen.png") == before, "toast and shadow disappear without leaving stale pixels"
    action({"type": "tap", "x": 500, "y": 1275})
    wait_for_toast(True)
    capture("demo-achievement-over-book.png")
    action({"type": "tap", "x": 1000, "y": 1000})
    wait_for_toast(False)
    request("/api/reload", {})
    state_after()
    action({"type": "tap", "x": 790, "y": 60})
    print("Achievement preview page, timer repaint, clean dismissal, reading overlay, and page-turn input passed.")
