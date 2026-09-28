#!/usr/bin/env bash
BASE="/mnt/d/projects/learning/bk-blueking-72"
cd "$BASE" || exit 1

echo "=== 替换 1：本机路径 bk-lite -> bk-blueking-72（md/sh/ps1）==="
# 只替换 工作区路径，不碰 /opt/bk-lite、registry 域名、GitHub 仓库
files=$(grep -rl --include='*.md' --include='*.sh' --include='*.ps1' \
        -E 'projects/learning/bk-blueking-72|projects\\learning\\bk-lite' . 2>/dev/null)
n=0
for f in $files; do
  sed -i 's#projects/learning/bk-blueking-72#projects/learning/bk-blueking-72#g; s#projects\\learning\\bk-lite#projects\\learning\\bk-blueking-72#g' "$f"
  n=$((n+1))
done
echo "    已改文件数: $n"

echo ""
echo "=== 替换 2：报告/索引标题里的 '蓝鲸 bk-lite' -> '蓝鲸 7.2 CE' ==="
for f in "21-分批验证总报告.md" "25-部署验收总报告-全8批合并.md" "README-验证报告索引.md"; do
  [ -f "$f" ] && sed -i 's/蓝鲸 bk-lite /蓝鲸 7.2 CE /g; s/蓝鲸 bk-lite/蓝鲸 7.2 CE/g' "$f" && echo "    已改: $f"
done

echo ""
echo "=== 替换 3：评审清单标题 ==="
[ -f "00-评审清单.md" ] && \
  sed -i '1s/# BK-Lite \/ 蓝鲸 7.2 部署实战 · 评审清单/# 蓝鲸 7.2 CE 部署实战 · 评审清单/' "00-评审清单.md" && \
  echo "    已改: 00-评审清单.md"

echo ""
echo "=== 替换 4：复审记录里的错误路径注释 ==="
[ -f "26-总报告独立复审记录.md" ] && \
  sed -i 's#D:/projects/learning/bk-blueking-72/#D:/projects/learning/bk-blueking-72/#g' "26-总报告独立复审记录.md" && \
  echo "    已改: 26-总报告独立复审记录.md"

echo ""
echo "=== 替换 5：/root/bk-lite-b 临时目录（这是本机临时工作目录，一并改名认知）==="
grep -rl --include='*.md' -E '/root/bk-lite-b' . 2>/dev/null | sed 's/^/    含引用: /'

echo ""
echo "=== 替换 6：脚本内 bk-lite 路径引用（sh/ps1）==="
sfiles=$(grep -rl --include='*.sh' --include='*.ps1' -E 'bk-lite' . 2>/dev/null)
m=0
for f in $sfiles; do
  sed -i 's#projects/learning/bk-blueking-72#projects/learning/bk-blueking-72#g; s#projects\\learning\\bk-lite#projects\\learning\\bk-blueking-72#g' "$f"
  m=$((m+1))
done
echo "    已处理脚本数: $m"

echo ""
echo "=== 残留检查（应只剩真实产品名）==="
grep -rn --include='*.md' -E 'projects/learning/bk-blueking-72' . 2>/dev/null | sed 's/^/    残留路径: /'
echo "    路径残留数: $(grep -rn --include='*.md' -E 'projects/learning/bk-blueking-72' . 2>/dev/null | wc -l)"
grep -rn --include='*.sh' --include='*.ps1' -E 'projects/learning/bk-blueking-72' . 2>/dev/null | sed 's/^/    残留脚本: /'
echo "    脚本残留数: $(grep -rn --include='*.sh' --include='*.ps1' -E 'projects/learning/bk-blueking-72' . 2>/dev/null | wc -l)"
