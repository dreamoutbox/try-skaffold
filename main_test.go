package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRootHandler(t *testing.T) {
	router := newRouter()
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)
	resp := w.Result()
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected status 200, got %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("failed to read response body: %v", err)
	}

	expected := "Hello from skaffold-demo (updated)!"
	if !strings.Contains(string(body), expected) {
		t.Fatalf("expected body to contain %q, got %q", expected, string(body))
	}
}

func TestHealthzHandler(t *testing.T) {
	router := newRouter()
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)
	resp := w.Result()
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected status 200, got %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("failed to read response body: %v", err)
	}

	expected := "OK"
	if !strings.Contains(string(body), expected) {
		t.Fatalf("expected body to contain %q, got %q", expected, string(body))
	}
}

func TestNotFoundHandler(t *testing.T) {
	router := newRouter()
	req := httptest.NewRequest(http.MethodGet, "/non-existent-path", nil)
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)
	resp := w.Result()
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("expected status 404, got %d", resp.StatusCode)
	}
}
