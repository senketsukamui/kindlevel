package dashboard

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestAuthenticationAndPairing(t *testing.T) {
	now := time.Now()
	store, err := Open(t.TempDir(), now)
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	handler := Handler(store, t.TempDir())
	request := func(method, path string, body any, cookie, bearer string) *httptest.ResponseRecorder {
		encoded, _ := json.Marshal(body)
		r := httptest.NewRequest(method, path, bytes.NewReader(encoded))
		r.Header.Set("Content-Type", "application/json")
		if cookie != "" {
			r.AddCookie(&http.Cookie{Name: "kindlevel_session", Value: cookie})
		}
		if bearer != "" {
			r.Header.Set("Authorization", "Bearer "+bearer)
		}
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, r)
		return w
	}
	if response := request("GET", "/api/v1/dashboard", nil, "", ""); response.Code != 401 {
		t.Fatal("history was exposed without owner login")
	}
	code, err := os.ReadFile(filepath.Join(store.directory, "setup-code"))
	if err != nil {
		t.Fatal(err)
	}
	bad := request("POST", "/api/v1/auth/setup", map[string]string{"code": "wrong", "username": "reader", "password": "test-password-only"}, "", "")
	if bad.Code != 400 {
		t.Fatal("invalid bootstrap code accepted")
	}
	response := request("POST", "/api/v1/auth/setup", map[string]string{"code": string(code), "username": "reader", "password": "test-password-only"}, "", "")
	if response.Code != 200 || len(response.Result().Cookies()) != 1 {
		t.Fatalf("setup failed: %d", response.Code)
	}
	cookie := response.Result().Cookies()[0]
	if !cookie.HttpOnly || cookie.SameSite != http.SameSiteStrictMode {
		t.Fatal("session cookie is missing browser protections")
	}
	if _, err := os.Stat(filepath.Join(store.directory, "setup-code")); !os.IsNotExist(err) {
		t.Fatal("bootstrap code should be removed after setup")
	}
	if response = request("GET", "/api/v1/dashboard", nil, cookie.Value, ""); response.Code != 200 {
		t.Fatal("owner cannot load dashboard")
	}
	if response = request("POST", "/api/v1/auth/login", map[string]string{"username": "reader", "password": "wrong"}, "", ""); response.Code != 401 {
		t.Fatal("wrong password accepted")
	}
	if response = request("POST", "/api/v1/pairing", nil, "", ""); response.Code != 401 {
		t.Fatal("pairing code generation is not private")
	}
	response = request("POST", "/api/v1/pairing", nil, cookie.Value, "")
	if response.Code != 200 {
		t.Fatal("owner cannot generate code")
	}
	var offer struct {
		Code string `json:"code"`
	}
	if err = json.Unmarshal(response.Body.Bytes(), &offer); err != nil {
		t.Fatal(err)
	}
	response = request("POST", "/api/v1/devices/pair", map[string]string{"code": offer.Code, "name": "Paperwhite"}, "", "")
	if response.Code != 200 {
		t.Fatal("Kindle could not claim pairing code")
	}
	var claim struct {
		ID    string `json:"device_id"`
		Token string `json:"token"`
	}
	_ = json.Unmarshal(response.Body.Bytes(), &claim)
	if response = request("POST", "/api/v1/devices/pair", map[string]string{"code": offer.Code, "name": "Other"}, "", ""); response.Code != 401 {
		t.Fatal("pairing code reused")
	}
	if response = request("GET", "/api/v1/dashboard", nil, "", claim.Token); response.Code != 401 {
		t.Fatal("device token can read owner dashboard")
	}
	if response = request("POST", "/api/v1/auth/logout", nil, cookie.Value, ""); response.Code != 200 {
		t.Fatal("logout failed")
	}
	if response = request("GET", "/api/v1/dashboard", nil, cookie.Value, ""); response.Code != 401 {
		t.Fatal("logged-out cookie is still valid")
	}
	expired, _ := store.PairCode(now.Add(-11 * time.Minute))
	if _, _, err = store.Claim(expired, "Old code", now); err == nil {
		t.Fatal("expired pairing code accepted")
	}
	if err = store.Revoke(claim.ID); err != nil {
		t.Fatal(err)
	}
	if _, err = store.DeviceToken(claim.Token); err == nil {
		t.Fatal("revoked Kindle token accepted")
	}
}

func TestSnapshotRetryReplacementAndRestart(t *testing.T) {
	path := t.TempDir()
	now := time.Now()
	store, err := Open(path, now)
	if err != nil {
		t.Fatal(err)
	}
	code, _ := store.PairCode(now)
	id, secret, err := store.Claim(code, "Paperwhite", now)
	if err != nil {
		t.Fatal(err)
	}
	value := Upload{Schema: 1, Sequence: 1, CapturedAt: now.Unix(), TimezoneOffset: 14400, Version: "0.6.0-dev", CurrentBook: "stats:1", Goals: Goals{20, 24}, Books: []Book{{ID: "stats:1", Title: "A real book", Author: "Reader", Format: "EPUB", Status: "reading", Progress: 42, ProgressKnown: true, Pages: 100, Color: "olive"}}, Activity: []Activity{{ID: "stats:1:2026-10-01", BookID: "stats:1", Date: "2026-10-01", Seconds: 600, Pages: 10}}, Achievements: []Achievement{{ID: "first_pages", Title: "First Pages", Description: "Read 15 minutes", Icon: "book", Target: 15, Unit: "min", Progress: 10, XP: 25}}}
	for range 2 {
		if err = store.Accept(id, value, now); err != nil {
			t.Fatal(err)
		}
	}
	snapshot, err := store.Snapshot(now)
	if err != nil {
		t.Fatal(err)
	}
	if snapshot.Demo || len(snapshot.Activity) != 1 || snapshot.Activity[0].Seconds != 600 || snapshot.Goals != (Goals{20, 24}) {
		t.Fatal("retry doubled stats or real data was mixed with demo")
	}
	if err = store.SetGoals(Goals{45, 12}); err != nil {
		t.Fatal(err)
	}
	value.Sequence = 2
	value.Activity[0].Seconds = 900
	if err = store.Accept(id, value, now); err != nil {
		t.Fatal(err)
	}
	value.Sequence = 1
	if err = store.Accept(id, value, now); err != errStale {
		t.Fatal("older snapshot replaced newer data")
	}
	value.Sequence = 2
	value.Activity[0].Seconds = 1200
	if err = store.Accept(id, value, now); err != errChanged {
		t.Fatal("same sequence accepted conflicting content")
	}
	value.Sequence = 3
	value.Activity = nil
	value.Books = nil
	value.Achievements = nil
	value.CurrentBook = ""
	if err = store.Accept(id, value, now); err != nil {
		t.Fatal(err)
	}
	store.Close()
	store, err = Open(path, now)
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	if _, err = store.DeviceToken(secret); err != nil {
		t.Fatal("device pairing was lost on restart")
	}
	snapshot, err = store.Snapshot(now)
	if err != nil {
		t.Fatal(err)
	}
	if snapshot.Demo || len(snapshot.Activity) != 0 || len(snapshot.Books) != 0 || snapshot.Goals != (Goals{45, 12}) {
		t.Fatal("replacement retained deleted records or overwrote edited goals")
	}
	if err = store.Revoke(id); err != nil {
		t.Fatal(err)
	}
	if err = store.Accept(id, value, now); err != errCredentials {
		t.Fatal("revoked device can upload")
	}
}
