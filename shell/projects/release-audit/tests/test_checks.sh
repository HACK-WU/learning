# tests/test_checks.sh —— 检查项与端到端集成用例
#
# 本文件由测试运行器在子 shell 顶层 source，库已随 test_core.sh 载入；
# 这里再补上 checks.sh（带 include guard，重复 source 安全）。

RA_TEST_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# 每个用例文件都在【独立的子 shell】里 source，不共享 test_core.sh 的加载结果
#（这正是 test_core 与 test_checks 分开存放带来的约束）。
# 因此这里必须自己 source 全部依赖，且顺序固定：core → report → checks。
# 库都带 include guard，重复 source 是安全的 no-op。
# shellcheck disable=SC1090,SC1091
source "$RA_TEST_ROOT/lib/core.sh"
# shellcheck disable=SC1090,SC1091
source "$RA_TEST_ROOT/lib/report.sh"
# shellcheck disable=SC1090,SC1091
source "$RA_TEST_ROOT/lib/checks.sh"

ra_fixture() {
  local kind=$1
  local d
  ra_mktemp_dir d
  bash "$RA_TEST_ROOT/tests/make_fixture.sh" "$d" "$kind" >/dev/null 2>&1
  printf '%s\n' "$d"
}

# ⚠️ 通用约定（实测，tests/repro9_remaining.sh）：
#   用例文件 source 了 core.sh，而它带 set -e。若直接写
#     out=$(bash release-audit ... )      # 程序返回 2
#   ERR trap 会立刻终止用例 —— 即使你后面想断言"它应该返回 2"。
#   必须显式接住：out=$(cmd ... ) || rc=$?
#   本项目统一用 ra_run 帮手函数，避免每处都重复这个坑。
ra_run() {
  RA_RUN_RC=0
  RA_RUN_OUT=$(bash "$RA_TEST_ROOT/release-audit" "$@" 2>/dev/null) || RA_RUN_RC=$?
  return 0
}

# ── 端到端：退出码分级 ──
test_e2e_clean_returns_zero() {
  local d
  d=$(ra_fixture clean)
  ra_run -q "$d" "$d/MANIFEST"
  assert_exit 0 "$RA_RUN_RC" 'clean 样例应全部通过'
}

test_e2e_warn_returns_one() {
  local d
  d=$(ra_fixture warn)
  ra_run -q "$d" "$d/MANIFEST"
  assert_exit 1 "$RA_RUN_RC" 'warn 样例应返回 1（警告但不阻断）'
}

test_e2e_block_returns_two() {
  local d
  d=$(ra_fixture block)
  ra_run -q "$d" "$d/MANIFEST"
  assert_exit 2 "$RA_RUN_RC" 'block 样例应返回 2（阻断）'
}

test_e2e_tampered_returns_two() {
  local d
  d=$(ra_fixture tampered)
  ra_run -q "$d" "$d/MANIFEST"
  assert_exit 2 "$RA_RUN_RC" 'checksum 被篡改应返回 2'
}

# ── 报告内容 ──
test_report_goes_to_stdout() {
  local d
  d=$(ra_fixture block)
  ra_run -q "$d" "$d/MANIFEST"
  assert_contains "$RA_RUN_OUT" 'release-audit' '报告应有标题'
  assert_contains "$RA_RUN_OUT" 'BLOCK' '报告应含 BLOCK 统计'
  assert_contains "$RA_RUN_OUT" 'TOTAL' '报告应含 TOTAL'
}

test_log_goes_to_stderr_in_e2e() {
  local d
  d=$(ra_fixture clean)
  local out err
  out=$(bash "$RA_TEST_ROOT/release-audit" "$d" "$d/MANIFEST" 2>/dev/null) || true
  err=$(bash "$RA_TEST_ROOT/release-audit" "$d" "$d/MANIFEST" 2>&1 >/dev/null) || true

  # ⚠️ 取证坑（tests/repro11_bracket.sh 实测，修正了我最初的错误假设）：
  #   日志格式是 printf '[%s] [%-5s] %s\n' —— %-5s 让 INFO 补齐到 5 字符，
  #   所以真实标签是 "[INFO ]"【带一个尾空格】，不是 "[INFO]"。
  #   用 "[INFO]" 去匹配永远匹配不上，与单引号、与括号表达式都无关
  #   （实测：[[ ]] 里 *"$pat"* 对方括号就是普通字面匹配，'I' 不会被误命中）。
  #
  #   这里用 grep -F 固定字符串，既避免任何 pattern 解析歧义，
  #   也保证将来若改了日志格式能立刻暴露。
  local pat='[INFO ]'
  if printf '%s' "$out" | grep -qF -- "$pat"; then
    printf '    ✗ 失败: stdout 里不应有日志（日志走 stderr）\n'
    return 1
  fi
  if ! printf '%s' "$err" | grep -qF -- "$pat"; then
    printf '    ✗ 失败: stderr 里应有日志\n'
    return 1
  fi
  return 0
}

# 固化取证坑：日志级别标签是 %-5s 左对齐补空格的，"[INFO]" ≠ "[INFO ]"
# 实测（tests/repro12_label.sh）：
#   [18:23:48] [DEBUG] D     ← DEBUG 正好 5 字符，无尾空格
#   [18:23:48] [INFO ] I     ← INFO 是 4 字符，补 1 个尾空格
#   [18:23:48] [WARN ] W
#   [18:23:48] [ERROR] E
test_log_level_label_has_trailing_space() {
  # 必须先把级别调到 DEBUG，否则 ra_debug / ra_info 的日志被阈值抑制，
  # 命令替换拿到空串 —— 这是我写这条用例时第一个踩到的坑。
  RA_LOG_LEVEL=$RA_LOG_DEBUG

  local extract='s/^\[[^]]*\] \[(.*)\] .*$/\1/'

  local d i w e
  d=$(ra_debug 'x' 2>&1) || true
  i=$(ra_info  'x' 2>&1) || true
  w=$(ra_warn  'x' 2>&1) || true
  e=$(ra_error 'x' 2>&1) || true

  local dlabel ilabel wlabel elabel
  dlabel=$(printf '%s' "$d" | sed -E "$extract")
  ilabel=$(printf '%s' "$i" | sed -E "$extract")
  wlabel=$(printf '%s' "$w" | sed -E "$extract")
  elabel=$(printf '%s' "$e" | sed -E "$extract")

  # %-5s 补到 5 字符：INFO(4)+1 空格、WARN(4)+1 空格；DEBUG/ERROR 本就是 5
  assert_eq 'DEBUG' "$dlabel" 'DEBUG 标签本就是 5 字符'
  assert_eq 'INFO ' "$ilabel" 'INFO 标签应被 %-5s 补齐为 "INFO "（4+1）'
  assert_eq 'WARN ' "$wlabel" 'WARN 标签应被补齐为 "WARN "（4+1）'
  assert_eq 'ERROR' "$elabel" 'ERROR 标签本就是 5 字符'

  assert_eq 5 "${#dlabel}" 'DEBUG 标签长度应为 5'
  assert_eq 5 "${#ilabel}" 'INFO 标签长度应为 5'
  assert_eq 5 "${#wlabel}" 'WARN 标签长度应为 5'
  assert_eq 5 "${#elabel}" 'ERROR 标签长度应为 5'

  RA_LOG_LEVEL=$RA_LOG_INFO
  return 0
}

# 需要 core.sh 的日志函数（本文件已 source，这里只是显式声明依赖）
ra_src_core() { return 0; }

# 报告结构（实测行号，tests/repro9_remaining.sh）：
#   1 release-audit 1.0.0
#   2 目标目录
#   3 审计时间
#   4 并发度
#   5 (空)
#   6 表头
#   7 分隔线
#   8 第一条 finding ← 正文从这里开始
test_report_block_before_info() {
  local d
  d=$(ra_fixture block)
  ra_run -q "$d" "$d/MANIFEST"
  local first_finding
  first_finding=$(printf '%s\n' "$RA_RUN_OUT" | sed -n '8p')
  assert_contains "$first_finding" 'BLOCK' '报告正文首条应是 BLOCK（最严重优先）'
}

# ── 参数与用法 ──
test_help_exit_zero() {
  local rc=0
  bash "$RA_TEST_ROOT/release-audit" --help >/dev/null 2>&1 || rc=$?
  assert_exit 0 "$rc" '--help 应返回 0'
}

test_version_exit_zero() {
  local out rc=0
  out=$(bash "$RA_TEST_ROOT/release-audit" -V 2>/dev/null) || rc=$?
  assert_exit 0 "$rc" '-V 应返回 0'
  assert_match "$out" '^release-audit [0-9]+\.[0-9]+\.[0-9]+$' '版本输出格式'
}

test_missing_dir_returns_66() {
  local rc=0
  bash "$RA_TEST_ROOT/release-audit" /nonexistent-dir-xyz-123 >/dev/null 2>&1 || rc=$?
  assert_exit 66 "$rc" '不存在的目录应返回 66（EX_NOINPUT）'
}

test_unknown_option_returns_64() {
  local rc=0
  bash "$RA_TEST_ROOT/release-audit" --definitely-not-an-option >/dev/null 2>&1 || rc=$?
  assert_exit 64 "$rc" '未知选项应返回 64（EX_USAGE）'
}

test_no_args_returns_64() {
  local rc=0
  bash "$RA_TEST_ROOT/release-audit" >/dev/null 2>&1 || rc=$?
  assert_exit 64 "$rc" '无参数应返回 64'
}

test_bad_jobs_value_returns_64() {
  local rc=0
  bash "$RA_TEST_ROOT/release-audit" --jobs notanumber /tmp >/dev/null 2>&1 || rc=$?
  assert_exit 64 "$rc" '--jobs 非数字应返回 64'
}

test_unknown_skip_name_returns_64() {
  local rc=0
  bash "$RA_TEST_ROOT/release-audit" --skip nosuchcheck /tmp >/dev/null 2>&1 || rc=$?
  assert_exit 64 "$rc" '--skip 未知检查名应返回 64'
}

# ── 注入防护（阶段 4 知识点） ──
test_injection_semicolon_in_dirname() {
  # 目录名里塞分号：若代码有裸 unquoted 展开，这里就会执行 touch
  local base
  ra_mktemp_dir base
  local evil="$base/evil; touch PWNED_INJECT; echo"
  mkdir -p -- "$evil"
  printf '1.0.0\n' >"$evil/VERSION"
  printf 'x\n' >"$evil/f.txt"

  local rc=0
  bash "$RA_TEST_ROOT/release-audit" -q "$evil" >/dev/null 2>&1 || rc=$?

  # 关键：命令注入若发生，会在 CWD 或 base 下出现 PWNED_INJECT
  if [[ -e "$base/PWNED_INJECT" ]]; then
    printf '    ✗ 检测到命令注入！PWNED_INJECT 被创建\n'
    return 1
  fi
  # 目录确实被审计了（不是因为报错而跳过）
  assert_contains "$(bash "$RA_TEST_ROOT/release-audit" -q "$evil" 2>/dev/null)" \
    'release-audit' '含分号的目录名应被正常审计而不执行注入'
}

test_injection_dash_dash_filename() {
  # 文件名以 - 开头：若缺 --，会被当选项解析
  local d
  d=$(ra_fixture clean)
  printf 'sneaky\n' >"$d/-rf"
  local rc=0
  bash "$RA_TEST_ROOT/release-audit" -q "$d" "$d/MANIFEST" >/dev/null 2>&1 || rc=$?
  # 不应崩溃（rc 应为 0/1/2 之一，不能是 64/70）
  if (( rc != 0 && rc != 1 && rc != 2 )); then
    printf '    ✗ 以 - 开头的文件导致异常退出码 %s\n' "$rc"
    return 1
  fi
  return 0
}

# 含空格的文件名：
#   注意初版断言写错了 —— 把文件丢进目录，它没触发任何检查，
#   报告里自然不会出现它（这是正确行为，不是 bug）。
#   要验证"不被词拆分"，必须让它【进入检查路径】：写进清单 → REQUIRED 检查命中。
test_injection_filename_with_spaces() {
  local d
  d=$(ra_fixture clean)
  local spaced='my file with spaces.txt'
  printf 'spaced\n' >"$d/$spaced"
  printf '%s\n' "$spaced" >>"$d/MANIFEST"

  ra_run -q "$d" "$d/MANIFEST"
  assert_exit 0 "$RA_RUN_RC" '含空格的必需文件应被正常找到（不被词拆分）'

  # 反向对照：清单里写一个不存在但含空格的名字，报错信息里的名字必须完整
  printf 'no such file here.txt\n' >>"$d/MANIFEST"
  ra_run -q "$d" "$d/MANIFEST"
  assert_contains "$RA_RUN_OUT" 'no such file here.txt' \
    '缺失文件名含空格时，报告应显示完整名字而非被拆成多个词'
}

# 含 glob 字符的文件名：
#   关键在于【不能被 shell 展开】。若代码写成 ls $f 或 cat $f，
#   file-with-star-*.txt 会被展开成匹配到的所有文件。
test_injection_glob_chars_in_filename() {
  local d
  d=$(ra_fixture clean)
  local globname='file-with-star-*.txt'
  printf 'glob\n' >"$d/$globname"
  printf 'glob\n' >"$d/$globname"
  printf '%s\n' "$globname" >>"$d/MANIFEST"

  ra_run -q "$d" "$d/MANIFEST"
  assert_exit 0 "$RA_RUN_RC" '含 glob 字符的文件名应被当作字面量（不被展开）'

  # 直接验证原义：unquoted 展开会被 glob 展开，加引号则保持原样
  local expanded_count
  expanded_count=$(cd -- "$d" && ls -1 file-with-star-*.txt 2>/dev/null | wc -l)
  assert_eq 1 "$expanded_count" '目录下确实存在这个含 glob 字符的文件'
}

# ── 并发（阶段 3 知识点） ──
test_concurrency_jobs_one_vs_many_same_result() {
  local d
  d=$(ra_fixture clean)
  local r1=0 r2=0
  bash "$RA_TEST_ROOT/release-audit" -q -j 1 "$d" "$d/MANIFEST" >/dev/null 2>&1 || r1=$?
  bash "$RA_TEST_ROOT/release-audit" -q -j 8 "$d" "$d/MANIFEST" >/dev/null 2>&1 || r2=$?
  assert_exit "$r1" "$r2" '并发度 1 与 8 应得到相同退出码'
}

test_concurrency_detects_tamper() {
  local d
  d=$(ra_fixture tampered)
  local rc=0
  bash "$RA_TEST_ROOT/release-audit" -q -j 4 "$d" "$d/MANIFEST" >/dev/null 2>&1 || rc=$?
  assert_exit 2 "$rc" '并发模式也应检出 checksum 篡改'
}

test_concurrency_no_temp_leftover() {
  local d
  d=$(ra_fixture clean)
  local before after
  before=$(ls -1 /tmp 2>/dev/null | grep -c '^release-audit\.' || true)
  ra_run -q "$d" "$d/MANIFEST"
  after=$(ls -1 /tmp 2>/dev/null | grep -c '^release-audit\.' || true)
  # nameref 修复前，登记动作被子 shell 吞掉 → 临时目录泄漏。
  # 这条用例正是那个 bug 的守门人。
  assert_exit "$before" "$after" '运行前后 /tmp 下 release-audit.* 数量应不变（无临时目录泄漏）'
}

# ── 检查项行为 ──
test_skip_check_reduces_findings() {
  local d
  d=$(ra_fixture block)
  ra_run -q "$d" "$d/MANIFEST"
  assert_contains "$RA_RUN_OUT" 'SECRET' '未跳过时报告应含 SECRET finding'

  ra_run -q --skip secret --skip perm "$d" "$d/MANIFEST"
  assert_not_contains "$RA_RUN_OUT" 'SECRET' '--skip secret 后不应出现 SECRET finding'
  assert_not_contains "$RA_RUN_OUT" 'PERM' '--skip perm 后不应出现 PERM finding'
}

test_manifest_metadata_line_not_treated_as_file() {
  # 回归测试：清单里的 version=2.1.0 曾被当成"必需文件 version=2.1.0"，
  # 导致 clean 样例误报 BLOCK（e2e 实测抓出）
  local d
  d=$(ra_fixture clean)
  ra_run -q "$d" "$d/MANIFEST"
  assert_exit 0 "$RA_RUN_RC" 'clean 样例应通过（元数据行不得被误判为文件）'
  assert_not_contains "$RA_RUN_OUT" 'version=2.1.0' '元数据行不应作为必需文件出现在报告中'
}

test_missing_required_file_is_block() {
  local d
  d=$(ra_fixture clean)
  printf 'lib/definitely-missing.jar\n' >>"$d/MANIFEST"
  ra_run -q "$d" "$d/MANIFEST"
  assert_exit 2 "$RA_RUN_RC" '缺失必需文件应阻断'
  assert_contains "$RA_RUN_OUT" 'lib/definitely-missing.jar' '缺失的必需文件应出现在报告'
  assert_contains "$RA_RUN_OUT" '必需文件缺失' '应标记为必需文件缺失'
}

test_empty_dir_is_block() {
  local d
  ra_mktemp_dir d
  ra_run -q "$d"
  assert_exit 2 "$RA_RUN_RC" '空目录应阻断（没有任何文件可发布）'
}

# ── 库幂等性 ──
test_double_source_is_safe() {
  # 重复 source 带 declare -r 的库，在 set -e 下曾直接终止（repro4 实测）
  source "$RA_TEST_ROOT/lib/core.sh"
  source "$RA_TEST_ROOT/lib/report.sh"
  assert_eq 1 "${_RA_CORE_LOADED:-0}" 'core.sh 应标记已载入'
  assert_eq 1 "${_RA_REPORT_LOADED:-0}" 'report.sh 应标记已载入'
}
