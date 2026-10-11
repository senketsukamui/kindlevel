package dashboard

import (
	"crypto/pbkdf2"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

var errCredentials = errors.New("invalid credentials")

func token() string { return base64.RawURLEncoding.EncodeToString(randBytes(32)) }
func randBytes(size int) []byte {
	value := make([]byte, size)
	if _, err := rand.Read(value); err != nil {
		panic(err)
	}
	return value
}
func digest(value string) string {
	result := sha256.Sum256([]byte(value))
	return hex.EncodeToString(result[:])
}

func (s *Store) initConnection() error {
	_, err := s.db.Exec(`CREATE TABLE IF NOT EXISTS owner(id INTEGER PRIMARY KEY CHECK(id=1),username TEXT NOT NULL,salt BLOB NOT NULL,password_hash BLOB NOT NULL);
		CREATE TABLE IF NOT EXISTS sessions(token_hash TEXT PRIMARY KEY,expires INTEGER NOT NULL);
		CREATE TABLE IF NOT EXISTS pair_codes(code_hash TEXT PRIMARY KEY,expires INTEGER NOT NULL);
		CREATE TABLE IF NOT EXISTS devices(id TEXT PRIMARY KEY,name TEXT NOT NULL,token_hash TEXT UNIQUE NOT NULL,created INTEGER NOT NULL,revoked INTEGER NOT NULL DEFAULT 0,last_sync INTEGER NOT NULL DEFAULT 0,last_sequence INTEGER NOT NULL DEFAULT 0,last_digest TEXT NOT NULL DEFAULT '',snapshot TEXT NOT NULL DEFAULT '');
		UPDATE schema_version SET version=2;`)
	if err != nil {
		return err
	}
	initialized, err := s.Initialized()
	if err != nil || initialized {
		return err
	}
	path := filepath.Join(s.directory, "setup-code")
	file, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if errors.Is(err, os.ErrExist) {
		return nil
	}
	if err != nil {
		return err
	}
	defer file.Close()
	if _, err = file.WriteString(token() + "\n"); err != nil {
		return err
	}
	return file.Sync()
}

func (s *Store) Initialized() (bool, error) {
	var count int
	err := s.db.QueryRow(`SELECT COUNT(*) FROM owner`).Scan(&count)
	return count > 0, err
}

func (s *Store) Setup(code, username, password string) error {
	username = strings.TrimSpace(username)
	if len(username) < 1 || len(username) > 64 || len(password) < 12 || len(password) > 256 {
		return fmt.Errorf("choose a username and a password between 12 and 256 bytes")
	}
	expected, err := os.ReadFile(filepath.Join(s.directory, "setup-code"))
	if err != nil || subtle.ConstantTimeCompare([]byte(digest(strings.TrimSpace(code))), []byte(digest(strings.TrimSpace(string(expected))))) != 1 {
		return errCredentials
	}
	salt := randBytes(32)
	key, err := pbkdf2.Key(sha256.New, password, salt, 600000, 32)
	if err != nil {
		return err
	}
	_, err = s.db.Exec(`INSERT INTO owner(id,username,salt,password_hash) VALUES(1,?,?,?)`, username, salt, key)
	if err != nil {
		return errCredentials
	}
	_ = os.Remove(filepath.Join(s.directory, "setup-code"))
	return nil
}

func (s *Store) Login(username, password string, now time.Time) (string, error) {
	if len(username) > 64 || len(password) > 256 {
		return "", errCredentials
	}
	var name string
	var salt, expected []byte
	err := s.db.QueryRow(`SELECT username,salt,password_hash FROM owner WHERE id=1`).Scan(&name, &salt, &expected)
	if err != nil {
		return "", errCredentials
	}
	key, err := pbkdf2.Key(sha256.New, password, salt, 600000, 32)
	if err != nil || subtle.ConstantTimeCompare(key, expected) != 1 || username != name {
		return "", errCredentials
	}
	value := token()
	tx, err := s.db.Begin()
	if err != nil {
		return "", err
	}
	defer tx.Rollback()
	if _, err = tx.Exec(`DELETE FROM sessions WHERE expires<=?`, now.Unix()); err != nil {
		return "", err
	}
	if _, err = tx.Exec(`DELETE FROM sessions WHERE token_hash IN (SELECT token_hash FROM sessions ORDER BY expires DESC LIMIT -1 OFFSET 31)`); err != nil {
		return "", err
	}
	if _, err = tx.Exec(`INSERT INTO sessions VALUES(?,?)`, digest(value), now.Add(7*24*time.Hour).Unix()); err != nil {
		return "", err
	}
	return value, tx.Commit()
}

func (s *Store) Session(value string, now time.Time) bool {
	if len(value) != 43 {
		return false
	}
	var expiry int64
	err := s.db.QueryRow(`SELECT expires FROM sessions WHERE token_hash=?`, digest(value)).Scan(&expiry)
	return err == nil && expiry > now.Unix()
}

func (s *Store) Logout(value string) {
	_, _ = s.db.Exec(`DELETE FROM sessions WHERE token_hash=?`, digest(value))
}

type Device struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Created  int64  `json:"created"`
	Revoked  bool   `json:"revoked"`
	LastSync int64  `json:"last_sync"`
}

func (s *Store) Devices() ([]Device, error) {
	rows, err := s.db.Query(`SELECT id,name,created,revoked,last_sync FROM devices ORDER BY created DESC,id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := []Device{}
	for rows.Next() {
		var value Device
		var revoked int
		if err = rows.Scan(&value.ID, &value.Name, &value.Created, &revoked, &value.LastSync); err != nil {
			return nil, err
		}
		value.Revoked = revoked != 0
		result = append(result, value)
	}
	return result, rows.Err()
}

func (s *Store) PairCode(now time.Time) (string, error) {
	// Ten base32 characters carry 50 bits of entropy and are easy to type on Kindle.
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	bytes := randBytes(10)
	var result strings.Builder
	for _, value := range bytes {
		result.WriteByte(alphabet[int(value)%32])
	}
	code := result.String()
	tx, err := s.db.Begin()
	if err != nil {
		return "", err
	}
	defer tx.Rollback()
	if _, err = tx.Exec(`DELETE FROM pair_codes`); err != nil {
		return "", err
	}
	if _, err = tx.Exec(`INSERT INTO pair_codes VALUES(?,?)`, digest(code), now.Add(10*time.Minute).Unix()); err != nil {
		return "", err
	}
	return code[:5] + "-" + code[5:], tx.Commit()
}

func (s *Store) Claim(code, name string, now time.Time) (string, string, error) {
	code = strings.ToUpper(strings.ReplaceAll(strings.TrimSpace(code), "-", ""))
	name = strings.TrimSpace(name)
	if len(code) != 10 || len(name) < 1 || len(name) > 80 {
		return "", "", errCredentials
	}
	tx, err := s.db.Begin()
	if err != nil {
		return "", "", err
	}
	defer tx.Rollback()
	var expiry int64
	if err = tx.QueryRow(`DELETE FROM pair_codes WHERE code_hash=? RETURNING expires`, digest(code)).Scan(&expiry); err != nil || expiry <= now.Unix() {
		return "", "", errCredentials
	}
	var count int
	if err = tx.QueryRow(`SELECT COUNT(*) FROM devices`).Scan(&count); err != nil || count >= 50 {
		return "", "", fmt.Errorf("device limit reached")
	}
	id := hex.EncodeToString(randBytes(16))
	secret := token()
	if _, err = tx.Exec(`INSERT INTO devices(id,name,token_hash,created) VALUES(?,?,?,?)`, id, name, digest(secret), now.Unix()); err != nil {
		return "", "", err
	}
	return id, secret, tx.Commit()
}

func (s *Store) DeviceToken(value string) (string, error) {
	if len(value) != 43 {
		return "", errCredentials
	}
	var id string
	err := s.db.QueryRow(`SELECT id FROM devices WHERE token_hash=? AND revoked=0`, digest(value)).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return "", errCredentials
	}
	return id, err
}

func (s *Store) Revoke(id string) error {
	_, err := s.db.Exec(`UPDATE devices SET revoked=1 WHERE id=?`, id)
	return err
}
