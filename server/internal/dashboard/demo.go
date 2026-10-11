package dashboard

import (
	"encoding/json"
	"time"
)

func (s *Store) seed(now time.Time) error {
	var present int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM preferences WHERE key='demo_seeded'`).Scan(&present); err != nil {
		return err
	}
	if present > 0 {
		return nil
	}
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	date := func(days int) string { return today.AddDate(0, 0, -days).Format("2006-01-02") }
	books := []Book{
		{"quiet", "A Quiet Beginning", "Kindlevel", "EPUB", "finished", 100, 216, "sage", "An original sample story about finding a little room for reading in an ordinary day.", date(72), true},
		{"notes", "Notes on Reading", "Kindlevel", "PDF", "finished", 100, 154, "clay", "Small observations about attention, books, and the passages that stay with us.", date(31), true},
		{"home", "The Long Way Home", "Kindlevel", "EPUB", "reading", 67, 284, "olive", "A gentle journey through familiar places, unexpected detours, and the comfort of returning.", "", true},
		{"hours", "The Small Hours", "Kindlevel", "FB2", "reading", 24, 192, "ink", "Short chapters for late evenings, when the world grows quiet and there is time for one more page.", "", true},
		{"field", "Field Notes", "Kindlevel", "TXT", "unread", 0, 128, "sand", "A pocket notebook of walks, changing seasons, and everyday discoveries.", "", true},
		{"rain", "Pages for Rainy Days", "Kindlevel", "MOBI", "finished", 100, 240, "rose", "A collection of original miniature stories best enjoyed beside a window.", date(9), true},
	}
	badges := []Achievement{
		{"first", "First pages", "Open a book and begin your reading journey.", "book", date(120), 1, 1, "book", 10},
		{"habit", "A little every day", "Read on seven consecutive days.", "calendar", date(55), 7, 7, "days", 50},
		{"night", "One more chapter", "Read after the rest of the world has gone to bed.", "moon", date(18), 1, 1, "evening", 25},
		{"return", "Welcome back", "Return to a book after taking a break.", "return", date(12), 1, 1, "return", 25},
		{"tea", "Time well spent", "Spend ten hours in the company of books.", "tea", date(47), 10, 10, "hours", 50},
		{"stack", "A growing shelf", "Finish five books.", "stack", "", 3, 5, "books", 75},
		{"marathon", "Marathon reader", "Read for three hours in one uninterrupted session.", "clock", "", 74, 180, "minutes", 100},
		{"sun", "Early bird", "Make a little time for reading before sunrise.", "sun", "", 0, 1, "morning", 25},
		{"pages", "A thousand pages", "Read 1,000 pages across your library.", "pages", date(4), 1000, 1000, "pages", 100},
		{"compass", "The scenic route", "Return to three different books after a longer break.", "compass", "", 2, 3, "books", 50},
		{"flame", "Keeping the flame", "Keep a reading streak going for thirty days.", "flame", "", 12, 30, "days", 100},
		{"quill", "Margin companion", "Save fifty highlights or notes.", "quill", "", 32, 50, "passages", 50},
	}
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	put := func(kind, id string, item any) error {
		data, err := json.Marshal(item)
		if err != nil {
			return err
		}
		_, err = tx.Exec(`INSERT INTO demo_records(kind,id,data) VALUES(?,?,?)`, kind, id, string(data))
		return err
	}
	for _, book := range books {
		if err := put("book", book.ID, book); err != nil {
			return err
		}
	}
	for _, badge := range badges {
		if err := put("achievement", badge.ID, badge); err != nil {
			return err
		}
	}
	start := time.Date(today.Year(), 1, 1, 0, 0, 0, 0, today.Location())
	for day, offset := start, 0; !day.After(today); day, offset = day.AddDate(0, 0, 1), offset+1 {
		distance := int(today.Sub(day).Hours() / 24)
		if distance > 11 && (offset%11 == 3 || offset%11 == 4 || offset%67 >= 20 && offset%67 <= 24) {
			continue
		}
		ids := []string{"quiet", "notes", "rain", "home"}
		book := ids[(offset/25)%len(ids)]
		if distance < 12 {
			book = "home"
		}
		minutes := 18 + (offset*13)%47
		if distance == 0 {
			minutes = 24
		}
		id := day.Format("2006-01-02") + "-morning"
		activity := Activity{id, book, day.Format("2006-01-02"), minutes * 60, 8 + (offset*7)%28}
		if err := put("activity", id, activity); err != nil {
			return err
		}
		if offset%4 == 0 && distance != 0 {
			id = day.Format("2006-01-02") + "-evening"
			if err := put("activity", id, Activity{id, "hours", day.Format("2006-01-02"), 11 * 60, 6}); err != nil {
				return err
			}
		}
	}
	_, err = tx.Exec(`INSERT INTO preferences(key,value) VALUES('goals','{"daily_minutes":30,"yearly_books":12}'),('demo_seeded',?)`, date(0))
	if err != nil {
		return err
	}
	return tx.Commit()
}
