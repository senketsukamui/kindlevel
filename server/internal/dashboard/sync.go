package dashboard

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"time"
)

type Upload struct {
	Schema         int           `json:"schema"`
	Sequence       int64         `json:"sequence"`
	CapturedAt     int64         `json:"captured_at"`
	TimezoneOffset int           `json:"timezone_offset"`
	Version        string        `json:"version"`
	CurrentBook    string        `json:"current_book"`
	Books          []Book        `json:"books"`
	Activity       []Activity    `json:"activity"`
	Achievements   []Achievement `json:"achievements"`
	Goals          Goals         `json:"goals"`
}

var recordID = regexp.MustCompile(`^[A-Za-z0-9:_-]{1,128}$`)
var iconNames = map[string]bool{"book": true, "calendar": true, "clock": true, "compass": true, "desert": true, "eye": true, "flame": true, "moon": true, "pages": true, "quill": true, "return": true, "ring": true, "skeptic": true, "spark": true, "stack": true, "sun": true, "tea": true, "towel": true, "whale": true}
var colors = map[string]bool{"olive": true, "sage": true, "clay": true, "ink": true, "sand": true, "rose": true}

func dateValid(value string) bool { _, err := time.Parse("2006-01-02", value); return err == nil }

func validateUpload(value *Upload) error {
	if value.Schema != 1 || value.Sequence < 1 || value.Sequence > 9007199254740991 || value.CapturedAt < 1 || value.CapturedAt > 253402300799 || value.TimezoneOffset < -14*3600 || value.TimezoneOffset > 14*3600 || len(value.Version) > 64 {
		return fmt.Errorf("unsupported sync schema, sequence or time")
	}
	if len(value.Books) > 5000 || len(value.Activity) > 100000 || len(value.Achievements) > 2000 {
		return fmt.Errorf("sync snapshot is too large")
	}
	books := map[string]bool{}
	for i := range value.Books {
		book := &value.Books[i]
		if !recordID.MatchString(book.ID) || books[book.ID] || len(book.Title) == 0 || len(book.Title) > 2048 || len(book.Author) > 2048 || len(book.Format) > 16 || len(book.Description) > 4000 || book.Pages < 0 || book.Pages > 10000000 || book.Progress < 0 || book.Progress > 100 || book.Finished != "" && !dateValid(book.Finished) {
			return fmt.Errorf("invalid or duplicate book record")
		}
		if book.Status != "reading" && book.Status != "finished" && book.Status != "unread" {
			return fmt.Errorf("invalid book status")
		}
		if !colors[book.Color] {
			book.Color = "olive"
		}
		books[book.ID] = true
	}
	if value.CurrentBook != "" && !books[value.CurrentBook] {
		return fmt.Errorf("current book is not in the snapshot")
	}
	ids := map[string]bool{}
	for _, item := range value.Activity {
		if !recordID.MatchString(item.ID) || ids[item.ID] || !books[item.BookID] || !dateValid(item.Date) || item.Seconds < 0 || item.Seconds > 1000000000 || item.Pages < 0 || item.Pages > 10000000 {
			return fmt.Errorf("invalid or duplicate activity record")
		}
		ids[item.ID] = true
	}
	ids = map[string]bool{}
	for i := range value.Achievements {
		badge := &value.Achievements[i]
		if !recordID.MatchString(badge.ID) || ids[badge.ID] || len(badge.Title) == 0 || len(badge.Title) > 256 || len(badge.Description) > 4000 || len(badge.Unit) > 64 || badge.Progress < 0 || badge.Progress > 1000000000000 || badge.Target < 1 || badge.Target > 1000000000000 || badge.XP < 0 || badge.XP > 1000000000 || badge.Unlocked != "" && !dateValid(badge.Unlocked) {
			return fmt.Errorf("invalid or duplicate achievement record")
		}
		if !iconNames[badge.Icon] {
			badge.Icon = "book"
		}
		ids[badge.ID] = true
	}
	if !validGoals(value.Goals) {
		return fmt.Errorf("invalid reading goals")
	}
	return nil
}

var errStale = errors.New("snapshot sequence is older than the server copy")
var errChanged = errors.New("this snapshot sequence was already used for different data")

func (s *Store) Accept(id string, value Upload, now time.Time) error {
	if err := validateUpload(&value); err != nil {
		return err
	}
	// Normalize before hashing so JSON whitespace and key order do not affect retry identity.
	encoded, err := json.Marshal(value)
	if err != nil {
		return err
	}
	hash := digest(string(encoded))
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var sequence int64
	var prior string
	if err = tx.QueryRow(`SELECT last_sequence,last_digest FROM devices WHERE id=? AND revoked=0`, id).Scan(&sequence, &prior); err != nil {
		return errCredentials
	}
	if value.Sequence < sequence {
		return errStale
	}
	if value.Sequence == sequence {
		if hash != prior {
			return errChanged
		}
		return nil
	}
	if _, err = tx.Exec(`UPDATE devices SET snapshot=?,last_sequence=?,last_digest=?,last_sync=? WHERE id=? AND revoked=0`, string(encoded), value.Sequence, hash, now.Unix(), id); err != nil {
		return err
	}
	var imported int
	if err = tx.QueryRow(`SELECT COUNT(*) FROM preferences WHERE key IN ('goals_edited','device_goals_imported')`).Scan(&imported); err != nil {
		return err
	}
	if imported == 0 {
		goals, _ := json.Marshal(value.Goals)
		if _, err = tx.Exec(`UPDATE preferences SET value=? WHERE key='goals'`, string(goals)); err != nil {
			return err
		}
		if _, err = tx.Exec(`INSERT INTO preferences(key,value) VALUES('device_goals_imported','true')`); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *Store) Snapshot(now time.Time) (Snapshot, error) { return s.DeviceSnapshot("", false, now) }

func (s *Store) DeviceSnapshot(id string, demo bool, now time.Time) (Snapshot, error) {
	var data, idFound string
	var err error
	if !demo {
		if id != "" {
			err = s.db.QueryRow(`SELECT id,snapshot FROM devices WHERE id=? AND snapshot!=''`, id).Scan(&idFound, &data)
		} else {
			err = s.db.QueryRow(`SELECT id,snapshot FROM devices WHERE snapshot!='' ORDER BY last_sync DESC,id LIMIT 1`).Scan(&idFound, &data)
		}
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			return Snapshot{}, err
		}
		if id != "" && errors.Is(err, sql.ErrNoRows) {
			return Snapshot{}, err
		}
	}
	var result Snapshot
	if data == "" {
		result, err = s.demoSnapshot(now)
		if err != nil {
			return result, err
		}
		for i := range result.Books {
			result.Books[i].ProgressKnown = true
		}
		result.CurrentBook = "home"
	} else {
		var payload Upload
		if err = json.Unmarshal([]byte(data), &payload); err != nil {
			return result, err
		}
		zone := time.FixedZone(fmt.Sprintf("Kindle (UTC%+d:%02d)", payload.TimezoneOffset/3600, abs(payload.TimezoneOffset/60)%60), payload.TimezoneOffset)
		result = Snapshot{Demo: false, Today: now.In(zone).Format("2006-01-02"), Timezone: zone.String(), Books: payload.Books, Activity: payload.Activity, Achievements: payload.Achievements, SourceDevice: idFound, CurrentBook: payload.CurrentBook}
		if result.Books == nil {
			result.Books = []Book{}
		}
		if result.Activity == nil {
			result.Activity = []Activity{}
		}
		if result.Achievements == nil {
			result.Achievements = []Achievement{}
		}
		var goals string
		if err = s.db.QueryRow(`SELECT value FROM preferences WHERE key='goals'`).Scan(&goals); err != nil {
			return result, err
		}
		if err = json.Unmarshal([]byte(goals), &result.Goals); err != nil {
			return result, err
		}
	}
	result.Devices, err = s.Devices()
	return result, err
}

func abs(value int) int {
	if value < 0 {
		return -value
	}
	return value
}
func validGoals(g Goals) bool {
	return g.DailyMinutes >= 1 && g.DailyMinutes <= 1440 && g.YearlyBooks >= 0 && g.YearlyBooks <= 10000
}
