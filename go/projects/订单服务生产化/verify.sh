#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_FILE="$PROJECT_DIR/ALL_OUTPUT.txt"
cd "$PROJECT_DIR"

: > "$OUTPUT_FILE"

run() {
  { printf '\n$'; printf ' %q' "$@"; printf '\n'; } | tee -a "$OUTPUT_FILE"
  "$@" 2>&1 | tee -a "$OUTPUT_FILE"
}

run go version
run go test -count=1 ./...
run go test -race -count=1 ./...

printf '\n$ gofmt -l .\n' | tee -a "$OUTPUT_FILE"
if [ -n "$(gofmt -l .)" ]; then
  gofmt -l . | tee -a "$OUTPUT_FILE"
  exit 1
fi
printf 'gofmt-clean\n' | tee -a "$OUTPUT_FILE"

run go vet ./...
run go build ./...
run go test -run '^$' -bench '^BenchmarkEncodeOrder$' -benchmem ./internal/order
PROFILE_FILE="${TMPDIR:-/tmp}/go-order-service-cpu.prof"
TEST_BINARY="${TMPDIR:-/tmp}/go-order-service.test"
run go test -o "$TEST_BINARY" -cpuprofile="$PROFILE_FILE" -run '^$' -bench '^BenchmarkEncodeOrder$' -benchtime=200ms ./internal/order
run go tool pprof -top "$PROFILE_FILE"
rm -f "$PROFILE_FILE"
rm -f "$TEST_BINARY"
run go run -ldflags='-X main.version=capstone-local -X main.commit=working-tree -X main.buildTime=2026-09-16T00:00:00Z' ./cmd/order-service -demo

LINUX_BINARY="${TMPDIR:-/tmp}/go-order-service-linux-amd64"
run env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags='-s -w' -o "$LINUX_BINARY" ./cmd/order-service
run file "$LINUX_BINARY"
rm -f "$LINUX_BINARY"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  IMAGE="go-order-service:capstone-local"
  run docker build --tag "$IMAGE" --build-arg VERSION=container-local --build-arg COMMIT=working-tree --build-arg BUILD_TIME=2026-09-16T00:00:00Z .
  run docker run --rm "$IMAGE" -demo
  run docker image rm "$IMAGE"
else
  printf '\nDocker skipped: daemon unavailable\n' | tee -a "$OUTPUT_FILE"
fi

printf '\nverification=passed\n' | tee -a "$OUTPUT_FILE"
