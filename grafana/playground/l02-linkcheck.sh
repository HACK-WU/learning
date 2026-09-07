#!/usr/bin/env bash
# 链接可达性检查（课 1 曾漏做，课 2 起强制执行）
# A 组：两个索引（02-课程目录.md / 01-学习路径总览.md）中的本地链接
# B 组：四个阶段 overview 的返回链接层级是否正确（应为 ../../02-课程目录.md）
# C 组：课 1、课 2 正文中的本地链接
set -u
BASE="/mnt/d/projects/learning/grafana"
FAIL=0

echo "=== A. 两个索引中的本地链接 ==="
for idx in "02-课程目录.md" "01-学习路径总览.md"; do
  grep -oE '\]\(([^)]+)\)' "${BASE}/${idx}" 2>/dev/null \
    | sed -E 's/^\]\((.*)\)$/\1/' | grep -vE '^(https?:|#|mailto:)' | sort -u | while read -r link; do
      # 去掉锚点
      p="${link%%#*}"
      if [ -f "${BASE}/${p}" ]; then echo "  ✅ [${idx}] ${p}"
      else echo "  ❌ [${idx}] ${p} 不存在"; fi
    done
done

echo
echo "=== B. 各阶段 overview 的返回链接层级 ==="
for ov in "${BASE}"/stages/*/overview.md; do
  rel="${ov#${BASE}/}"
  bad=$(grep -oE '\]\(\.\./[^)]*02-课程目录\.md\)' "$ov" | grep -v '^\](\.\./\.\./02-课程目录\.md)$' | head -3)
  if [ -n "$bad" ]; then
    echo "  ❌ ${rel} 层级错误: ${bad}"
    FAIL=$((FAIL+1))
  else
    echo "  ✅ ${rel} 返回链接层级正确"
  fi
done

echo
echo "=== C. 课 1 / 课 2 正文中的本地链接 ==="
for les in "${BASE}"/stages/*/lessons/lesson-0[12]-*.md; do
  rel="${les#${BASE}/}"
  dir=$(dirname "$les")
  grep -oE '\]\(([^)]+)\)' "$les" | sed -E 's/^\]\((.*)\)$/\1/' \
    | grep -vE '^(https?:|#|mailto:)' | sort -u | while read -r link; do
      p="${link%%#*}"
      case "$p" in
        /D:/*)
          # /D:/projects/learning/... -> /mnt/d/projects/learning/...
          # ⚠️ 2026-09-04 课 2 修正：此前先 ${p#/D:/} 再 ${rp#/} 是【双重剥离】，
          #    会把 /D:/projects/... 变成 projects/...，导致绝对路径全部误报不存在。
          target="/mnt/d${p#/D:}"
          ;;
        /*) target="$p" ;;
        *) target="${dir}/${p}" ;;
      esac
      # 规范化 ../
      target=$(cd "$(dirname "$target")" 2>/dev/null && echo "$(pwd)/$(basename "$target")")
      if [ -f "$target" ]; then echo "  ✅ [${rel}] ${p}"
      else echo "  ❌ [${rel}] ${p} -> ${target} 不存在"; fi
    done
done

echo
echo "RESULT: ${FAIL} 个层级错误（A/C 组的缺失项需人工确认，不自动计入）"
