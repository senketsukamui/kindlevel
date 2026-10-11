package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/senketsukamui/kindlevel/server/internal/dashboard"
)

func env(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func main() {
	store, err := dashboard.Open(env("KINDLEVEL_DATA_DIR", "data"), time.Now())
	if err != nil {
		log.Fatal(err)
	}
	defer store.Close()
	server := &http.Server{
		Addr:              env("KINDLEVEL_ADDR", ":8080"),
		Handler:           dashboard.Handler(store, env("KINDLEVEL_WEB_DIR", "web/dist")),
		ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second,
		WriteTimeout: 30 * time.Second, IdleTimeout: 60 * time.Second,
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdown); err != nil {
			log.Print(err)
		}
	}()
	log.Printf("Kindlevel listening on %s; pair your Kindle from the dashboard", server.Addr)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
}
