"""Explore the actual journey/return screens through the running Mac preview."""
from preview_http import action, capture, request, state_after, tap


if __name__ == "__main__":
    request("/api/reload", {})
    state_after()
    tap("tab-stats")

    state = tap("return-statistics")
    assert state["stats_view"] == "recovery" and state["recovery_mode"] == "reading"
    capture("demo-return-statistics.png")
    state = tap("recovery-books")
    assert state["recovery_mode"] == "books"
    capture("demo-book-returns.png")
    state = tap("recovery-return-1")
    assert state["stats_view"] == "journey" and state["stats_book_id"]
    book = state["stats_book_id"]
    capture("demo-book-journey.png")
    state = action({"type": "key", "key": "Right"})
    assert state["stats_list_page"] == 2
    capture("demo-book-journey-older.png")
    state = action({"type": "key", "key": "Left"})
    assert state["stats_list_page"] == 1
    state = tap("break-7")
    assert state["break_days"] == 7
    state = tap("break-3")
    assert state["break_days"] == 3
    state = tap(next(h["id"] for h in state_after()["hit_targets"] if h["id"].startswith("journey-episode-")))
    assert state["stats_view"] == "day"
    state = action({"type": "key", "key": "Esc"})
    assert state["stats_view"] == "journey" and state["stats_book_id"] == book
    state = action({"type": "key", "key": "Esc"})
    assert state["stats_view"] == "recovery" and state["recovery_mode"] == "books"
    state = action({"type": "key", "key": "Esc"})
    assert state["stats_view"] == "overview"
    # Reach the same view from book details rather than a return card.
    tap("stats-books")
    state = tap(next(h["id"] for h in state_after()["hit_targets"] if h["id"].startswith("history-book-")))
    assert state["stats_view"] == "book"
    state = tap("book-journey")
    assert state["stats_view"] == "journey"
    print("Journey/return screens, scope, thresholds, paging, journals and back navigation passed.")
