#!/usr/bin/env bash
# 课 13 证据汇总：模块、测试与规范的最小可运行示例。
set -euo pipefail

cd "$(dirname "$0")"

run() {
	local label="$1"
	shift
	printf '\n$ %s\n' "$label"
	"$@"
	printf '[exit=%d]\n' "$?"
}

run "go version" go version
run "go list -m all" go list -m all
run "go mod tidy -diff" go mod tidy -diff
run "go test -v ./..." go test -v ./...
run "go test -race ./..." go test -race ./...
run "go test -cover ./..." go test -cover ./...
run "gofmt -l ." gofmt -l .
run "go vet ./..." go vet ./...
run "go build ./..." go build ./...
run "go run ./cmd/demo" go run ./cmd/demo

printf '\nALL_OUTPUT 生成完毕\n'
