#!/usr/bin/env bash
#
# tests/run_tests.sh —— 手写测试运行器
#
# 为什么手写而不用 bats？
#   本机未安装 bats-core（课 12 已确认），且按阶段 4 约定不擅自安装。
#   手写运行器反而把断言写得更加显式，读者能直接看到每条断言在验什么。
#
# 用法：
#   bash tests/run_tests.sh            跑全部
#   bash tests/run_tests.sh core       只跑文件名含 core 的用例
#
# 退出码：0 全通过 / 1 有失败

set -uo pipefail

TESTS_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly TESTS_DIR
readonly PROJECT_ROOT=$(cd -- "$TESTS_DIR/.." && pwd)

PASS_COUNT=0
FAIL_COUNT=0
declare -a FAILED_NAMES=()

# 断言：相等
assert_eq() {
  local expected=$1 actual=$2 msg=${3:-}
  if [[ $expected == "$actual" ]]; then
    return 0
  fi
  printf '    ✗ assert_eq 失败: %s\n' "$msg"
  printf '      期望: %q\n' "$expected"
  printf '      实际: %q\n' "$actual"
  return 1
}

# 断言：不相等
assert_ne() {
  local unexpected=$1 actual=$2 msg=${3:-}
  if [[ $unexpected != "$actual" ]]; then
    return 0
  fi
  printf '    ✗ assert_ne 失败: %s\n' "$msg"
  printf '      不期望: %q（实际就是它）\n' "$unexpected"
  return 1
}

# 断言：包含子串
assert_contains() {
  local haystack=$1 needle=$2 msg=${3:-}
  if [[ $haystack == *"$needle"* ]]; then
    return 0
  fi
  printf '    ✗ assert_contains 失败: %s\n' "$msg"
  printf '      期望包含: %q\n' "$needle"
  printf '      实际内容: %q\n' "$haystack"
  return 1
}

# 断言：不包含子串
assert_not_contains() {
  local haystack=$1 needle=$2 msg=${3:-}
  if [[ $haystack != *"$needle"* ]]; then
    return 0
  fi
  printf '    ✗ assert_not_contains 失败: %s\n' "$msg"
  printf '      期望不包含: %q\n' "$needle"
  printf '      实际内容: %q\n' "$haystack"
  return 1
}

# 断言：退出码等于期望
assert_exit() {
  local expected=$1 actual=$2 msg=${3:-}
  assert_eq "$expected" "$actual" "$msg（退出码）"
}

# 断言：正则匹配
assert_match() {
  local text=$1 pattern=$2 msg=${3:-}
  if [[ $text =~ $pattern ]]; then
    return 0
  fi
  printf '    ✗ assert_match 失败: %s\n' "$msg"
  printf '      期望匹配: %s\n' "$pattern"
  printf '      实际内容: %q\n' "$text"
  return 1
}

# 运行一个测试函数：捕获 stdout/stderr/退出码，任一断言失败则整体失败
#
# ⚠️ 关键设计（实测确认，见 repro4_scope_and_resource.sh）：
#   被 source 的库文件里若用 declare（不带 -g），在【函数内】source 时
#   这些变量会变成该函数的【局部变量】，函数返回后即消失，
#   后续代码读到 unbound variable。
#   因此不能用 "用例函数内部 source" 的写法，
#   改为在子 shell 顶层先 source，再调用用例函数。
run_test() {
  local name=$1
  local out err rc
  out=$(mktemp)
  err=$(mktemp)

  # 在子 shell 里跑，避免用例之间污染变量。
  # 子 shell 顶层先 source 用例文件（若它设置了 RA_SRC_AT_TOP，则连库一起 source），
  # 再调用具体的 test_ 函数。
  ( set -uo pipefail
    if [[ -n ${RA_SRC_AT_TOP:-} ]]; then
      # shellcheck disable=SC1090
      source "$RA_SRC_AT_TOP"
    fi
    "$name" ) >"$out" 2>"$err"
  rc=$?

  if (( rc == 0 )); then
    PASS_COUNT=$((PASS_COUNT + 1))
    printf '  ✓ %s\n' "$name"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILED_NAMES+=("$name")
    printf '  ✗ %s\n' "$name"
    if [[ -s $err ]]; then
      printf '    --- stderr ---\n'
      sed 's/^/    /' "$err"
    fi
  fi
  rm -f -- "$out" "$err"
  return 0
}

# ─────────────────────────────────────────────────────────────
# 载入用例文件
# ─────────────────────────────────────────────────────────────
main() {
  local filter=${1:-}
  local file
  local -a files=()
  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(find "$TESTS_DIR" -maxdepth 1 -name 'test_*.sh' -print0 | sort -z)

  printf 'release-audit 测试套件\n'
  printf '项目根目录: %s\n' "$PROJECT_ROOT"
  printf '用例文件数: %s\n\n' "${#files[@]}"

  for file in "${files[@]}"; do
    if [[ -n $filter && $file != *"$filter"* ]]; then
      continue
    fi
    printf '[%s]\n' "$(basename -- "$file")"
    # 把用例文件路径交给子 shell：由子 shell 在【顶层】source，
    # 从而让库文件的 declare 变量成为全局的（见 run_test 注释）
    export RA_SRC_AT_TOP="$file"

    # 从文件里解析 test_ 函数名。
    # 不能用 declare -F：用例文件是在【子 shell】里 source 的，
    # 父 shell 的 declare -F 看不到那些函数（这正是刚才 0 通过 0 失败的原因）。
    local t
    while IFS= read -r t; do
      [[ -n $t ]] || continue
      run_test "$t"
    done < <(grep -oE '^test_[A-Za-z0-9_]+[[:space:]]*\(\)' "$file" \
             | sed 's/[[:space:]]*()$//' | sort -u)
    printf '\n'
  done

  printf '════════════════════════════════\n'
  printf '通过: %s   失败: %s\n' "$PASS_COUNT" "$FAIL_COUNT"
  if (( FAIL_COUNT > 0 )); then
    printf '失败用例:\n'
    local n
    for n in "${FAILED_NAMES[@]}"; do
      printf '  - %s\n' "$n"
    done
    return 1
  fi
  printf '全部通过 ✓\n'
  return 0
}

main "$@"
