-- Copy to custom_achievements.lua in this folder. Return as many definitions as you like.
return {
    {
        id = "my_favorite_book", -- Keep this ID stable after people unlock it.
        icon = "achievements/book.svg", -- Relative to assets/; your own SVG works too.
        text = "One for the Favorites",
        description = "Read twenty minutes of my favorite book.",
        xp = 50, -- Display only. No XP balance or levels exist yet.
        group = "books",
        trigger = {
            type = "book", action = "read", target = 20,
            titles = { "Replace with a fragment of the book's metadata title" },
            -- authors = { "Optional exact author credit" },
        },
    },
    {
        id = "my_reading_ritual",
        icon = "achievements/tea.svg",
        text = "A Personal Ritual",
        description = "Read for an hour and save five highlights.",
        xp = 35,
        trigger = {
            type = "all", conditions = {
                { type = "metric", metric = "minutes", target = 60 },
                -- Use a function for a new condition without editing the engine.
                function(context)
                    return { value = context.metrics.highlights, target = 5, unit = "highlights" }
                end,
            },
        },
    },
}
