# Chapter 02: Demo Application and Dockerfile

In this chapter, we create the Go service that will be orchestrated throughout this tutorial and package it into an optimized container image.

---

## 1. Application Design

The service is written in Go using only the standard library (`net/http`):
- `GET /`: Returns `Hello from skaffold-demo!` with HTTP 200.
- `GET /healthz`: Returns `OK` with HTTP 200 (serving as the target for Kubernetes liveness and readiness probes).
- Any other route returns HTTP 404.

### Server Hygiene
Production container workloads require predictable lifecycle management:
1. **Graceful shutdown**: Handled via `signal.NotifyContext` listening for `os.Interrupt` and `syscall.SIGTERM`. When Kubernetes sends SIGTERM during a pod termination, the server stops accepting new connections and flushes in-flight requests within a 10-second timeout.
2. **Explicit timeouts**: `ReadHeaderTimeout`, `ReadTimeout`, `WriteTimeout`, and `IdleTimeout` are configured to prevent connection leaks and Slowloris denial-of-service vulnerabilities.
3. **Configurable port**: Reads the `PORT` environment variable, defaulting to `8080`.

---

## 2. Multi-Stage Dockerfile Architecture

Containerizing Go applications benefits from multi-stage builds:

```dockerfile
# syntax=docker/dockerfile:1

# Stage 1: Build the static binary
FROM golang:1.22-alpine AS builder

WORKDIR /src

# Cache dependency layer separately
COPY go.mod go.sum* ./
RUN go mod download

# Copy source code
COPY . .

# Build static binary with BuildKit cache mounts
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-w -s" -o /app/server .

# Stage 2: Minimal non-root runtime container
FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /app
COPY --from=builder /app/server /app/server

USER nonroot:nonroot
EXPOSE 8080

ENTRYPOINT ["/app/server"]
```

### Key Architectural Decisions:
1. **Separated Dependency Caching**: `go.mod` is copied and `go mod download` executed before copying the remaining source code. Code changes do not invalidate the module cache.
2. **BuildKit Cache Mounts**: `--mount=type=cache,target=/go/pkg/mod` and `--mount=type=cache,target=/root/.cache/go-build` persist Go compiler cache between builds, yielding sub-second rebuilds.
3. **Static Binary Compilation**: `CGO_ENABLED=0` produces a self-contained statically linked binary without libc dependencies.
4. **Distroless Runtime**: `gcr.io/distroless/static-debian12:nonroot` contains only the minimal files required to run a static binary (CA certificates, timezone data, `/etc/passwd`). It contains no shell, package manager, or package vulnerabilities.
5. **Non-Root User**: The image runs under UID 65532 (`nonroot`), adhering to the principle of least privilege.

---

## 3. Running with Plain Docker

Test the image standalone:

```bash
# 1. Build the image
docker build -t skaffold-demo:v1 .

# 2. Run the container locally
docker run -d --name skaffold-demo -p 8080:8080 skaffold-demo:v1

# 3. Verify endpoints
curl http://localhost:8080/
# Hello from skaffold-demo!

curl http://localhost:8080/healthz
# OK

# 4. Clean up
docker stop skaffold-demo && docker rm skaffold-demo
```

---

## 4. The Friction Plain Docker Introduces

Running this service in Kubernetes without Skaffold requires repeated manual intervention for every single code edit:

1. **Tag Management**: You must invent a tag (e.g., `v1`, `v2`, or a git commit timestamp) for each build.
2. **Cluster Side-loading**: Since Kind nodes run in separate Docker containers, your local Docker daemon's images are not visible to Kind until you manually run:
   ```bash
   kind load docker-image skaffold-demo:<tag> --name skaffold-demo
   ```
3. **Manifest Patching**: You must update your deployment manifest with the newly generated tag or run `kubectl set image`.
4. **Rollout Verification**: You must manually run `kubectl rollout status` and check pod logs.
5. **Port Forwarding**: You must restart `kubectl port-forward` when previous pods terminate.

In Phase 3, we write the raw Kubernetes manifests to experience this manual flow firsthand before handing it over to Skaffold in Phase 4.
