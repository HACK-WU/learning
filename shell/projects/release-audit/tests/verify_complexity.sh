#!/usr/bin/env bash
# 复杂度门槛核查：循环内 fork
#
# 判据（课 13）：循环体内不得出现【外部命令】调用。
#   外部命令 = 每次迭代 fork 一个进程；N 个文件 → N 次 fork。
#   内建命令（printf/read/local/参数展开…）与本项目自定义函数不 fork。
#
# 判定方法：
#   1) 收集本项目定义的全部函数名（ra_*、_ra_*、main 等），视为"内部命令"
#   2) 收集 bash 内建命令清单（compgen -b），视为"不 fork"
#   3) 循环体内出现的其余命令 = 疑似的外部命令
set -uo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." || exit 1

pass=0
fail=0

# 1) 本项目自定义函数（这些是 shell 函数调用，不 fork）
PROJECT_FUNCS=$(grep -hoE '^[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(\)' \
  release-audit lib/*.sh 2>/dev/null \
  | sed 's/[[:space:]]*()$//' | sort -u | paste -sd'|' -)

# 2) bash 内建命令（compgen -b 是内建，本身不 fork）
BASH_BUILTINS=$(compgen -b 2>/dev/null | sort -u | paste -sd'|' -)

# 3) 额外关键字/语法符号
KEYWORDS='if|then|else|elif|fi|case|esac|while|until|for|do|done|select|function|return|break|continue|time|coproc|local|declare|typeset|readonly|export|unset|shift|let|eval|source|\.|\[\[|\]\]|\(\(|\)\)|-n'

scan_file() {
  local f=$1
  local out
  out=$(awk -v pf="$PROJECT_FUNCS" -v bb="$BASH_BUILTINS" -v kw="$KEYWORDS" '
    BEGIN {
      n=split(pf, a, "|"); for (i=1;i<=n;i++) if (a[i]!="") isproj[a[i]]=1
      n=split(bb, b, "|"); for (i=1;i<=n;i++) if (b[i]!="") isblt[b[i]]=1
      n=split(kw, c, "|"); for (i=1;i<=n;i++) if (c[i]!="") iskw[c[i]]=1
    }

    /^[[:space:]]*(while|for|until)[[:space:]]/ { inloop++; next }
    /^[[:space:]]*done[[:space:]]*$/            { if (inloop>0) inloop--; next }

    inloop > 0 {
      line=$0
      sub(/[[:space:]]*#.*$/, "", line)
      gsub(/^[[:space:]]+/, "", line)
      gsub(/[[:space:]]+$/, "", line)
      if (line == "") next
    }

    # 纯语法结构
    inloop > 0 && line ~ /^(then|do|else|elif|fi|esac|;;|\{|\})$/ { next }
    inloop > 0 && line ~ /^(if|case|while|for|until|select)[[:space:]]/ { next }
    inloop > 0 && line ~ /^\|\|/ { next }
    inloop > 0 && line ~ /^&&/ { next }
    inloop > 0 && line ~ /^\(/ { next }
    inloop > 0 && line ~ /^\)/ { next }
    inloop > 0 && line ~ /^\*/ { next }          # case 的 *) 分支
    inloop > 0 && line ~ /^[0-9|)]/ { next }     # case 的数字分支
    inloop > 0 && line ~ /^[A-Za-z0-9_.|*?[:space:]-]+\)$/ { next }  # case 分支标签
    inloop > 0 && line ~ /^--?[A-Za-z0-9?*|.-]*=.*\)$/ { next }      # --opt=*) 分支
    # 赋值语句（含数组下标赋值 seen["k"]=1、RA_SKIP["$s"]=1）
    inloop > 0 && line ~ /^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?[-+.]?=/ { next }
    inloop > 0 && line ~ /^(local|declare|typeset|readonly|export)[[:space:]]/ { next }
    inloop > 0 && line ~ /^-n[[:space:]]/ { next }
    inloop > 0 && line ~ /^:/ { next }
    inloop > 0 && line ~ /^[A-Za-z_][A-Za-z0-9_]*\+{2}/ { next }
    # 函数定义行 xxx() {
    inloop > 0 && line ~ /^[A-Za-z_][A-Za-z0-9_]*\(\)[[:space:]]*\{?/ { next }
    inloop > 0 && line ~ /^END[[:space:]]/ { next }          # awk 的 END 块
    inloop > 0 && line ~ /^\{[[:space:]]*[A-Za-z_]/ { next }  # awk 语句块

    inloop > 0 {
      split(line, a, /[[:space:]]/)
      cmd=a[1]
      if (cmd == "") next
      if (cmd ~ /^[$"'"'"']/) next
      if (cmd ~ /^[A-Za-z_][A-Za-z0-9_]*=/) next
      if (cmd in isproj)  next
      if (cmd in isblt)   next
      if (cmd in iskw)    next
      printf "  L%-4d  %s\n", NR, line
    }
  ' "$f")

  if [[ -z $out ]]; then
    printf '  ✓ %-22s 循环内无外部命令\n' "$f"
    pass=$((pass + 1))
  else
    printf '  ✗ %-22s 循环内发现外部命令：\n' "$f"
    printf '%s\n' "$out"
    fail=$((fail + 1))
  fi
}

echo '################ 门槛核查：循环内 fork ################'
echo "本项目函数数: $(printf '%s' "$PROJECT_FUNCS" | tr '|' '\n' | grep -c . )"
echo "bash 内建数:  $(printf '%s' "$BASH_BUILTINS" | tr '|' '\n' | grep -c . )"
echo
for f in release-audit lib/core.sh lib/report.sh lib/checks.sh; do
  scan_file "$f"
done

echo
echo '################ 运行时验证：进程数是否随文件数增长 ################'
echo
printf '  %-8s %-14s %s\n' '文件数' '外部命令调用' '结论'
for n in 10 100 400; do
  d="/tmp/ra_forkv_$n"
  rm -rf -- "$d"
  mkdir -p -- "$d"
  i=0
  while (( i < n )); do
    printf 'c%s\n' "$i" >"$d/f$i.txt"
    (( i += 1 )) || true
  done
  cnt=$(bash -x ./release-audit -q --skip required --skip perm --skip secret \
        --skip version --skip checksum "$d" 2>&1 >/dev/null \
        | grep -cE '^\+* (grep|sed|awk|stat|basename|expr|cut|tr|wc|find|mktemp|rm|cat)' || true)
  printf '  %-8s %-14s %s\n' "$n" "$cnt" \
    "$([[ $cnt -le 8 ]] && echo '常量级 ✓' || echo '随 N 增长 ✗')"
done

echo
printf '  通过: %s   失败: %s\n' "$pass" "$fail"
exit $(( fail > 0 ? 1 : 0 ))
