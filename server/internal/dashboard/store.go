package dashboard

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"
)

type Book struct {
	ID            string `json:"id"`
	Title         string `json:"title"`
	Author        string `json:"author"`
	Format        string `json:"format"`
	Status        string `json:"status"`
	Progress      int    `json:"progress"`
	Pages         int    `json:"pages"`
	Color         string `json:"color"`
	Description   string `json:"description"`
	Finished      string `json:"finished,omitempty"`
	ProgressKnown bool   `json:"progress_known"`
}

type Activity struct {
	ID      string `json:"id"`
	BookID  string `json:"book_id"`
	Date    string `json:"date"`
	Seconds int    `json:"seconds"`
	Pages   int    `json:"pages"`
}

type Achievement struct {
	ID          string `json:"id"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Icon        string `json:"icon"`
	Unlocked    string `json:"unlocked,omitempty"`
	Progress    int    `json:"progress"`
	Target      int    `json:"target"`
	Unit        string `json:"unit"`
	XP          int    `json:"xp"`
}

type Goals struct {
	DailyMinutes int `json:"daily_minutes"`
	YearlyBooks  int `json:"yearly_books"`
}

type Snapshot struct {
	Demo         bool          `json:"demo"`
	Today        string        `json:"today"`
	Timezone     string        `json:"timezone"`
	Books        []Book        `json:"books"`
	Activity     []Activity    `json:"activity"`
	Achievements []Achievement `json:"achievements"`
	Goals        Goals         `json:"goals"`
	Devices      []Device      `json:"devices"`
	SourceDevice string        `json:"source_device,omitempty"`
	CurrentBook  string        `json:"current_book,omitempty"`
}

type Store struct {
	db        *sql.DB
	directory string
}

func Open(directory string, now time.Time) (*Store, error) {
	if err := os.MkdirAll(directory, 0700); err != nil {
		return nil, err
	}
	db, err := sql.Open("sqlite", filepath.Join(directory, "kindlevel.sqlite3"))
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	store := &Store{db: db, directory: directory}
	if _, err = db.Exec(`PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;
		CREATE TABLE IF NOT EXISTS schema_version(version INTEGER NOT NULL);
		INSERT INTO schema_version SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM schema_version);
		CREATE TABLE IF NOT EXISTS demo_records(kind TEXT NOT NULL, id TEXT NOT NULL, data TEXT NOT NULL, PRIMARY KEY(kind,id));
		CREATE TABLE IF NOT EXISTS preferences(key TEXT PRIMARY KEY, value TEXT NOT NULL);`); err != nil {
		db.Close()
		return nil, err
	}
	var version int
	if err = db.QueryRow(`SELECT version FROM schema_version`).Scan(&version); err != nil || version < 1 || version > 2 {
		db.Close()
		return nil, fmt.Errorf("unsupported database schema: %d (%v)", version, err)
	}
	if err = store.initConnection(); err != nil {
		db.Close()
		return nil, err
	}
	if err = store.seed(now); err != nil {
		db.Close()
		return nil, err
	}
	return store, nil
}

func (s *Store) Close() error { return s.db.Close() }

func records[T any](db *sql.DB, kind string) ([]T, error) {
	rows, err := db.Query(`SELECT data FROM demo_records WHERE kind=? ORDER BY id`, kind)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := []T{}
	for rows.Next() {
		var data string
		var record T
		if err := rows.Scan(&data); err != nil {
			return nil, err
		}
		if err := json.Unmarshal([]byte(data), &record); err != nil {
			return nil, err
		}
		result = append(result, record)
	}
	return result, rows.Err()
}

func (s *Store) demoSnapshot(now time.Time) (Snapshot, error) {
	value := Snapshot{Demo: true, Today: now.Format("2006-01-02"), Timezone: now.Location().String()}
	var err error
	if value.Books, err = records[Book](s.db, "book"); err != nil {
		return value, err
	}
	if value.Activity, err = records[Activity](s.db, "activity"); err != nil {
		return value, err
	}
	if value.Achievements, err = records[Achievement](s.db, "achievement"); err != nil {
		return value, err
	}
	var goals string
	err = s.db.QueryRow(`SELECT value FROM preferences WHERE key='goals'`).Scan(&goals)
	if err != nil {
		return value, err
	}
	err = json.Unmarshal([]byte(goals), &value.Goals)
	return value, err
}

func (s *Store) SetGoals(goals Goals) error {
	if !validGoals(goals) {
		return fmt.Errorf("daily minutes must be 1–1440 and yearly books must be 0–10000")
	}
	data, err := json.Marshal(goals)
	if err != nil {
		return err
	}
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err = tx.Exec(`INSERT INTO preferences(key,value) VALUES('goals',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value`, string(data)); err != nil {
		return err
	}
	if _, err = tx.Exec(`INSERT OR REPLACE INTO preferences(key,value) VALUES('goals_edited','true')`); err != nil {
		return err
	}
	return tx.Commit()
}
