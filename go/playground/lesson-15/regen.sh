#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT

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
run gofmt -l .
run go vet ./...

version="lesson15-local"
commit="abc1234"
build_time="2026-09-16T00:00:00Z"
ldflags="-s -w -X main.version=$version -X main.commit=$commit -X main.buildTime=$build_time"

run go build -trimpath -ldflags "$ldflags" -o "$build_dir/productiondemo" ./cmd/productiondemo
run "$build_dir/productiondemo" -demo

run env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags "$ldflags" -o "$build_dir/productiondemo-linux-amd64" ./cmd/productiondemo
run file "$build_dir/productiondemo-linux-amd64"

if docker info >/dev/null 2>&1; then
	image="go-course-lesson15:verify-$$"
	run docker build --quiet \
		--build-arg "VERSION=$version" \
		--build-arg "COMMIT=$commit" \
		--build-arg "BUILD_TIME=$build_time" \
		-t "$image" .
	run docker image inspect "$image" --format 'image={{.Id}} size={{.Size}}'
	run docker run --rm "$image" -demo
	run docker image rm "$image"
else
	printf '\n$ docker info\ndocker daemon unavailable; Docker build/run skipped\n[exit=0]\n'
fi

printf '\nALL_OUTPUT 生成完毕\n'
