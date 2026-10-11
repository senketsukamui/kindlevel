"""Exercise achievement browsing and details in the running KOReader preview."""
from preview_http import request, action, state_after, capture


if __name__ == "__main__":
    request("/api/reload", {})
    state_after()
    action({"type": "tap", "x": 790, "y": 60})
    assert state_after()["tab"] == "achievements"
    state = action({"type": "key", "key": "Right"})
    assert state["achievement_page"] == 2
    state = action({"type": "key", "key": "Left"})
    assert state["achievement_page"] == 1
    state = action({"type": "tap", "x": 900, "y": 405})
    assert state["achievement_filter"] == "books" and state["achievement_page"] == 1
    capture("demo-book-quests.png")
    before = request("/screen.png")
    # The former preview location now belongs to the card's details target.
    state = action({"type": "tap", "x": 920, "y": 580})
    assert not state["achievement_toast"], "tapping a card does not replay a notification"
    assert request("/screen.png") != before, "the card opens its details"
    capture("demo-achievement-details.png")
    action({"type": "tap", "x": 500, "y": 700})
    assert request("/screen.png") == before, "closing details restores the gallery"
    state = action({"type": "key", "key": "Right"})
    assert state["achievement_page"] == 2
    state = action({"type": "tap", "x": 415, "y": 405})
    assert state["achievement_filter"] == "earned" and state["achievement_page"] == 1
    capture("demo-earned-achievements.png")
    state = action({"type": "tap", "x": 655, "y": 405})
    assert state["achievement_filter"] == "locked"
    capture("demo-locked-achievements.png")
    action({"type": "tap", "x": 170, "y": 405})
    capture("demo-achievements.png")
    state = action({"type": "tap", "x": 500, "y": 1275})
    assert state["tab"] == "achievements" and not state["achievement_toast"], "gallery footer has no reading preview action"
    print("Achievement paging, filters, full-card details and removal of preview actions passed.")
