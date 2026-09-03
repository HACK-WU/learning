#!/bin/bash
# 课 10 最终校验（UTF-8 输出）
export LANG=C.UTF-8 LC_ALL=C.UTF-8 PYTHONIOENCODING=utf-8
cd /mnt/d/projects/learning/victoriametrics/playground || exit 1

echo "===== 1. 课 10 交付自检 ====="
bash l10-check-delivery.sh 2>&1 | grep -E 'MISS|BAD|合计问题|断链数'

echo
echo "===== 2. 全局链接可达性 ====="
python3 l05-link-check.py 2>&1 | tail -4

echo
echo "===== 3. 双 agent 评审结论 ====="
bash l10-run-review.sh 2>&1 | grep -A4 '评审结论'

echo
echo "===== 4. 讲义关键内容 ====="
F='/mnt/d/projects/learning/victoriametrics/stages/4-怎么横向扩展/10-多租户与vmauth.md'
echo "  行数: $(wc -l < "$F")"
echo "  本机实测标注: $(grep -c '本机实测' "$F") 处"
echo "  实验数: $(grep -c '^### 实验' "$F")"
echo "  判据数: $(grep -c '\*\*判据\*\*' "$F")"
echo "  误区条数: $(awk '/## 🐞 常见误区/,/## 🚀/' "$F" | grep -c '^### ')"
echo "  课后题数: $(awk '/## 课后小测/,/## 🚀/' "$F" | grep -c '<summary>')"

echo
echo "===== 5. 四处档案 ====="
cd /mnt/d/projects/learning/victoriametrics
echo "  [1] 学习档案 课10三行:"
grep '^| 4 | 课 10' 00-学习档案.md | sed 's/^/      /'
echo "  [2] 评审清单:"
grep -c '课 10' 00-评审清单.md | sed 's/^/      课10 出现 /'
echo "  [3] 阶段4概览:"
grep -n 'status:\|课 10：多租户' 'stages/4-怎么横向扩展/README.md' | sed 's/^/      /'
echo "  [4] 目录+总览:"
grep -o '10-多租户与vmauth.md' 02-课程目录.md | head -1 | sed 's/^/      目录: /'
grep -o '12 课中已完成 10 课[^，]*，35 知识点中已完成 34 个' 01-学习路径总览.md | head -1 | sed 's/^/      总览: /'

echo
echo "===== 6. 课 10 残留检查 ====="
r=$(grep -rn '课 10' --include='*.md' . 2>/dev/null | grep -c '未开始\|⬜')
echo "  含『未开始/⬜』的课10行: $r"

echo
echo "===== 7. 线上复核（用 count_over_time 避开 5 分钟窗口）====="
for u in backend:backend-pass-123 frontend:frontend-pass-456; do
  printf "  %-10s " "${u%%:*}"
  curl -s --max-time 20 -u "$u" \
    --data-urlencode 'query=count_over_time(l10_vc_value[1h])' \
    'http://localhost:8427/api/v1/query' \
    | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0)' 2>/dev/null
done

echo
echo "===== 8. 结果一致性（连查 10 次）====="
printf "  "
for i in $(seq 1 10); do
  v=$(curl -s --max-time 20 -u backend:backend-pass-123 \
      --data-urlencode 'query=count_over_time(l10_vc_value[1h])' \
      'http://localhost:8427/api/v1/query' \
      | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0)' 2>/dev/null)
  printf "%s " "$v"
done
echo "  (预期: 5/10 交替 = 后端 dedup 不一致)"

echo
echo "===== 9. 容器状态 ====="
echo "  vm* 容器总数: $(docker ps --filter 'name=vm' --format '{{.Names}}' | wc -l)"
docker ps --filter 'name=vm' --format '{{.Names}}' | tr '\n' ' '
echo
