# lib/checks.sh —— 具体审计检查项
#
# 覆盖知识点：
#   阶段 1 ·参数展开 ${var#pattern}、退出码分级
#   阶段 2 ·关联数组（清单表）、case 匹配、local 作用域
#   阶段 3 ·无循环内 fork：find -print0 + while read 批量遍历；awk 单次扫描替代 N 次 grep
#            trap 与临时文件生命周期
#            并发：多线程 checksum（阶段 3「作业控制与并发」）
#   阶段 4 ·注入防护（-- 与引号、路径穿越校验）、选型说明

# shellcheck shell=bash

# 并发度：0 = 自动（= CPU 核数）
RA_JOBS=${RA_JOBS:-0}

ra_cpu_count() {
  local n
  # nproc 不是 POSIX，但本机（WSL/Ubuntu）肯定有；取不到就回落 4
  if ra_has_cmd nproc; then
    n=$(nproc 2>/dev/null) || n=4
  else
    n=4
  fi
  [[ $n =~ ^[0-9]+$ ]] && (( n > 0 )) || n=4
  printf '%s\n' "$n"
}

# ─────────────────────────────────────────────────────────────
# 检查 1：必需文件存在性
# ─────────────────────────────────────────────────────────────
# 清单来自 --manifest 文件，每行一个相对路径。
# 用关联数组做"是否已找到"的标记表（阶段 2 知识点）。
ra_check_required_files() {
  local root=$1
  local manifest_file=$2
  local -A seen=()
  local -a required=()
  local line relpath

  if [[ ! -f $manifest_file ]]; then
    ra_add_finding 'REQUIRED' "$SEV_SKIP" "$manifest_file" '未提供清单文件，跳过必需文件检查'
    return 0
  fi

  # 用 mapfile 一次性读入，避免 while-read 子 shell 丢变量
  # mapfile 是 bash 内建，零 fork；但 mapfile 纯读入【不过滤】，
  # 注释与空行要自己处理（课 5 实测过的坑）
  local -a raw_lines=()
  mapfile -t raw_lines <"$manifest_file"

  for line in "${raw_lines[@]}"; do
    # 去掉行尾 \r（Windows 编辑的清单文件在 Linux 下会带 \r）
    line=${line%$'\r'}
    [[ -z $line ]] && continue
    [[ $line == \#* ]] && continue
    # 跳过 key=value 形式的【元数据行】（如 version=2.1.0）。
    # 初版没做这一步，结果 `version=2.1.0` 被当成一个叫 "version=2.1.0" 的
    # 必需文件，clean 样例因此误报 BLOCK —— 清单格式里注释与元数据
    # 是两种不同语法，必须分别处理（e2e 实测抓出）。
    [[ $line == *=* ]] && continue
    required+=("$line")
  done

  if ((${#required[@]} == 0)); then
    ra_add_finding 'REQUIRED' "$SEV_WARN" "$manifest_file" '清单文件为空'
    return 0
  fi

  for relpath in "${required[@]}"; do
    local full="$root/$relpath"
    if [[ -e $full ]]; then
      if [[ -L $full ]]; then
        # 符号链接：存在但可能指向外面，这是发布包的高风险项
        local link_target
        link_target=$(readlink -- "$full" 2>/dev/null) || link_target='(unreadable)'
        ra_add_finding 'REQUIRED' "$SEV_WARN" "$relpath" "是符号链接，指向 $link_target"
        seen["$relpath"]=1
      elif [[ -f $full ]]; then
        seen["$relpath"]=1
        ra_debug "必需文件存在: $relpath"
      else
        ra_add_finding 'REQUIRED' "$SEV_WARN" "$relpath" '存在但不是常规文件（可能是目录）'
        seen["$relpath"]=1
      fi
    else
      ra_add_finding 'REQUIRED' "$SEV_BLOCK" "$relpath" '必需文件缺失'
      seen["$relpath"]=0
    fi
  done
  return 0
}

# ─────────────────────────────────────────────────────────────
# 检查 2：文件权限
# ─────────────────────────────────────────────────────────────
# 关注两点：
#   1) 可执行文件是否真的可执行（脚本没有 +x 会导致部署后 126/127）
#   2) 私钥、配置文件是否过于开放（world-readable 的私钥 = 事故）
#
# 实现要点：find -print0 + while IFS= read -r -d ''
#   -print0 用 NUL 分隔，文件名含空格/换行也不会被切开（课 10 实测：NUL=9 换行=10 for=16）
#   整个遍历只有一个 find 进程，没有循环内 fork
ra_check_permissions() {
  local root=$1

  local f mode
  # -d '' 配合 -print0：read 按 NUL 切分
  while IFS= read -r -d '' f; do
    # stat -c 取权限位；这里在循环内【确实】有 fork，见下方说明
    mode=$(stat -c '%a' -- "$f" 2>/dev/null) || continue

    local rel="${f#"$root"/}"
    local last3="${mode: -3}"
    local other_bit="${last3:2:1}"

    # world-writable 是阻断级：任何人都能改发布产物
    if [[ $last3 == *7 || $last3 == *6 || $last3 == *3 || $last3 == *2 ]]; then
      : # world 位有写权限会在下面单独判断
    fi
    case "$other_bit" in
      2|3|6|7)
        ra_add_finding 'PERM' "$SEV_BLOCK" "$rel" "world-writable，权限 $mode"
        ;;
    esac

    # 私钥类文件：扩展名命中且 group/other 可读 → WARN
    case "$rel" in
      *.key|*.pem|*.p12|*.pfx|*id_rsa*|*.keystore)
        local g_bit="${last3:1:1}" o_bit="${last3:2:1}"
        if (( g_bit > 0 || o_bit > 0 )); then
          ra_add_finding 'PERM' "$SEV_WARN" "$rel" "私钥文件权限过宽 $mode（建议 600）"
        fi
        ;;
    esac

    # .sh 脚本缺少可执行位（owner 位非奇数 = 无 x）
    if [[ $rel == *.sh ]]; then
      local u_bit="${last3:0:1}"
      case "$u_bit" in
        0|2|4|6)
          ra_add_finding 'PERM' "$SEV_WARN" "$rel" "shell 脚本缺少可执行位，权限 $mode"
          ;;
      esac
    fi
  done < <(find "$root" -type f -print0 2>/dev/null)

  return 0
}

# ─────────────────────────────────────────────────────────────
# 检查 3：敏感信息扫描（正则）
# ─────────────────────────────────────────────────────────────
# ⚠️ 选型决策（记录于 DECISIONS.md · D1）：
#   为什么用 bash 正则（[[ =~ ]]）而不是 N 次 grep？
#     N 次 grep = 每个文件每个模式 fork 一次，files×patterns 进程数。
#     bash 内建 =~ 零 fork；只有极少数超长词法场景才需要 grep。
#   为什么不用 Python？
#     本机有 Python，但引入解释器依赖会让这个"零依赖运维工具"变成"需要环境的工具"。
#     这里模式数量少、逻辑是逐行匹配，shell 完全胜任；
#     若将来要做嵌套 JSON/YAML 解析，那才是迁 Python 的触发条件（课 13 判据）。
ra_check_secrets() {
  local root=$1
  local f

  # 模式表：用数组而不是关联数组，保证匹配顺序稳定
  local -a patterns=(
    'BEGIN (RSA|DSA|EC|OPENSSH|PRIVATE) PRIVATE KEY'
    'AKIA[0-9A-Z]{16}'
    '(password|passwd|pwd|secret|token|api[_-]?key)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9/+=._-]{8,}'
  )
  local -a names=('private-key' 'aws-access-key' 'credential-assignment')

  while IFS= read -r -d '' f; do
    # 跳过二进制文件：用 file 判断会 fork，改用更省的判据 —— 扩展名黑名单
    case "$f" in
      *.png|*.jpg|*.jpeg|*.gif|*.zip|*.gz|*.tar|*.jar|*.war|*.so|*.exe|*.pdf) continue ;;
    esac

    local rel="${f#"$root"/}"
    local i=0
    local pat
    for pat in "${patterns[@]}"; do
      # grep -m1 提前退出：命中即停，不必扫完整文件
      # 这里仍在循环内 fork（files × patterns），是本项目唯一保留的 fork 点，见 DECISIONS.md D2
      if grep -qIEm1 -- "$pat" -- "$f" 2>/dev/null; then
        ra_add_finding 'SECRET' "$SEV_BLOCK" "$rel" "疑似硬编码凭证（模式 ${names[i]}）"
      fi
      (( i += 1 )) || true
    done
  done < <(find "$root" -type f -print0 2>/dev/null)

  return 0
}

# ─────────────────────────────────────────────────────────────
# 检查 4：版本号一致性
# ─────────────────────────────────────────────────────────────
# 期望：目录名中的版本 与 VERSION 文件内容 与 清单文件里的版本 三者一致。
# 三者不一致是"发布错版本"的经典原因。
ra_check_version_consistency() {
  local root=$1
  local manifest_file=$2

  # 来源 A：目录名
  local dirbase
  dirbase=$(basename -- "$root")
  local ver_from_dir=''
  if [[ $dirbase =~ v?([0-9]+\.[0-9]+\.[0-9]+) ]]; then
    ver_from_dir=${BASH_REMATCH[1]}
  fi

  # 来源 B：VERSION 文件
  local ver_from_file=''
  local vf="$root/VERSION"
  if [[ -f $vf ]]; then
    # 读第一行并去掉首尾空白：参数展开 + while read，零外部命令
    local line=''
    IFS= read -r line <"$vf" || true
    line=${line%$'\r'}
    if [[ $line =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
      ver_from_file=${BASH_REMATCH[1]}
    else
      ra_add_finding 'VERSION' "$SEV_WARN" 'VERSION' "内容不像版本号：'${line}'"
    fi
  else
    ra_add_finding 'VERSION' "$SEV_SKIP" 'VERSION' '无 VERSION 文件，跳过版本一致性检查'
    return 0
  fi

  # 来源 C：清单里的版本（manifest 中形如 version=1.2.3 的行）
  local ver_from_manifest=''
  if [[ -f $manifest_file ]]; then
    local mline
    while IFS= read -r mline || [[ -n $mline ]]; do
      mline=${mline%$'\r'}
      if [[ $mline =~ ^version[[:space:]]*=[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        ver_from_manifest=${BASH_REMATCH[1]}
        break
      fi
    done <"$manifest_file"
  fi

  # 三方比对
  if [[ -n $ver_from_dir && -n $ver_from_file && $ver_from_dir != "$ver_from_file" ]]; then
    ra_add_finding 'VERSION' "$SEV_BLOCK" 'VERSION' \
      "目录名版本 $ver_from_dir 与 VERSION 文件 $ver_from_file 不一致"
  fi
  if [[ -n $ver_from_manifest && -n $ver_from_file && $ver_from_manifest != "$ver_from_file" ]]; then
    ra_add_finding 'VERSION' "$SEV_BLOCK" 'manifest' \
      "清单版本 $ver_from_manifest 与 VERSION 文件 $ver_from_file 不一致"
  fi
  if [[ -n $ver_from_file ]]; then
    ra_add_finding 'VERSION' "$SEV_INFO" 'VERSION' "声明版本 $ver_from_file"
  fi
  return 0
}

# ─────────────────────────────────────────────────────────────
# 检查 5：checksum 校验（并发）
# ─────────────────────────────────────────────────────────────
# 校验 SHA256SUMS 里的每个条目。
#
# 阶段 3「作业控制与并发」知识点：
#   checksum 是 CPU 密集且彼此独立 → 适合并发。
#   用后台任务 + wait 收集退出码；用临时文件收集子任务输出
#   （子 shell 的变量改不了父 shell 的数组，这是阶段 3 的核心坑）。
#
# ⚠️ 注意（课 9 实测）：set -e 对裸 wait【生效】，对 `if wait`【失效】。
#   这里需要拿到每个任务的退出码逐个判断，所以用 `wait $pid; rc=$?` 形式，
#   但 `wait $pid` 在 set -e 下失败会直接终止脚本 —— 故用 `|| rc=$?` 兜住。
ra_one_sum() {
  local expected=$1
  local file=$2
  local actual
  actual=$(sha256sum -- "$file" 2>/dev/null | awk '{print $1}') || actual=''
  if [[ -z $actual ]]; then
    return 3
  fi
  if [[ $actual == "$expected" ]]; then
    return 0
  fi
  return 1
}

ra_check_checksums() {
  local root=$1
  local sums_file="$root/SHA256SUMS"

  if [[ ! -f $sums_file ]]; then
    ra_add_finding 'CHECKSUM' "$SEV_SKIP" 'SHA256SUMS' '无 SHA256SUMS 文件，跳过校验'
    return 0
  fi

  local jobs=$RA_JOBS
  (( jobs > 0 )) || jobs=$(ra_cpu_count)

  # 收集任务：先读到数组，再分批并发
  local -a expecteds=() relpaths=()
  local line
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    [[ -z $line ]] && continue
    [[ $line == \#* ]] && continue
    # 格式：<64位hex><空格><*| ><路径>；路径可能含空格，故只切第一段
    local exp="${line:0:64}"
    local path="${line:66}"
    # 去掉可能的 binary 标记 '*'
    path=${path#\*}
    [[ -n $exp && -n $path ]] || continue
    expecteds+=("$exp")
    relpaths+=("$path")
  done <"$sums_file"

  if ((${#expecteds[@]} == 0)); then
    ra_add_finding 'CHECKSUM' "$SEV_WARN" 'SHA256SUMS' 'SHA256SUMS 为空'
    return 0
  fi

  local outdir
  # nameref 出参（不是 d=$(...)）：若用命令替换，函数会在子 shell 里执行，
  # 登记动作被吞，EXIT trap 就清理不到这个目录 → 临时目录泄漏
  ra_mktemp_dir outdir

  local i idx
  local -a pids=()
  local running=0
  for (( i = 0; i < ${#expecteds[@]}; i++ )); do
    local rel="${relpaths[i]}"
    local exp="${expecteds[i]}"
    local full="$root/$rel"

    if [[ ! -f $full ]]; then
      ra_add_finding 'CHECKSUM' "$SEV_BLOCK" "$rel" '清单中记录的文件不存在'
      continue
    fi

    # 每个任务把结果写进自己的临时文件（子 shell 无法回写父 shell 变量）
    local outfile="$outdir/$i.result"
    (
      local rc=0
      ra_one_sum "$exp" "$full" || rc=$?
      printf '%s\n' "$rc" >"$outfile"
    ) &
    pids+=($!)
    (( running += 1 )) || true

    # 达到并发上限就等一批
    if (( running >= jobs )); then
      local p
      for p in "${pids[@]}"; do
        wait "$p" || true
      done
      pids=()
      running=0
    fi
  done

  # 等剩余任务
  local p
  for p in "${pids[@]}"; do
    wait "$p" || true
  done

  # 读取结果并生成 finding
  for (( i = 0; i < ${#expecteds[@]}; i++ )); do
    local outfile="$outdir/$i.result"
    [[ -f $outfile ]] || continue
    local rc
    rc=$(cat -- "$outfile")
    local rel="${relpaths[i]}"
    case "$rc" in
      0) ra_debug "checksum OK: $rel" ;;
      1) ra_add_finding 'CHECKSUM' "$SEV_BLOCK" "$rel" 'SHA256 校验不匹配（产物被篡改或传输损坏）' ;;
      3) ra_add_finding 'CHECKSUM' "$SEV_WARN"  "$rel" '无法计算 checksum（读取失败）' ;;
      *) ra_add_finding 'CHECKSUM' "$SEV_WARN"  "$rel" "checksum 任务异常退出 rc=$rc" ;;
    esac
  done

  return 0
}

# ─────────────────────────────────────────────────────────────
# 检查 6：结构体规模统计（awk 单次扫描）
# ─────────────────────────────────────────────────────────────
# 演示"用一次 awk 扫描替代 N 次外部命令"：
#   N 个文件各自 stat + 累加 = 2N 次 fork
#   一次 find -printf + 一次 awk = 2 个进程
ra_check_structure() {
  local root=$1

  # find -printf 直接输出 size 与 type，awk 汇总 —— 全程 2 个进程
  local stats
  stats=$(find "$root" -type f -printf '%s\n' 2>/dev/null \
    | awk '
      { n++; s += $1; if ($1 > max) max = $1 }
      END { printf "%d %d %d", n+0, s+0, max+0 }
    ') || stats=''

  local count total biggest
  read -r count total biggest <<<"$stats"
  count=${count:-0}
  total=${total:-0}
  biggest=${biggest:-0}

  ra_add_finding 'STRUCT' "$SEV_INFO" "$root" "文件数 $count，总字节 $total，最大单文件 $biggest 字节"

  if (( count == 0 )); then
    ra_add_finding 'STRUCT' "$SEV_BLOCK" "$root" '发布目录里没有任何文件'
  fi

  # 异常大文件（>100MB）提示
  if (( biggest > 104857600 )); then
    ra_add_finding 'STRUCT' "$SEV_WARN" "$root" "存在超过 100MB 的单文件（$biggest 字节）"
  fi

  return 0
}
