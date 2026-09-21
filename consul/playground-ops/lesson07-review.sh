#!/usr/bin/env bash
R=/mnt/d/projects/learning/consul
B="$R/子教程/运维专项/lessons"
L7="$B/lesson-07-版本升级与迁移.md"
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501

echo "===== 1. 讲义引用的实测数字复测 ====="
echo "  --- gossip protocol ---"
echo "  实测: $(consul version | grep -o 'understands [0-9]* to [0-9]*')  (讲义: understands 2 to 3)"
echo "  --- raft protocol ---"
echo "  实测: $(consul operator raft list-peers 2>/dev/null | awk 'NR==2{print $6}')  (讲义: 3)"
echo "  --- 版本 ---"
echo "  实测: $(consul version | head -1)  (讲义: v2.0.2)"

echo
echo "===== 2. quorum 停机上限计算（讲义表）====="
python3 -c "
for n in [3,5,7]:
    q=n//2+1
    print(f'  {n} 节点: quorum={q}, 可停 {n-q} 台')
"

echo
echo "===== 3. 链接可达性（课7 全部 md 链接）====="
BAD=0; TOT=0
while IFS= read -r link; do
  TOT=$((TOT+1))
  link="${link#./}"
  tgt="$R/${link%%#*}"
  [ -f "$tgt" ] || { echo "  ❌ → $link"; BAD=$((BAD+1)); }
done < <(grep -oE '\]\(([^)]+\.md)\)' "$L7" | sed 's/](\(.*\))/\1/')
echo "  共 $TOT 条，断链 $BAD 条"

echo
echo "===== 4. 讲义结构自检 ====="
echo "  行数: $(wc -l < "$L7")"
echo "  核心结论条数: $(sed -n '/## 六、本课核心结论/,/^## /p' "$L7" | grep -c '^[0-9]\.')"
echo "  小测题数: $(sed -n '/### 小测/,/<details>/p' "$L7" | grep -c '^[0-9]\.')"
echo "  实测边界标注: $(grep -c '实测边界' "$L7")"
echo "  官方文档引用: $(grep -c 'docs.hashicorp.com\|consul.io/docs' "$L7")"
