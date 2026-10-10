"""Explore the actual journey/return screens through the running Mac preview."""
from preview_http import action, capture, request, state_after


if __name__ == "__main__":
    request("/api/reload", {})
    state_after()
    scale = min(1072/600, 1448/800)
    px = lambda value: int(value*scale+0.5)

    def tap(x, y):
        return action({"type": "tap", "x": px(x), "y": px(y)})

    state = tap(435, 715)
    assert state["stats_view"] == "recovery" and state["recovery_mode"] == "reading"
    capture("demo-return-statistics.png")
    state = tap(445, 265)
    assert state["recovery_mode"] == "books"
    capture("demo-book-returns.png")
    state = tap(260, 550)
    assert state["stats_view"] == "journey" and state["stats_book_id"]
    book = state["stats_book_id"]
    capture("demo-book-journey.png")
    state = action({"type": "key", "key": "Right"})
    assert state["stats_list_page"] == 2
    capture("demo-book-journey-older.png")
    state = action({"type": "key", "key": "Left"})
    assert state["stats_list_page"] == 1
    state = tap(440, 241)
    assert state["break_days"] == 7
    state = tap(345, 241)
    assert state["break_days"] == 3
    state = tap(260, 590)
    assert state["stats_view"] == "day"
    state = action({"type": "key", "key": "Esc"})
    assert state["stats_view"] == "journey" and state["stats_book_id"] == book
    state = action({"type": "key", "key": "Esc"})
    assert state["stats_view"] == "recovery" and state["recovery_mode"] == "books"
    state = action({"type": "key", "key": "Esc"})
    assert state["stats_view"] == "overview"
    # Reach the same view from book details rather than a return card.
    tap(260, 367)
    state = tap(260, 245)
    assert state["stats_view"] == "book"
    state = tap(160, 707)
    assert state["stats_view"] == "journey"
    print("Journey/return screens, scope, thresholds, paging, journals and back navigation passed.")
