#!/usr/bin/env bash
R=/mnt/d/projects/learning/consul
echo "===== 查找需回写的索引文件 ====="
for f in "02-课程目录.md" "01-学习路径总览.md" "00-评审清单.md" "00-学习档案.md"; do
  P=$(find "$R" -maxdepth 3 -name "$f" 2>/dev/null | head -1)
  [ -n "$P" ] && echo "  ✅ $f → $P" || echo "  ❌ $f 未找到"
done

echo
echo "===== 这些文件是否已提及运维专项 ====="
for f in "02-课程目录.md" "01-学习路径总览.md"; do
  P=$(find "$R" -maxdepth 3 -name "$f" 2>/dev/null | head -1)
  if [ -n "$P" ]; then
    N=$(grep -c '运维专项' "$P" 2>/dev/null || echo 0)
    echo "  $f: 提及运维专项 $N 次"
    grep -n '运维专项' "$P" 2>/dev/null | sed 's/^/    /' | head -5
  fi
done
