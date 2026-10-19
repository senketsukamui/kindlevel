"""Achievement browsing, filters and details in the real KOReader preview."""
from preview_http import request, action, state_after, capture, tap

if __name__ == "__main__":
    request("/api/reload", {})
    state_after()
    assert tap("tab-achievements")["tab"] == "achievements"
    assert action({"type": "key", "key": "Right"})["achievement_page"] == 2
    assert action({"type": "key", "key": "Left"})["achievement_page"] == 1
    state = tap("achievement-filter-books")
    assert state["achievement_filter"] == "books" and state["achievement_page"] == 1
    capture("demo-book-quests.png")
    details = next(h["id"] for h in state["hit_targets"] if h["id"].startswith("achievement-details-"))
    state = tap(details)
    assert state["achievement_detail"] and not state["achievement_toast"]
    capture("demo-achievement-details.png")
    assert not tap("achievement-back")["achievement_detail"]
    assert tap("achievement-filter-earned")["achievement_filter"] == "earned"
    capture("demo-earned-achievements.png")
    assert tap("achievement-filter-locked")["achievement_filter"] == "locked"
    capture("demo-locked-achievements.png")
    tap("achievement-filter-all")
    capture("demo-achievements.png")
    print("Achievement paging, filters and native details passed; no preview action or live XP.")
