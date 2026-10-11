package dashboard

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestDemoAndGoalPersistence(t *testing.T) {
	path := t.TempDir()
	now := time.Date(2026, 10, 12, 12, 0, 0, 0, time.UTC)
	store, err := Open(path, now)
	if err != nil {
		t.Fatal(err)
	}
	initial, err := store.Snapshot(now)
	if err != nil || len(initial.Books) != 6 || len(initial.Activity) == 0 || len(initial.Achievements) != 12 || !initial.Demo {
		t.Fatalf("invalid demo data: %+v, %v", initial, err)
	}
	handler := signedInHandler(t, store)
	request := httptest.NewRequest(http.MethodPut, "/api/v1/goals", strings.NewReader(`{"daily_minutes":45,"yearly_books":20}`))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != 200 {
		t.Fatalf("saving goals: %d %s", response.Code, response.Body.String())
	}
	store.Close()
	store, err = Open(path, now.AddDate(0, 0, 1))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	current, err := store.Snapshot(now.AddDate(0, 0, 1))
	if err != nil {
		t.Fatal(err)
	}
	if current.Goals != (Goals{45, 20}) || len(initial.Activity) != len(current.Activity) {
		t.Fatal("restart lost preferences or duplicated demo history")
	}
	handler = signedInHandler(t, store)
	for _, test := range []struct {
		body, origin, contentType string
		status                    int
	}{
		{`{"daily_minutes":0,"yearly_books":12}`, "", "application/json", 400},
		{`{"daily_minutes":30,"yearly_books":10001}`, "", "application/json", 400},
		{`{"daily_minutes":30,"yearly_books":12,"extra":true}`, "", "application/json", 400},
		{`{"daily_minutes":30,"yearly_books":12} {}`, "", "application/json", 400},
		{`{"daily_minutes":30,"yearly_books":12}`, "https://another-site.test", "application/json", 403},
		{`{"daily_minutes":30,"yearly_books":12}`, "", "text/plain", 415},
	} {
		request = httptest.NewRequest(http.MethodPut, "/api/v1/goals", strings.NewReader(test.body))
		request.Header.Set("Content-Type", test.contentType)
		request.Header.Set("Origin", test.origin)
		response = httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		if response.Code != test.status {
			t.Errorf("%s: got %d, want %d", test.body, response.Code, test.status)
		}
	}
	current, _ = store.Snapshot(now)
	if current.Goals != (Goals{45, 20}) {
		t.Fatal("rejected request changed goals")
	}
	response = httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest("GET", "/api/v1/dashboard", nil))
	var snapshot Snapshot
	if response.Code != 200 || json.Unmarshal(response.Body.Bytes(), &snapshot) != nil || snapshot.Goals != (Goals{45, 20}) {
		t.Fatal("dashboard did not return persisted data")
	}
	response = httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest("GET", "/api/missing", nil))
	if response.Code != 404 {
		t.Fatal("unknown API route should not return the app shell")
	}
}

func signedInHandler(t *testing.T, store *Store) http.Handler {
	t.Helper()
	initialized, err := store.Initialized()
	if err != nil {
		t.Fatal(err)
	}
	if !initialized {
		code, err := os.ReadFile(filepath.Join(store.directory, "setup-code"))
		if err != nil {
			t.Fatal(err)
		}
		if err := store.Setup(string(code), "reader", "a-test-password-only"); err != nil {
			t.Fatal(err)
		}
	}
	secret, err := store.Login("reader", "a-test-password-only", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	handler := Handler(store, t.TempDir())
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		r.AddCookie(&http.Cookie{Name: "kindlevel_session", Value: secret})
		handler.ServeHTTP(w, r)
	})
}
