package dashboard

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

func respond(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func decode(w http.ResponseWriter, r *http.Request, value any, limit int64) bool {
	if !strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
		respond(w, 415, map[string]string{"error": "Use application/json."})
		return false
	}
	reader := json.NewDecoder(http.MaxBytesReader(w, r.Body, limit))
	reader.DisallowUnknownFields()
	if err := reader.Decode(value); err != nil {
		respond(w, 400, map[string]string{"error": "The JSON request is invalid or too large."})
		return false
	}
	if err := reader.Decode(new(any)); err != io.EOF {
		respond(w, 400, map[string]string{"error": "Provide one JSON object."})
		return false
	}
	return true
}

func Handler(store *Store, webDir string) http.Handler {
	mux := http.NewServeMux()
	publicURL := strings.TrimSuffix(os.Getenv("KINDLEVEL_PUBLIC_URL"), "/")
	cookieName := "kindlevel_session"
	session := func(r *http.Request) string {
		value, err := r.Cookie(cookieName)
		if err != nil {
			return ""
		}
		return value.Value
	}
	setCookie := func(w http.ResponseWriter, r *http.Request, value string, maxAge int) {
		http.SetCookie(w, &http.Cookie{Name: cookieName, Value: value, Path: "/", HttpOnly: true, SameSite: http.SameSiteStrictMode, Secure: r.TLS != nil || strings.HasPrefix(publicURL, "https://"), MaxAge: maxAge})
	}
	var rateMu sync.Mutex
	var rateStart time.Time
	rateCount := 0
	allowAuth := func() bool {
		rateMu.Lock()
		defer rateMu.Unlock()
		if time.Since(rateStart) > time.Minute {
			rateStart = time.Now()
			rateCount = 0
		}
		rateCount++
		return rateCount <= 20
	}
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		if err := store.db.PingContext(r.Context()); err != nil {
			respond(w, 503, map[string]string{"status": "unavailable"})
			return
		}
		respond(w, 200, map[string]string{"status": "ok"})
	})
	mux.HandleFunc("GET /api/v1/auth/status", func(w http.ResponseWriter, r *http.Request) {
		initialized, err := store.Initialized()
		if err != nil {
			respond(w, 500, map[string]string{"error": "Cannot check account setup."})
			return
		}
		respond(w, 200, map[string]any{"initialized": initialized, "authenticated": store.Session(session(r), time.Now()), "server_url": publicURL})
	})
	mux.HandleFunc("POST /api/v1/auth/setup", func(w http.ResponseWriter, r *http.Request) {
		var value struct {
			Code     string `json:"code"`
			Username string `json:"username"`
			Password string `json:"password"`
		}
		if !decode(w, r, &value, 4096) {
			return
		}
		if err := store.Setup(value.Code, value.Username, value.Password); err != nil {
			respond(w, 400, map[string]string{"error": "Setup failed. Check the setup code, username and password (12–256 bytes)."})
			return
		}
		secret, err := store.Login(strings.TrimSpace(value.Username), value.Password, time.Now())
		if err != nil {
			respond(w, 500, map[string]string{"error": "Account created. Sign in to continue."})
			return
		}
		setCookie(w, r, secret, 7*86400)
		respond(w, 200, map[string]bool{"authenticated": true})
	})
	mux.HandleFunc("POST /api/v1/auth/login", func(w http.ResponseWriter, r *http.Request) {
		var value struct {
			Username string `json:"username"`
			Password string `json:"password"`
		}
		if !decode(w, r, &value, 4096) {
			return
		}
		secret, err := store.Login(value.Username, value.Password, time.Now())
		if err != nil {
			respond(w, 401, map[string]string{"error": "Username or password is incorrect."})
			return
		}
		setCookie(w, r, secret, 7*86400)
		respond(w, 200, map[string]bool{"authenticated": true})
	})
	mux.HandleFunc("POST /api/v1/auth/logout", func(w http.ResponseWriter, r *http.Request) {
		store.Logout(session(r))
		setCookie(w, r, "", -1)
		respond(w, 200, map[string]bool{"authenticated": false})
	})
	mux.HandleFunc("GET /api/v1/dashboard", func(w http.ResponseWriter, r *http.Request) {
		data, err := store.DeviceSnapshot(r.URL.Query().Get("device"), r.URL.Query().Get("source") == "demo", time.Now())
		if err != nil {
			respond(w, 404, map[string]string{"error": "No reading snapshot is available for this device yet."})
			return
		}
		respond(w, 200, data)
	})
	mux.HandleFunc("PUT /api/v1/goals", func(w http.ResponseWriter, r *http.Request) {
		var goals Goals
		if !decode(w, r, &goals, 2048) {
			return
		}
		if !validGoals(goals) {
			respond(w, 400, map[string]string{"error": "Daily minutes must be 1–1440; yearly books must be 0–10000."})
			return
		}
		if err := store.SetGoals(goals); err != nil {
			respond(w, 500, map[string]string{"error": "Could not save your goals."})
			return
		}
		respond(w, 200, goals)
	})
	mux.HandleFunc("GET /api/v1/devices", func(w http.ResponseWriter, r *http.Request) {
		devices, err := store.Devices()
		if err != nil {
			respond(w, 500, map[string]string{"error": "Cannot load devices."})
			return
		}
		respond(w, 200, devices)
	})
	mux.HandleFunc("POST /api/v1/pairing", func(w http.ResponseWriter, r *http.Request) {
		code, err := store.PairCode(time.Now())
		if err != nil {
			respond(w, 500, map[string]string{"error": "Cannot create a pairing code."})
			return
		}
		respond(w, 200, map[string]any{"code": code, "expires_at": time.Now().Add(10 * time.Minute).Unix()})
	})
	mux.HandleFunc("POST /api/v1/devices/{id}/revoke", func(w http.ResponseWriter, r *http.Request) {
		if err := store.Revoke(r.PathValue("id")); err != nil {
			respond(w, 500, map[string]string{"error": "Could not revoke this Kindle."})
			return
		}
		respond(w, 200, map[string]bool{"revoked": true})
	})
	mux.HandleFunc("POST /api/v1/devices/pair", func(w http.ResponseWriter, r *http.Request) {
		var value struct {
			Code string `json:"code"`
			Name string `json:"name"`
		}
		if !decode(w, r, &value, 2048) {
			return
		}
		id, secret, err := store.Claim(value.Code, value.Name, time.Now())
		if err != nil {
			respond(w, 401, map[string]string{"error": "Pairing code is invalid, expired or already used. Generate a new code in the dashboard."})
			return
		}
		respond(w, 200, map[string]string{"device_id": id, "token": secret})
	})
	mux.HandleFunc("POST /api/v1/sync", func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		id, err := store.DeviceToken(strings.TrimPrefix(header, "Bearer "))
		if !strings.HasPrefix(header, "Bearer ") || err != nil {
			respond(w, 401, map[string]string{"error": "This Kindle is not authorized. Pair it again from the dashboard."})
			return
		}
		var value Upload
		if !decode(w, r, &value, 8<<20) {
			return
		}
		if err = store.Accept(id, value, time.Now()); err != nil {
			status := 400
			if errors.Is(err, errStale) || errors.Is(err, errChanged) {
				status = 409
			}
			if errors.Is(err, errCredentials) {
				status = 401
			}
			respond(w, status, map[string]string{"error": err.Error()})
			return
		}
		respond(w, 200, map[string]any{"accepted_sequence": value.Sequence, "books": len(value.Books), "activity": len(value.Activity), "achievements": len(value.Achievements)})
	})
	mux.HandleFunc("/api/", func(w http.ResponseWriter, r *http.Request) {
		respond(w, 404, map[string]string{"error": "Endpoint not found."})
	})
	assets := http.FileServer(http.Dir(webDir))
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			w.Header().Set("Allow", "GET, HEAD")
			http.Error(w, "Method not allowed", 405)
			return
		}
		if strings.HasPrefix(r.URL.Path, "/assets/") {
			w.Header().Set("Cache-Control", "public, max-age=3600")
			assets.ServeHTTP(w, r)
			return
		}
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		index := filepath.Join(webDir, "index.html")
		if _, err := os.Stat(index); err != nil {
			http.Error(w, "Dashboard assets are missing. Build server/web first.", 503)
			return
		}
		w.Header().Set("Cache-Control", "no-cache")
		http.ServeFile(w, r, index)
	})
	public := map[string]bool{"/api/v1/auth/status": true, "/api/v1/auth/setup": true, "/api/v1/auth/login": true, "/api/v1/devices/pair": true, "/api/v1/sync": true}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "same-origin")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'")
		if strings.HasPrefix(r.URL.Path, "/api/") {
			if r.Method != "GET" && r.Method != "HEAD" {
				site := r.Header.Get("Sec-Fetch-Site")
				origin := r.Header.Get("Origin")
				if site != "" && site != "same-origin" && site != "none" || origin != "" && origin != "http://"+r.Host && origin != "https://"+r.Host && origin != publicURL {
					respond(w, 403, map[string]string{"error": "Cross-origin requests are not allowed."})
					return
				}
			}
			if !public[r.URL.Path] && !store.Session(session(r), time.Now()) {
				respond(w, 401, map[string]string{"error": "Sign in to your reading home."})
				return
			}
			if r.Method == "POST" && (r.URL.Path == "/api/v1/auth/setup" || r.URL.Path == "/api/v1/auth/login" || r.URL.Path == "/api/v1/devices/pair") && !allowAuth() {
				w.Header().Set("Retry-After", "60")
				respond(w, 429, map[string]string{"error": "Too many attempts. Wait a minute and try again."})
				return
			}
		}
		mux.ServeHTTP(w, r)
	})
}
