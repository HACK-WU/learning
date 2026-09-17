#!/usr/bin/env bash
# 课 12 证据汇总：顺序跑完所有探针 + 摘录 GOROOT 源码原文 → ALL_OUTPUT.txt
#
# 用法：bash regen.sh > ALL_OUTPUT.txt 2>&1
set -uo pipefail
export PATH=/usr/local/bin:$PATH
cd "$(dirname "$0")"

R=$(go env GOROOT)

sec() { printf '\n\n########## %s ##########\n' "$1"; }
sub() { printf '\n--- %s ---\n' "$1"; }
run() {                      # run <显示命令> <命令...>
  local label="$1"; shift
  printf '\n$ %s\n' "$label"
  "$@" 2>&1
  printf '[exit=%d]\n' $?
}

sec "0. 环境"
run "go version" go version
run "go env GOROOT GOOS GOARCH" go env GOROOT GOOS GOARCH
run "sysctl -n machdep.cpu.brand_string / hw.ncpu" sh -c 'sysctl -n machdep.cpu.brand_string; sysctl -n hw.ncpu'
run "sw_vers" sw_vers
run "go env GOEXPERIMENT" go env GOEXPERIMENT
run "cat go.mod" cat go.mod

sec "1. GOROOT 源码原文摘录（本课依赖的事实）"

sub "database/sql：DB 是连接池"
sed -n '500,516p' "$R/src/database/sql/sql.go"
sub "database/sql：sql.Open 的注释"
sed -n '851,867p' "$R/src/database/sql/sql.go"
sub "database/sql：defaultMaxIdleConns 常量与 maxIdleConnsLocked"
sed -n '965,979p' "$R/src/database/sql/sql.go"
sub "database/sql：SetMaxIdleConns / SetMaxOpenConns 注释"
sed -n '987,1034p' "$R/src/database/sql/sql.go"
sub "database/sql：SetConnMaxLifetime / SetConnMaxIdleTime 注释"
sed -n '1047,1090p' "$R/src/database/sql/sql.go"
sub "database/sql：connectionCleaner 的 minInterval = time.Second"
sed -n '1100,1102p' "$R/src/database/sql/sql.go"
sub "database/sql：QueryContext / ExecContext / Rows.Close / DB.Close 注释"
sed -n '1740,1742p' "$R/src/database/sql/sql.go"
sed -n '1670,1672p' "$R/src/database/sql/sql.go"
sed -n '3478,3481p' "$R/src/database/sql/sql.go"
sed -n '925,930p' "$R/src/database/sql/sql.go"
sub "database/sql：ErrNoRows 与包注释里「驱动不支持取消就不会提前返回」"
sed -n '497,500p' "$R/src/database/sql/sql.go"
sed -n '5,15p' "$R/src/database/sql/sql.go"

sub "database/sql driver：ErrBadConn / Validator"
grep -n -B6 "ErrBadConn = " "$R/src/database/sql/driver/driver.go"
grep -n -A6 "type Validator interface" "$R/src/database/sql/driver/driver.go"

sub "net/http：Client 结构体与 Timeout 注释"
sed -n '32,37p' "$R/src/net/http/client.go"
sed -n '96,111p' "$R/src/net/http/client.go"
sub "net/http：Client.Do 注释（含 1.27 新增的“异步排空”承诺）"
sed -n '566,574p' "$R/src/net/http/client.go"
sub "net/http：Response.Body 注释（含 1.27 新增段）"
sed -n '54,76p' "$R/src/net/http/response.go"
sub "net/http：http.Get 注释"
sed -n '449,453p' "$R/src/net/http/client.go"
sub "net/http：DefaultTransport 全文"
sed -n '47,58p' "$R/src/net/http/transport.go"
sub "net/http：DefaultMaxIdleConnsPerHost 与 MaxIdleConnsPerHost 字段注释"
sed -n '60,62p' "$R/src/net/http/transport.go"
sed -n '209,216p' "$R/src/net/http/transport.go"
sub "net/http：Transport 结构体开头注释"
sed -n '65,78p' "$R/src/net/http/transport.go"
sub "net/http：1.27 新增的 maxPostCloseReadBytes / maxPostCloseReadTime / maybeDrainBody"
sed -n '2414,2446p' "$R/src/net/http/transport.go"
sub "net/http：Transport.RoundTrip 注释（Body 必须关闭）"
grep -n -B14 "^func (t \*Transport) RoundTrip" "$R/src/net/http/transport.go" | head -20
sub "net/http：httpproxy 自动排除 localhost 与回环 IP"
sed -n '167,190p' "$R/src/vendor/golang.org/x/net/http/httpproxy/proxy.go"

sub "time：Time 结构体注释（单调时钟部分）"
sed -n '126,140p' "$R/src/time/time.go"
sub "time：包文档 Monotonic Clocks 全节"
N=$(grep -n 'Monotonic Clocks' "$R/src/time/time.go" | head -1 | cut -d: -f1)
sed -n "$N,$((N+66))p" "$R/src/time/time.go"
sub "time：Since / Until 注释"
sed -n '1225,1238p' "$R/src/time/time.go"
sub "time：Timer 与 NewTimer / Stop / Reset 注释（Go 1.23 变更）"
sed -n '60,64p' "$R/src/time/sleep.go"
sed -n '66,84p' "$R/src/time/sleep.go"
sed -n '89,115p' "$R/src/time/sleep.go"
sub "time：After / AfterFunc 注释"
sed -n '166,190p' "$R/src/time/sleep.go"
sub "time：Ticker / NewTicker / Stop / Tick 注释"
sed -n '14,27p' "$R/src/time/tick.go"
sed -n '50,56p' "$R/src/time/tick.go"
sed -n '76,94p' "$R/src/time/tick.go"
sub "time：布局串常量全表与标准 token 表"
sed -n "$(grep -n '^const (' "$R/src/time/format.go" | head -1 | cut -d: -f1),+36p" "$R/src/time/format.go"
sub "time：Format 注释"
sed -n '633,639p' "$R/src/time/format.go"
sub "time：Parse 的时区规则与两位年规则"
sed -n '1002,1025p' "$R/src/time/format.go"
sub "time：ParseInLocation 注释"
sed -n '1036,1041p' "$R/src/time/format.go"
sub "time：官方测试断言 handler 的 cap == 0"
sed -n '396,402p' "$R/src/time/tick_test.go"
sub "runtime：timeTimer 布局与 newTimer（dataqsiz 校验）"
sed -n '384,415p' "$R/src/runtime/time.go"
sub "runtime：timer 结构体里 isChan 的说明"
sed -n '61,72p' "$R/src/runtime/time.go"

sec "2. 知识点 1：database/sql"
run "go run ./p1_pool（自写 driver 证明 sql.DB 是池）" go run ./p1_pool
run "go run ./p2_query_exec（真实 sqlite：Query/Exec/Scan/ErrNoRows）" go run ./p2_query_exec
run "go run ./p3_injection（参数化 vs 拼接）" go run ./p3_injection
run "go run ./p4_tx（事务）" go run ./p4_tx
run "go run ./p5_ctx_chain（客户端断开 → r.Context() → 查询中止）" go run ./p5_ctx_chain
run "go run ./p6_rows_memory（Rows 泄漏 + :memory: 隔离）" go run ./p6_rows_memory
run "go run ./p15_dao（知识点 1 的完整 mini DAO 示例：池配置 + CRUD + 事务 + 注入对照 + Stats）" go run ./p15_dao

sec "3. 知识点 2：http.Client"
run "go run ./p8_client_timeout（默认无超时 / Timeout 覆盖读 body / DefaultTransport 实参 / 代理）" go run ./p8_client_timeout
run "go run ./p9_bodyclose（连接复用 6 种写法 + MaxIdleConnsPerHost）" go run ./p9_bodyclose
run "go run ./p10_retry（重试边界 + MaxConnsPerHost + 复用 Client）" go run ./p10_retry
run "go run ./p16_downstream（知识点 2 的完整示例：生产级下游客户端封装）" go run ./p16_downstream

sec "4. 知识点 3：时间与定时器"
run "go run ./p11_monotonic（单调时钟与它的丢失）" go run ./p11_monotonic
run "go run ./p12_timer（Ticker/Timer 的 Stop 与 Reset）" go run ./p12_timer
run "go run ./p12b_timer_gc（cap 之谜 + AfterFunc 内存）" go run ./p12b_timer_gc
run "go run ./p18_timerstop（Timer.Stop 返回值语义：Go 1.23 起「已到期但未接收」仍返回 true）" go run ./p18_timerstop
run "go test -bench=. -benchtime=300ms -benchmem -count=2 ./p13_afterbench" go test -bench=. -benchtime=300ms -benchmem -count=2 ./p13_afterbench
run "go run ./p14_layout（布局串 / Parse / 时区 / 时间戳）" go run ./p14_layout
run "go run ./p17_timeutil（知识点 3 的完整示例：定时任务骨架 / 热路径分配 / 格式化解析 / 单调时钟）" go run ./p17_timeutil

sec "5. 静态检查"
run "gofmt -l ." gofmt -l .
run "go vet ./..." go vet ./...
run "go build ./..." go build ./...

sec "结束"
echo "ALL_OUTPUT 生成完毕"
