-- Add an entry here, or return extra entries from custom_achievements.lua.
-- Stable IDs are the keys in the unlock ledger. XP is descriptive metadata only.
local catalog = {}
local function add(id, icon, text, description, trigger, xp, group)
    catalog[#catalog + 1] = { id = id, icon = "achievements/" .. icon .. ".svg", text = text,
        description = description, trigger = trigger, xp = xp, group = group or "milestones" }
end
local function metric(id, icon, text, description, name, target, xp, group)
    add(id, icon, text, description, { type = "metric", metric = name, target = target }, xp, group)
end

-- Keep the four original IDs so existing references and future unlocks stay stable.
metric("first_pages", "book", "First Pages", "Spend 15 minutes reading.", "minutes", 15, 25)
metric("consistent_reader", "flame", "Consistent Reader", "Read on seven consecutive days.", "best_streak", 7, 75, "habits")
metric("page_turner", "pages", "Page Turner", "Read 1,000 pages across your reading days.", "pages", 1000, 100)
metric("first_book", "stack", "First Book", "Finish a book and record its finish date.", "finished", 1, 150)
metric("warm_up", "clock", "The Warm-Up", "Reach one hour of reading time.", "minutes", 60, 30)
metric("ten_hour_club", "clock", "Ten-Hour Club", "Spend ten hours between the covers.", "minutes", 600, 100)
metric("hundred_hour_club", "clock", "Time Well Spent", "Reach 100 hours of reading time.", "minutes", 6000, 250)
metric("hundred_pages", "pages", "Getting Somewhere", "Read your first 100 pages.", "pages", 100, 35)
metric("ten_thousand_pages", "pages", "A Small Forest", "Read 10,000 pages. Digital trees thank you.", "pages", 10000, 300)
metric("five_books", "stack", "Shelf Starter", "Record five different finished books.", "finished", 5, 100)
metric("twelve_books", "stack", "A Dozen Endings", "Record twelve different finished books.", "finished", 12, 200)
metric("fifty_books", "stack", "Walking Library", "Record fifty different finished books.", "finished", 50, 500)
metric("three_day_streak", "flame", "Three Is a Habit", "Read on three consecutive days.", "best_streak", 3, 30, "habits")
metric("thirty_day_streak", "flame", "A Month of Chapters", "Read on thirty consecutive days.", "best_streak", 30, 200, "habits")
metric("thirty_reading_days", "calendar", "Showing Up", "Read on thirty different days.", "active_days", 30, 75, "habits")
metric("hundred_reading_days", "calendar", "Part of the Routine", "Read on one hundred different days.", "active_days", 100, 200, "habits")
add("hour_in_a_day", "clock", "Lost in a Book", "Read for an hour in one calendar day.",
    { type = "daily", metric = "minutes", target = 60 }, 50, "habits")
add("hundred_page_day", "pages", "Quite a Plot", "Read 100 pages in one calendar day.",
    { type = "daily", metric = "pages", target = 100 }, 75, "habits")
add("weekend_warrior", "calendar", "Weekend Warrior", "Read for two hours on a Saturday or Sunday.",
    { type = "daily", metric = "minutes", target = 120, weekdays = { 0, 6 } }, 100, "habits")
add("welcome_back", "return", "Welcome Back", "Return to reading after three full days away.",
    { type = "return", scope = "reading", min_gap = 3, target = 1 }, 40, "habits")
add("five_comebacks", "return", "Still Here", "Return to reading after five breaks of at least three days.",
    { type = "return", scope = "reading", min_gap = 3, target = 5 }, 100, "habits")
add("unfinished_business", "return", "Unfinished Business", "Return to a book after at least seven days away.",
    { type = "return", scope = "books", min_gap = 7, target = 1 }, 50, "habits")
add("long_time_no_read", "return", "Long Time, No Read", "Return to a book after at least thirty days away.",
    { type = "return", scope = "books", min_gap = 30, target = 1 }, 75, "habits")
metric("first_highlights", "quill", "Worth Keeping", "Save ten highlights across your recorded books.", "highlights", 10, 30)
metric("hundred_highlights", "quill", "Marginally Obsessed", "Save one hundred highlights.", "highlights", 100, 100)
metric("ten_notes", "quill", "Receipts Included", "Write ten notes in your recorded books.", "notes", 10, 50)
metric("five_authors", "compass", "Different Voices", "Read at least fifteen minutes each from five authors.", "authors", 5, 75)
metric("five_books_read", "compass", "Window Shopping", "Read at least fifteen minutes in five different book records.", "books_read", 5, 50)
add("early_bird", "sun", "Early Bird", "Read fifteen minutes between 5 AM and 8 AM, across any days.",
    { type = "window", start_hour = 5, end_hour = 8, target = 15 }, 40, "curiosities")
add("night_owl", "moon", "Night Owl", "Read thirty minutes between 10 PM and 5 AM, across any days.",
    { type = "window", start_hour = 22, end_hour = 5, target = 30 }, 50, "curiosities")
add("one_more_chapter", "moon", "Just One More Chapter", "Read an hour between 10 PM and 5 AM on one calendar date.",
    { type = "window", start_hour = 22, end_hour = 5, per_day = true, target = 60 }, 75, "curiosities")
add("lunch_break", "tea", "Lunch Break Lore", "Read fifteen minutes between noon and 2 PM, across any days.",
    { type = "window", start_hour = 12, end_hour = 14, target = 15 }, 30, "curiosities")
metric("answer_to_everything", "spark", "The Answer Is 42", "Read for forty-two minutes. The question is still unclear.", "minutes", 42, 42, "curiosities")
add("marathon_reader", "clock", "Marathon Reader", "Read three recorded hours in one session. Sleep, closing the book, or gaps over a minute reset it.",
    { type = "session", target = 180, max_gap = 60 }, 200, "habits")

-- Normalized title fragments: putting a file on the shelf never unlocks these.
add("dont_panic", "towel", "Don't Panic", "Read fifteen minutes of The Hitchhiker's Guide to the Galaxy. Bring a towel.",
    { type = "book", action = "read", target = 15,
      titles = { "The Hitchhiker's Guide to the Galaxy", "Hitchhiker's Guide to the Galaxy", "Автостопом по галактике" } }, 42, "books")
add("spice_must_flow", "desert", "The Spice Must Flow", "Read thirty minutes of Dune. Hydration is your responsibility.",
    { type = "book", action = "read", target = 30, titles = { "Dune", "Дюна" } }, 80, "books")
add("big_reader", "eye", "Big Reader Is Watching", "Read fifteen minutes of 1984. This statistic is watching you.",
    { type = "book", action = "read", target = 15, titles = { "1984", "Nineteen Eighty-Four" } }, 84, "books")
add("there_and_back", "ring", "There and Back Again", "Read fifteen minutes of The Hobbit. Second breakfast can wait.",
    { type = "book", action = "read", target = 15, titles = { "The Hobbit", "The Hobbit, or There and Back Again", "Хоббит", "Хоббит, или Туда и обратно" } }, 60, "books")
add("one_does_not_simply", "ring", "One Does Not Simply Finish", "Record a finish for The Lord of the Rings or The Fellowship of the Ring.",
    { type = "book", action = "finish", titles = { "The Lord of the Rings", "The Fellowship of the Ring", "Властелин колец", "Братство кольца" } }, 150, "books")
add("white_whale", "whale", "The White Whale", "Record a finish for Moby-Dick. At last, a statistic you can catch.",
    { type = "book", action = "finish", titles = { "Moby-Dick", "Moby Dick, or The Whale", "Моби Дик", "Моби Дик, или Белый кит" } }, 150, "books")
add("quiet_beginning", "book", "Small Beginnings", "Read five minutes of the bundled A Quiet Beginning. Every quest starts somewhere.",
    { type = "book", action = "read", target = 5, titles = { "A Quiet Beginning" }, authors = { "Kindlevel" } }, 10, "books")
add("dude", "skeptic", "Dude...", "Open Mein Kampf. Well, this is awkward.",
    { type = "book", action = "open", titles = { "Mein Kampf", "Майн Кампф", "Моя борьба" } }, 0, "books")

return catalog
