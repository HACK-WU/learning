#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

run() {
  printf '\n$'
  printf ' %q' "$@"
  printf '\n'
  "$@"
  printf '[exit=%d]\n' "$?"
}

run go version
run go test -v -count=1 ./...
run go test -race -count=1 ./...
run go test -run '^$' -bench 'BenchmarkConcat' -benchmem -count=3 ./hotpath
run gofmt -l .
run go vet ./...
run go build ./...

printf '\n$ go build -gcflags=-m=2 ./... (filtered escape-analysis lines)\n'
escape_output="$(go build -gcflags=-m=2 ./... 2>&1)"
printf '%s\n' "$escape_output" | rg 'escapes to heap|does not escape' | sed -n '1,18p'
printf '[exit=0]\n'

profile_dir="$(mktemp -d)"
trap 'rm -rf "$profile_dir"' EXIT
printf '\n$ go run ./cmd/profiledemo -out <temporary-profile-dir>\n'
go run ./cmd/profiledemo -out "$profile_dir"
printf '[exit=%d]\n' "$?"

for profile in cpu heap goroutine block goroutineleak; do
  printf '\n$ go tool pprof -top <temporary-profile-dir>/%s.prof\n' "$profile"
  go tool pprof -top "$profile_dir/$profile.prof" | sed -n '1,24p'
  printf '[exit=%d]\n' "$?"
done

printf '\nALL_OUTPUT 生成完毕\n'
