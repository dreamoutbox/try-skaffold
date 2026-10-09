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
