#!/usr/bin/env bash
# lib/core.sh —— 严格模式、日志分级、退出码、trap 清理、临时目录管理
#
# 为什么单独成库：wf-lab 的每个子命令都要"能在 CI 里被机器读懂"，
# 退出码与日志流必须全局统一，否则编排层无法判断一步是否成功。

# ── include guard ─────────────────────────────────────────
# ⚠️ 必须：本项目有 5 个库都 source 本文件，不加 guard 会导致
#    ① readonly 变量重复赋值报错（set -e 下直接中断）
#    ② WF_TMP_DIRS 被重置 → 已登记的临时目录泄漏
#    ③ trap 被重复注册
[[ -n ${_WF_CORE_LOADED:-} ]] && return 0
_WF_CORE_LOADED=1

set -Eeuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# ── 退出码 ────────────────────────────────────────────────
# 三档刻意分开：混成一个 1，调用方就只能 grep 日志文本判断成败，
# 那是把结构化信息降级成字符串匹配。
readonly WF_OK=0        # 全部通过
readonly WF_WARN=1      # 有警告，可以继续
readonly WF_BLOCK=2     # 有阻断项，必须停下
readonly WF_USAGE=64    # 用法错误
readonly WF_NOINPUT=66  # 输入不存在/不可读
readonly WF_INTERNAL=70 # 工具自身出错

# ── 日志（写 stderr，报告写 stdout，两者分离）──────────────
WF_VERBOSITY="${WF_VERBOSITY:-1}"   # 0=静默 1=普通 2=调试
WF_LOG_PREFIX="${WF_LOG_PREFIX:-wf-lab}"

_log() {
    local level="$1" weight="$2"; shift 2
    (( weight <= WF_VERBOSITY )) || return 0
    printf '[%s] %s\n' "$level" "$*" >&2
}
log_debug() { _log DEBUG 2 "$@"; }
log_info()  { _log INFO  1 "$@"; }
log_warn()  { _log WARN  1 "$@"; }
log_error() { _log ERROR 0 "$@"; }

# ── die：带上下文的失败退出 ────────────────────────────────
# 错误信息带上下文（哪个路径、哪个参数），排障成本差一个数量级。
die() {
    local code="$1"; shift
    printf '%s: ERROR: %s\n' "$WF_LOG_PREFIX" "$*" >&2
    exit "$code"
}
die_usage()  { die "$WF_USAGE"   "$@"; }
die_noinput() { die "$WF_NOINPUT" "$@"; }

# ── 依赖检查 ───────────────────────────────────────────────
# 集中在一处：缺依赖就明确报，不要等到某个子命令跑到一半才炸。
wf_require_cmds() {
    local missing=() c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    (( ${#missing[@]} == 0 )) || die "$WF_INTERNAL" "缺少依赖命令: ${missing[*]}"
}

wf_git_version() { git --version | awk '{print $3}'; }

# ── 临时目录管理 ───────────────────────────────────────────
# ⚠️ 这里用"全局变量 + trap"而不是 stdout 返回值：
#    命令替换 $( ) 会开子 shell，函数内对数组的 += 不回传 → 泄漏。
#    （这是 shell 课程实战项目实测抓到的 D3 号 bug，此处从设计上避开。）
WF_TMP_DIRS=()

wf_mktemp() {
    local d
    d=$(mktemp -d "${TMPDIR:-/tmp}/wf-lab.XXXXXXXX")
    WF_TMP_DIRS+=("$d")
    printf '%s\n' "$d"
}

wf_cleanup() {
    local rc=$?   # ⚠️ 必须是第一行：被信号杀死时 EXIT trap 拿到的 $? 是 0
    local d
    for d in "${WF_TMP_DIRS[@]:-}"; do
        [[ -n $d && -d $d ]] && rm -rf -- "$d"
    done
    return "$rc"
}
trap wf_cleanup EXIT

# ── 结果收集（finding）───────────────────────────────────
# 分级收集，最后统一渲染。与"边跑边 print"相比，好处是能给出退出码。
WF_FINDINGS=()
WF_N_WARN=0
WF_N_BLOCK=0

finding_add() {
    local level="$1" check="$2" msg="$3"
    WF_FINDINGS+=("$level|$check|$msg")
    case "$level" in
        # Use pre-increment: (( x++ )) evaluates to the OLD value, so when the
        # counter is 0 the arithmetic result is 0 and set -e kills the script.
        # This is exactly the trap lesson 4 / the shell course warned about.
        WARN)  (( ++WF_N_WARN  )) ;;
        BLOCK) (( ++WF_N_BLOCK )) ;;
    esac
}

findings_exit_code() {
    # Must use if, not &&: with `cond && return N`, when cond is false the whole
    # AND-list evaluates to 1 and set -e terminates the caller before the next
    # line runs. Commands in an if condition are exempt from set -e.
    if (( WF_N_BLOCK > 0 )); then
        return "$WF_BLOCK"
    fi
    if (( WF_N_WARN > 0 )); then
        return "$WF_WARN"
    fi
    return "$WF_OK"
}

# ── findings 渲染 ─────────────────────────────────────────
findings_render() {
    local f level check msg
    printf '\n'
    printf '%s\n' '══════════ 结果 ══════════'
    if (( ${#WF_FINDINGS[@]} == 0 )); then
        printf '  （无检查项）\n'
    else
        for f in "${WF_FINDINGS[@]}"; do
            IFS='|' read -r level check msg <<<"$f"
            printf '  [%-5s] %-12s %s\n' "$level" "$check" "$msg"
        done
    fi
    printf '\n'
    printf '  BLOCK %d ｜ WARN %d\n' "$WF_N_BLOCK" "$WF_N_WARN"
}

# ── 计数与断言小工具 ──────────────────────────────────────
wf_count_lines() {   # 统计行数，空文件返回 0（wc -l 对无尾换行文件会少算一行）
    local f="$1"
    [[ -s $f ]] || { printf '0\n'; return 0; }
    awk 'END{print NR}' "$f"
}
