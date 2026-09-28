#!/usr/bin/env bash
BASE="/mnt/d/projects/learning/bk-blueking-72"
cd "$BASE" || exit 1

echo "=== 1. 文档内残留 bk-lite / BK-Lite / Lite 引用（仅 md）==="
grep -rn --include='*.md' -iE 'bk-lite|bk_lite|bk\.lite|BlueKing Lite|Lite 轻量版' . 2>/dev/null \
  | sed 's/^/    /' | head -40
echo "    命中行数: $(grep -rn --include='*.md' -iE 'bk-lite|bk_lite|bk\.lite|BlueKing Lite|Lite 轻量版' . 2>/dev/null | wc -l)"

echo ""
echo "=== 2. 脚本内残留 bk-lite 路径（仅 sh/ps1）==="
grep -rln --include='*.sh' --include='*.ps1' -iE 'bk-lite' . 2>/dev/null \
  | sed 's/^/    /' | head -30
echo "    命中文件数: $(grep -rln --include='*.sh' --include='*.ps1' -iE 'bk-lite' . 2>/dev/null | wc -l)"

echo ""
echo "=== 3. 标题里的 Lite 用词（判断是否名不副实）==="
grep -rn --include='*.md' -E '^#.*Lite' . 2>/dev/null | sed 's/^/    /'
