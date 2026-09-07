# lib/report.sh —— finding 收集、统计、报告渲染
#
# 本文件被 source，不可直接执行。
#
# 覆盖知识点：
#   阶段 1 ·退出码与严重度的映射（BLOCK>WARN>INFO>SKIP）
#   阶段 2 ·关联数组做计数器、数组收集结果、nameref 避免子 shell 陷阱
#   阶段 4 ·stdout 报告 vs stderr 日志分流、纯函数便于测试

# shellcheck shell=bash

# include guard：重复 source 时直接返回（理由同 core.sh，实测见 repro4）
if [[ -n ${_RA_REPORT_LOADED:-} ]]; then
  return 0
fi
_RA_REPORT_LOADED=1

# ─────────────────────────────────────────────────────────────
# 1. finding 模型
# ─────────────────────────────────────────────────────────────
# 一条 finding = "CHECK<TAB>SEVERITY<TAB>TARGET<TAB>MESSAGE"
# 用 TAB 分隔而不是空格：文件名可能含空格（这是课 13 注入防护的直接场景）。
# 用 TAB 而不是管道或冒号：文件名也可能含这两个字符，TAB 是最不可能出现在文件名里的。

declare -a RA_FINDINGS=()

# 严重度 → 数值，用于比较"最严重的是什么"
ra_sev_rank() {
  case "$1" in
    "$SEV_BLOCK") printf '3\n' ;;
    "$SEV_WARN")  printf '2\n' ;;
    "$SEV_INFO")  printf '1\n' ;;
    "$SEV_SKIP")  printf '0\n' ;;
    *)            printf '0\n' ;;
  esac
}

# ra_add_finding <check_id> <severity> <target> <message>
#
# 为什么不用命令替换收集？
#   findings=$(collect ...)   ← 命令替换开【子 shell】，函数里的数组修改不会传回来。
#                                阶段 3 的核心坑之一。
# 这里用 nameref 直接写全局数组，避免子 shell。
#
# ⚠️ nameref 撞名陷阱（课 6）：被调用方的 local 变量若与 nameref 目标【同名】，
#    赋值会被静默劫持。因此本文件的 nameref 一律用 _ra_nref_ 前缀，
#    与任何调用方的变量名都不可能撞上。
ra_add_finding() {
  local check_id=${1:-unknown}
  local severity=${2:-$SEV_INFO}
  local target=${3:--}
  local message=${4:-}

  # 校验严重度合法，非法值回落到 INFO 并告警（静默吞掉会让报告漏掉阻断项）
  case "$severity" in
    "$SEV_BLOCK"|"$SEV_WARN"|"$SEV_INFO"|"$SEV_SKIP") ;;
    *)
      ra_warn "ra_add_finding 收到非法严重度 '$severity'，回落为 $SEV_INFO"
      severity=$SEV_INFO
      ;;
  esac

  # TAB 不能出现在字段里，否则报告解析会错位
  # 用 ${var//$'\t'/ } 把 TAB 替换成空格 —— 参数展开，零 fork
  check_id=${check_id//$'\t'/ }
  target=${target//$'\t'/ }
  message=${message//$'\t'/ }

  RA_FINDINGS+=("${check_id}"$'\t'"${severity}"$'\t'"${target}"$'\t'"${message}")
  ra_debug "finding: [$severity] $check_id / $target / $message"
  return 0
}

# 统计各严重度数量
# 用法：ra_count_by_severity <关联数组名>
# 用 nameref 把结果写回调用方的关联数组
ra_count_by_severity() {
  local -n _ra_nref_counts=$1
  local f check_id severity target message

  # 初始化四类计数为 0（不初始化的话 set -u 下读取未定义键会报错）
  _ra_nref_counts["$SEV_BLOCK"]=0
  _ra_nref_counts["$SEV_WARN"]=0
  _ra_nref_counts["$SEV_INFO"]=0
  _ra_nref_counts["$SEV_SKIP"]=0

  for f in "${RA_FINDINGS[@]}"; do
    # IFS=$'\t' 只在这条 read 上生效（前面赋值 = 临时环境，不改全局）
    IFS=$'\t' read -r check_id severity target message <<<"$f"
    case "$severity" in
      "$SEV_BLOCK") (( _ra_nref_counts["$SEV_BLOCK"] += 1 )) || true ;;
      "$SEV_WARN")  (( _ra_nref_counts["$SEV_WARN"]  += 1 )) || true ;;
      "$SEV_INFO")  (( _ra_nref_counts["$SEV_INFO"]  += 1 )) || true ;;
      "$SEV_SKIP")  (( _ra_nref_counts["$SEV_SKIP"]  += 1 )) || true ;;
    esac
  done
  return 0
}

# 由统计结果推出退出码 —— 纯函数，无副作用，最容易测试
# 用法：ra_exit_code_for <block_count> <warn_count>
# 返回 0=通过 1=警告 2=阻断
ra_exit_code_for() {
  local blocks=${1:-0}
  local warns=${2:-0}
  if (( blocks > 0 )); then
    return "$EX_BLOCK"
  elif (( warns > 0 )); then
    return "$EX_WARN"
  fi
  return "$EX_OK"
}

# ─────────────────────────────────────────────────────────────
# 2. 报告渲染（写 stdout）
# ─────────────────────────────────────────────────────────────

# 按严重度排序输出：BLOCK 在前（人最需要先看到致命问题）
ra_render_findings() {
  local sev
  local f check_id severity target message
  # 从最严重到最轻
  for sev in "$SEV_BLOCK" "$SEV_WARN" "$SEV_INFO" "$SEV_SKIP"; do
    for f in "${RA_FINDINGS[@]}"; do
      IFS=$'\t' read -r check_id severity target message <<<"$f"
      [[ $severity == "$sev" ]] || continue
      printf '%-6s %-14s %-32s %s\n' "$severity" "$check_id" "$target" "$message"
    done
  done
  return 0
}

ra_render_summary() {
  local -A counts=()
  ra_count_by_severity counts

  printf '\n'
  printf '%-10s %s\n' 'BLOCK' "${counts[$SEV_BLOCK]}"
  printf '%-10s %s\n' 'WARN'  "${counts[$SEV_WARN]}"
  printf '%-10s %s\n' 'INFO'  "${counts[$SEV_INFO]}"
  printf '%-10s %s\n' 'SKIP'  "${counts[$SEV_SKIP]}"
  printf '%-10s %s\n' 'TOTAL' "${#RA_FINDINGS[@]}"
}
