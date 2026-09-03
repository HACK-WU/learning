#!/bin/bash
# 核查 08 每条故障模式的五段式完整性（症状/根因/排查路径/修复/预防）
F=/mnt/d/projects/learning/surrealdb/08-实战经验.md
cd /mnt/d/projects/learning/surrealdb || exit 1

awk '
/^### 故障模式/ {
  if (cur != "") {
    printf "%-40s 症状=%d 根因=%d 排查=%d 修复=%d 预防=%d 回指=%d\n", cur, a,b,c,d,e,f
  }
  cur=$0; a=b=c=d=e=f=0
}
/^\*\*症状（可观测）\*\*/ {a=1}
/^\*\*根因\*\*/ {b=1}
/^\*\*排查路径\*\*/ {c=1}
/^\*\*修复\*\*/ {d=1}
/^\*\*预防/ {e=1}
/对应速查条目/ {f=1}
END { if (cur != "") printf "%-40s 症状=%d 根因=%d 排查=%d 修复=%d 预防=%d 回指=%d\n", cur, a,b,c,d,e,f }
' "$F"

echo ""
echo "===== 09 每条症状的硬特征 ====="
awk '
/^## .*症状 [0-9]*：/ {
  if (cur != "") printf "%-46s 一眼识别=%d 止血=%d 若无效=%d 预防=%d 原理=%d\n", cur, a,b,c,d,e
  cur=$0; a=b=c=d=e=0
}
/^\*\*一眼识别\*\*/ {a=1}
/^\| \*\*止血\*\*/ {b=1}
/^\| 若无效/ {c=1}
/^> \*\*预防\*\*：/ {d=1}
/^> \*\*原理\*\*：/ {e=1}
END { if (cur != "") printf "%-46s 一眼识别=%d 止血=%d 若无效=%d 预防=%d 原理=%d\n", cur, a,b,c,d,e }
' 09-排障速查手册.md
