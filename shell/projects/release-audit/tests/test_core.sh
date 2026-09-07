# tests/test_core.sh —— 核心库与报告库用例
#
# 每个用例自己 source 被测文件（测试运行器在子 shell 中调用）。

RA_TEST_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
RA_FIXTURE=$(mktemp -d)
RA_TMPFILE=$(mktemp)

# ─────────────────────────────────────────────────────────────
# 顶层 source（不是在函数里！）
# ─────────────────────────────────────────────────────────────
# 本文件由测试运行器在子 shell 顶层 source，因此这里的 source 也在顶层，
# 库里的 declare 变量会成为全局的。
# 若改成 "ra_src() { source ...; }" 再在函数里调用，变量会变成局部的 ——
# 实测结论见 tests/repro4_scope_and_resource.sh。
# shellcheck disable=SC1090,SC1091
source "$RA_TEST_ROOT/lib/core.sh"
# shellcheck disable=SC1090,SC1091
source "$RA_TEST_ROOT/lib/report.sh"

# 保留一个空实现，兼容可能存在的 ra_src 调用；
# 库已加 include guard，重复 source 是安全的 no-op。
ra_src() {
  # shellcheck disable=SC1090,SC1091
  source "$RA_TEST_ROOT/lib/core.sh"
  # shellcheck disable=SC1090,SC1091
  source "$RA_TEST_ROOT/lib/report.sh"
  return 0
}

# ── 退出码语义 ──
test_exit_code_for_all_pass() {
  ra_src
  local rc=0
  ra_exit_code_for 0 0 || rc=$?
  assert_exit 0 "$rc" '无 BLOCK 无 WARN 应通过'
}

test_exit_code_for_warn_only() {
  ra_src
  local rc=0
  ra_exit_code_for 0 3 || rc=$?
  assert_exit 1 "$rc" '仅有 WARN 应返回 1'
}

test_exit_code_for_block() {
  ra_src
  local rc=0
  ra_exit_code_for 2 5 || rc=$?
  assert_exit 2 "$rc" '有 BLOCK 应返回 2，且优先于 WARN'
}

test_exit_code_for_block_zero_warn() {
  ra_src
  local rc=0
  ra_exit_code_for 1 0 || rc=$?
  assert_exit 2 "$rc" '有 BLOCK 即使无 WARN 也返回 2'
}

# ── 严重度排序 ──
test_sev_rank_ordering() {
  ra_src
  assert_eq 3 "$(ra_sev_rank BLOCK)" 'BLOCK rank 3'
  assert_eq 2 "$(ra_sev_rank WARN)" 'WARN rank 2'
  assert_eq 1 "$(ra_sev_rank INFO)" 'INFO rank 1'
  assert_eq 0 "$(ra_sev_rank SKIP)" 'SKIP rank 0'
}

test_sev_rank_unknown_falls_to_zero() {
  ra_src
  assert_eq 0 "$(ra_sev_rank NOPE)" '未知严重度回落到 0，不报错'
}

# ── finding 收集 ──
test_add_finding_appends() {
  ra_src
  RA_FINDINGS=()
  ra_add_finding 'C1' 'BLOCK' 'a.txt' 'boom'
  assert_eq 1 "${#RA_FINDINGS[@]}" '应收集到 1 条'
}

test_add_finding_uses_tab_separator() {
  ra_src
  RA_FINDINGS=()
  ra_add_finding 'C1' 'BLOCK' 'a.txt' 'boom'
  local f="${RA_FINDINGS[0]}"
  assert_eq 4 "$(awk -F'\t' '{print NF}' <<<"$f")" '一条 finding 应是 4 个 TAB 分隔字段'
}

test_add_finding_sanitizes_embedded_tab() {
  ra_src
  RA_FINDINGS=()
  # 文件名里塞 TAB，必须被替换成空格，否则报告列会错位
  ra_add_finding 'C1' 'BLOCK' "$(printf 'a\tb')" 'msg'
  local f="${RA_FINDINGS[0]}"
  assert_eq 4 "$(awk -F'\t' '{print NF}' <<<"$f")" '内嵌 TAB 被清理后仍是 4 字段'
}

test_add_finding_invalid_severity_falls_back() {
  ra_src
  RA_FINDINGS=()
  ra_add_finding 'C1' 'NOPE' 'a.txt' 'msg' 2>/dev/null
  local f="${RA_FINDINGS[0]}"
  assert_contains "$f" 'INFO' '非法严重度应回落为 INFO'
}

test_add_finding_filename_with_spaces() {
  ra_src
  RA_FINDINGS=()
  ra_add_finding 'C1' 'WARN' 'my file name.txt' 'spaced'
  local f="${RA_FINDINGS[0]}"
  assert_contains "$f" 'my file name.txt' '含空格的文件名应完整保留'
}

# ── 统计 ──
test_count_by_severity() {
  ra_src
  RA_FINDINGS=()
  ra_add_finding 'C1' 'BLOCK' 'a' 'm1'
  ra_add_finding 'C2' 'BLOCK' 'b' 'm2'
  ra_add_finding 'C3' 'WARN'  'c' 'm3'
  ra_add_finding 'C4' 'INFO'  'd' 'm4'
  local -A counts=()
  ra_count_by_severity counts
  assert_eq 2 "${counts[BLOCK]}" 'BLOCK 计数'
  assert_eq 1 "${counts[WARN]}" 'WARN 计数'
  assert_eq 1 "${counts[INFO]}" 'INFO 计数'
  assert_eq 0 "${counts[SKIP]}" 'SKIP 计数（未出现也应为 0 而不是空）'
}

test_count_by_severity_empty() {
  ra_src
  RA_FINDINGS=()
  local -A counts=()
  ra_count_by_severity counts
  assert_eq 0 "${counts[BLOCK]}" '空 findings 时 BLOCK 应为 0'
  assert_eq 0 "${#RA_FINDINGS[@]}" '总数应为 0'
}

# ── 报告渲染 ──
test_render_block_comes_first() {
  ra_src
  RA_FINDINGS=()
  ra_add_finding 'C1' 'INFO'  'a' 'info-msg'
  ra_add_finding 'C2' 'BLOCK' 'b' 'block-msg'
  ra_add_finding 'C3' 'WARN'  'c' 'warn-msg'
  local out
  out=$(ra_render_findings)
  local first_line
  first_line=$(head -1 <<<"$out")
  assert_contains "$first_line" 'BLOCK' '报告首行应是 BLOCK（最严重优先）'
}

test_render_contains_all_severities() {
  ra_src
  RA_FINDINGS=()
  ra_add_finding 'C1' 'INFO'  'a' 'i'
  ra_add_finding 'C2' 'BLOCK' 'b' 'b'
  ra_add_finding 'C3' 'WARN'  'c' 'w'
  local out
  out=$(ra_render_findings)
  assert_contains "$out" 'BLOCK' '含 BLOCK'
  assert_contains "$out" 'WARN' '含 WARN'
  assert_contains "$out" 'INFO' '含 INFO'
}

test_render_summary_totals() {
  ra_src
  RA_FINDINGS=()
  ra_add_finding 'C1' 'BLOCK' 'a' 'm'
  ra_add_finding 'C2' 'WARN'  'b' 'm'
  local out
  out=$(ra_render_summary)
  assert_contains "$out" 'BLOCK' 'summary 含 BLOCK 行'
  assert_contains "$out" 'WARN' 'summary 含 WARN 行'
  assert_contains "$out" 'TOTAL' 'summary 含 TOTAL 行'
}

# ── 日志分级 ──
test_log_respects_level_threshold() {
  ra_src
  RA_LOG_LEVEL=$RA_LOG_ERROR
  local out
  out=$(ra_info 'should be hidden' 2>&1)
  assert_eq '' "$out" 'ERROR 级别下 INFO 日志应被抑制'
}

test_log_error_always_visible() {
  ra_src
  RA_LOG_LEVEL=$RA_LOG_ERROR
  local out
  out=$(ra_error 'must show' 2>&1)
  assert_contains "$out" 'must show' 'ERROR 日志在 ERROR 级别下应可见'
}

test_log_goes_to_stderr_not_stdout() {
  ra_src
  RA_LOG_LEVEL=$RA_LOG_DEBUG
  local out
  out=$(ra_info 'hello' 2>/dev/null)
  assert_eq '' "$out" '日志不应写到 stdout（stdout 留给报告）'
}

test_log_format_has_level_tag() {
  ra_src
  RA_LOG_LEVEL=$RA_LOG_ERROR
  local out
  out=$(ra_error 'boom' 2>&1)
  assert_match "$out" '^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\] \[ERROR\] boom$' '日志格式应为 [时间] [级别] 消息'
}

# ── 安全工具 ──
test_is_safe_name_rejects_traversal() {
  ra_src
  local rc=0
  ra_is_safe_name '../etc/passwd' || rc=$?
  assert_exit 1 "$rc" '含 .. 的名字应被拒绝'
}

test_is_safe_name_rejects_absolute_like() {
  ra_src
  local rc=0
  ra_is_safe_name 'a/b' || rc=$?
  assert_exit 1 "$rc" '含斜杠应被拒绝'
}

test_is_safe_name_rejects_dash_prefix() {
  ra_src
  local rc=0
  ra_is_safe_name '-rf' || rc=$?
  assert_exit 1 "$rc" '以 - 开头应被拒绝（防止当选项解析）'
}

test_is_safe_name_rejects_empty() {
  ra_src
  local rc=0
  ra_is_safe_name '' || rc=$?
  assert_exit 1 "$rc" '空串应被拒绝'
}

test_is_safe_name_accepts_normal() {
  ra_src
  local rc=0
  ra_is_safe_name 'app-1.2.3.tar.gz' || rc=$?
  assert_exit 0 "$rc" '正常文件名应通过'
}

# ── 临时资源清理 ──
test_mktemp_dir_registered() {
  ra_src
  local before=${#_RA_CORE_TEMP_DIRS[@]}
  local d
  # nameref 出参：不能用 d=$(ra_mktemp_dir)，那会开子 shell 把登记动作吞掉
  ra_mktemp_dir d
  local after=${#_RA_CORE_TEMP_DIRS[@]}

  # 分步断言：一次失败也能立刻看出是长度没长、还是路径为空、还是目录没建
  assert_ne '' "$d" '应返回临时目录路径'
  assert_eq "$((before + 1))" "$after" "登记数应从 $before 增长到 $((before + 1))（实际 $after）"
  if [[ ! -d $d ]]; then
    printf '    临时目录不存在: %s\n' "$d"
    return 1
  fi
  return 0
}

test_mktemp_dir_actually_created() {
  ra_src
  local d
  ra_mktemp_dir d
  [[ -d $d ]] || { printf '    临时目录不存在: %s\n' "$d"; return 1; }
  return 0
}

# ── 子 shell 陷阱的回归测试 ──
# 这条用例锁死上面修掉的那个 bug：
#   若有人把 ra_mktemp_dir 改回 "printf 返回值" 的写法，
#   调用方就必须用命令替换，登记动作会被子 shell 吞掉，这条会立刻变红。
test_mktemp_dir_registers_in_current_shell() {
  ra_src
  local d
  ra_mktemp_dir d
  # 关键：不是比较 before/after，而是确认【当前 shell】的数组里确实有它
  local found=0
  local p
  for p in "${_RA_CORE_TEMP_DIRS[@]}"; do
    [[ $p == "$d" ]] && found=1
  done
  assert_eq 1 "$found" '临时目录必须登记在当前 shell 的数组中（不能被子 shell 吞掉）'
}

# ── 严格模式是真实打开的 ──
#
# ⚠️ 取证方法本身有坑（实测，tests/repro8_strict.sh）：
#   用 `set +o | grep errexit` 取证【不可靠】——
#     顶层读：          errexit=+o/-o  会变化
#     在【函数里】读：  errexit=+o     ← 明明开着却显示未开启
#     在【命令替换】里：errexit 直接从列表里消失
#   原因：set -e 的状态在函数/命令替换上下文中会被重置，
#   而 assert_contains 内部正是命令替换 —— 取证手段污染了被取证对象。
#
#   可靠做法：读只读变量 $SHELLOPTS。它是 bash 维护的冒号分隔快照，
#   不受调用上下文影响，且赋值即报错，天然防篡改。
test_strict_mode_flags_enabled() {
  ra_src
  # 前后加冒号，保证整体匹配而不是子串误命中（如 'noexec' 含 'exec'）
  local opts=":${SHELLOPTS}:"
  assert_contains "$opts" ':errexit:'  'set -e 应开启（core.sh 设置）'
  assert_contains "$opts" ':nounset:'  'set -u 应开启'
  assert_contains "$opts" ':pipefail:' 'set -o pipefail 应开启'
  assert_contains "$opts" ':errtrace:' 'set -E 应开启（没有它 ERR trap 不继承进函数）'
}

# 配套用例：把上面那个取证坑本身固化成知识，防止后人重新踩
test_strict_mode_evidence_must_use_shellopts() {
  ra_src
  # 证明 set +o 在函数+命令替换的上下文里【不可靠】：
  # 明明 errexit 开着，命令替换里取到的 on_flags 却不含 errexit
  local on_flags
  on_flags=$(set +o | awk '$2=="-o" {print $3}')
  local via_seto=0
  [[ $on_flags == *errexit* ]] && via_seto=1

  local via_shellopts=0
  [[ ":${SHELLOPTS}:" == *:errexit:* ]] && via_shellopts=1

  # 断言：SHELLOPTS 取到的必须是 1；而 set +o 取到的【可能】是 0
  assert_eq 1 "$via_shellopts" 'SHELLOPTS 应能稳定读到 errexit'
  if (( via_seto == 0 )); then
    # 这正是观察到的现象，记录它而不是当成失败
    ra_debug "已复现取证坑：命令替换里 set +o 读不到 errexit（故必须用 SHELLOPTS）"
  fi
  return 0
}
