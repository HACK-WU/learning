# lib/core.sh —— 严格模式、日志分级、退出码语义、清理
#
# 本文件被 source，不可直接执行。
#
# 覆盖知识点：
#   阶段 1 ·退出码语义（sysexits.h 分级：0 通过 / 1 警告 / 2 阻断 / 64 用法 / 70 内部）
#   阶段 3 ·trap EXIT 清理、trap ERR 打印调用栈、临时目录生命周期
#   阶段 4 ·set -Eeuo pipefail、日志分级、stdout 报告 vs stderr 日志分流
#           printf '%(...)T' 取时间戳（零 fork，见下方说明）

# shellcheck shell=bash

# ─────────────────────────────────────────────────────────────
# 0. include guard：重复 source 时直接返回
# ─────────────────────────────────────────────────────────────
# 为什么必须加（实测确认，见 tests/repro4_scope_and_resource.sh）：
#   本文件用了 declare -r。第二次 source 时 bash 报
#     "declare: RA_LOG_DEBUG: readonly variable"  退出码非 0，
#   而文件第 1 行就 set -e —— 于是 source 到一半被终止，
#   后面的函数与变量【全部未定义】，调用方拿到 unbound variable。
#   加 guard 后重复 source 变成 no-op，幂等且零副作用。
if [[ -n ${_RA_CORE_LOADED:-} ]]; then
  return 0
fi
_RA_CORE_LOADED=1

# ─────────────────────────────────────────────────────────────
# 1. 严格模式
# ─────────────────────────────────────────────────────────────
# -E  ERR trap 被函数和命令替换继承（没有它，子 shell 里的错误不会触发 ERR trap）
# -e  命令失败即退出
# -u  未定义变量即报错
# -o pipefail  管道任一环节失败，整体即失败
set -Eeuo pipefail

# 刻意【不】全局改 IFS。
# 全局 IFS=$'\n\t' 会影响所有依赖默认 IFS 的命令（read、unquoted 展开、数组赋值）。
# 本脚本在需要时【局部】设置 IFS，用完即恢复 —— 见 ra_read_lines 与 report.sh。

# ─────────────────────────────────────────────────────────────
# 2. 退出码语义（sysexits.h 风格）
# ─────────────────────────────────────────────────────────────
# 为什么不用 0/1 了事：调用方（CI、流水线）需要区分
#   "有警告但能发"  vs  "必须拦下"  vs  "你参数传错了"。
# 三件事混成一个 1，调用方就只能靠 grep 日志文本来判断 —— 那是把结构化信息降级成字符串匹配。
readonly EX_OK=0        # 全部通过
readonly EX_WARN=1      # 有 WARN，不阻断发布
readonly EX_BLOCK=2     # 有 BLOCK，必须阻断
readonly EX_USAGE=64    # 参数/用法错误（EX_USAGE）
readonly EX_NOINPUT=66  # 输入不存在或不可读（EX_NOINPUT）
readonly EX_INTERNAL=70 # 内部错误（EX_SOFTWARE）

# ─────────────────────────────────────────────────────────────
# 3. 严重度
# ─────────────────────────────────────────────────────────────
readonly SEV_BLOCK='BLOCK'
readonly SEV_WARN='WARN'
readonly SEV_INFO='INFO'
readonly SEV_SKIP='SKIP'

# ─────────────────────────────────────────────────────────────
# 4. 日志分级（写 stderr，绝不污染 stdout）
# ─────────────────────────────────────────────────────────────
# 报告走 stdout、日志走 stderr，调用方才能 `release-audit d > report.txt` 拿到干净报告。
# 这是课 12「日志分级 + stderr 分离」的直接应用。
declare -r RA_LOG_DEBUG=0 RA_LOG_INFO=1 RA_LOG_WARN=2 RA_LOG_ERROR=3
RA_LOG_LEVEL=${RA_LOG_LEVEL:-$RA_LOG_INFO}

# 校验日志级别：非法值静默回落到 INFO，而不是让后面每条日志都炸
case "$RA_LOG_LEVEL" in
  0|1|2|3) ;;
  *) RA_LOG_LEVEL=$RA_LOG_INFO ;;
esac

# 时间戳用 printf '%(...)T' —— bash 内建，零 fork。
# 注意区分课 12 实测过的坑：PS4【不】做 printf 格式化（PS4 是提示符展开，不走 printf），
# 但 printf 自身的 %(... )T 【是】支持的。两者不是一回事，别把结论搬错地方。
ra_log() {
  local level_num=$1
  local level_name=$2
  shift 2
  if (( level_num >= RA_LOG_LEVEL )); then
    # 一条 printf 同时输出时间与正文，只 fork 零次
    printf '[%s] [%-5s] %s\n' "$(printf '%(%H:%M:%S)T' -1)" "$level_name" "$*" >&2
  fi
  return 0
}

ra_debug() { ra_log "$RA_LOG_DEBUG" 'DEBUG' "$@"; }
ra_info()  { ra_log "$RA_LOG_INFO"  'INFO'  "$@"; }
ra_warn()  { ra_log "$RA_LOG_WARN"  'WARN'  "$@"; }
ra_error() { ra_log "$RA_LOG_ERROR" 'ERROR' "$@"; }

# ─────────────────────────────────────────────────────────────
# 5. 致命错误
# ─────────────────────────────────────────────────────────────
# 退出码必须先校验是数字：调用方传 'abc' 给 ra_die 会让 exit 报非数字错并退出 128，
# 那时真正的错误信息反而丢了。
ra_die() {
  local code=$1
  shift
  if [[ ! $code =~ ^[0-9]+$ ]]; then
    printf '[ERROR] ra_die 收到非数字退出码 %q，已回落到 %s\n' "$code" "$EX_INTERNAL" >&2
    code=$EX_INTERNAL
  fi
  printf '[ERROR] %s\n' "$*" >&2
  exit "$code"
}

# ─────────────────────────────────────────────────────────────
# 6. ERR trap：失败时打印调用栈位置
# ─────────────────────────────────────────────────────────────
# 没有 -E 的话，函数里的失败不会触发这里；配合 set -E 才能覆盖函数与命令替换。
ra_on_err() {
  local rc=$?
  # BASH_LINENO[0] 是 trap 触发处的行号；BASH_SOURCE[1]/FUNCNAME[1] 是出错的函数
  local line=${BASH_LINENO[0]:-unknown}
  local src=${BASH_SOURCE[1]:-unknown}
  local fn=${FUNCNAME[1]:-main}
  printf '[FATAL] %s:%s  in %s()  退出码 %s\n' "${src##*/}" "$line" "$fn" "$rc" >&2
  exit "$rc"
}
trap ra_on_err ERR

# ─────────────────────────────────────────────────────────────
# 7. 临时资源与 EXIT 清理
# ─────────────────────────────────────────────────────────────
# 阶段 3 知识点：脚本【必然】会被中断（Ctrl-C、CI 超时、kill），
# 清理逻辑不能依赖"正常走到最后一行"，必须挂在 EXIT trap 上。
declare -a _RA_CORE_TEMP_DIRS=()
declare -a _RA_CORE_TEMP_FILES=()

# ⚠️ 关键 API 设计（实测确认，见 tests/repro6_array_subsbleed.sh）：
#
#   错误写法（本项目初版就是这么写的）：
#     ra_mktemp_dir() { d=$(mktemp -d); _RA_CORE_TEMP_DIRS+=("$d"); echo "$d"; }
#     caller_d=$(ra_mktemp_dir)      ← 调用方拿到路径，但……
#
#   命令替换 $(...) 会开【子 shell】。函数里的 _RA_CORE_TEMP_DIRS+=(...)
#   发生在子 shell 中，返回后父 shell 的数组【纹丝不动】：
#       d=$(ra_mktemp_dir);  echo ${#_RA_CORE_TEMP_DIRS[@]}   → 0   ✗
#       直接调 ra_mktemp_dir;  echo ${#_RA_CORE_TEMP_DIRS[@]} → 1   ✓
#     BASH_SUBSHELL 从 1 变成 2，就是铁证。
#
#   后果极隐蔽：目录【确实】创建成功了，但没登记 → EXIT trap 不清理 → 临时目录泄漏。
#   这正是阶段 3「命令替换开子 shell，变量改不动」这一知识点在真实代码里的样子。
#
#   正确写法：用 nameref 出参，函数在当前 shell 里执行，不依赖 stdout。
#     local d; ra_mktemp_dir d; echo "$d"
ra_mktemp_dir() {
  # nameref 目标名统一加 _ra_nref_ 前缀，避免与调用方变量【同名】被劫持（课 6 陷阱）
  local -n _ra_nref_out=$1
  # ⚠️ 这里的局部变量【绝不能】叫 d 或任何可能与调用方传出参同名的名字。
  #    实测（tests/repro7_nameref.sh 场景 D/E）：
  #      local -n _ra_nref_out=$1      # _ra_nref_out 指向调用方的 d
  #      local d                       # 又声明一个叫 d 的局部量
  #    此时 _ra_nref_out 与 d 形成【循环引用】，bash 报警
  #      "circular name reference"
  #    后果：_ra_nref_out=$d 静默失效，调用方拿到的 d 仍是空值。
  #    这是课 6 nameref 撞名陷阱的第三种变体 —— 撞的不是 nameref 变量名，
  #    而是【函数内局部量】与【nameref 指向的名字】同名。
  #    统一加 _ra_tmp_ 前缀，从命名上根除这类碰撞。
  local _ra_tmp_dir
  # mktemp 是外部命令，会 fork —— 但它只在初始化时调用，不进循环，可接受
  _ra_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/release-audit.XXXXXX") \
    || ra_die "$EX_INTERNAL" '无法创建临时目录'
  _RA_CORE_TEMP_DIRS+=("$_ra_tmp_dir")
  _ra_nref_out=$_ra_tmp_dir
  return 0
}

ra_mktemp_file() {
  local -n _ra_nref_out=$1
  local _ra_tmp_file
  _ra_tmp_file=$(mktemp "${TMPDIR:-/tmp}/release-audit.XXXXXX") \
    || ra_die "$EX_INTERNAL" '无法创建临时文件'
  _RA_CORE_TEMP_FILES+=("$_ra_tmp_file")
  _ra_nref_out=$_ra_tmp_file
  return 0
}

ra_cleanup() {
  local rc=$?
  local p
  # 空数组在 set -u 下的展开：bash 4.4+ 已安全，这里仍显式判长度以兼容 4.3 及更早
  if ((${#_RA_CORE_TEMP_DIRS[@]} > 0)); then
    for p in "${_RA_CORE_TEMP_DIRS[@]}"; do
      [[ -d $p ]] && rm -rf -- "$p"
    done
  fi
  if ((${#_RA_CORE_TEMP_FILES[@]} > 0)); then
    for p in "${_RA_CORE_TEMP_FILES[@]}"; do
      [[ -f $p ]] && rm -f -- "$p"
    done
  fi
  return "$rc"
}
trap ra_cleanup EXIT

# ─────────────────────────────────────────────────────────────
# 8. 通用小工具
# ─────────────────────────────────────────────────────────────

# 安全读行：IFS= 保住首尾空格，-r 保住反斜杠，|| [ -n ] 保住没有尾换行的最后一行
# （课 13「read 的 -r / IFS= / 末行丢失 三元」）
ra_read_lines() {
  local line
  while IFS= read -r line || [[ -n $line ]]; do
    printf '%s\n' "$line"
  done
}

# 判断命令是否存在（不产生输出、不 fork 失败）
ra_has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# 文件名安全：校验入参不含路径穿越与危险字符
# 返回 0 = 安全，1 = 不安全
ra_is_safe_name() {
  local name=$1
  # 拒绝：空串、含 / 、等于 . 或 .. 、含 .. 组件、以 - 开头
  [[ -z $name ]] && return 1
  [[ $name == */* ]] && return 1
  [[ $name == . || $name == .. ]] && return 1
  [[ $name == -* ]] && return 1
  return 0
}
