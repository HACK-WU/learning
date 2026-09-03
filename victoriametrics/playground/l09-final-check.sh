#!/bin/bash
# 课 9 最终校验
cd /mnt/d/projects/learning/victoriametrics/playground || exit 1
echo "===== 1. 课 9 交付自检（仅看问题项）====="
bash l09-check-delivery.sh 2>&1 | grep -E 'MISS|BAD|合计问题|断链数'
echo
echo "===== 2. 全局链接可达性 ====="
python3 l05-link-check.py 2>&1 | tail -6
echo
echo "===== 3. 双 agent 评审（结论行）====="
bash l09-run-review.sh 2>&1 | grep -A5 '评审结论'
echo
echo "===== 4. 四处档案落盘确认 ====="
cd /mnt/d/projects/learning/victoriametrics
echo "-- 1) 00-学习档案.md --"
grep '课 9' 00-学习档案.md | head -3
echo "-- 2) 00-评审清单.md --"
grep '课 9' 00-评审清单.md | head -2
echo "-- 3) 阶段 4 概览 --"
grep -n '课 9' 'stages/4-怎么横向扩展/README.md' | head -4
echo "-- 4a) 课程目录 --"
grep -n '9-复制去重与高可用' 02-课程目录.md
echo "-- 4b) 学习路径总览 --"
grep -n '已完成 9 课\|31 个' 01-学习路径总览.md
echo
echo "===== 5. 本课最关键的三个数字复核 ====="
q() {
  curl -s --max-time 60 --data-urlencode "query=$1" \
    "http://localhost:$2/select/0/prometheus/api/v1/query" \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0)' 2>/dev/null
}
echo "  dedup 生效对比（l09_clean 应为 400 vs 200）:"
for m in $(curl -s --max-time 20 'http://localhost:8481/select/0/prometheus/api/v1/label/__name__/values' | python3 -c 'import json,sys
v=json.load(sys.stdin).get("data",[])
print(" ".join([x for x in v if x.startswith("l09_clean")]))' 2>/dev/null); do
  echo "    $m: 无dedup=$(q "count_over_time($m[2h])" 8481)  有dedup=$(q "count_over_time($m[2h])" 8487)"
done
echo
echo "  副本失败日志累计: $(docker logs vminsert-learn 2>&1 | grep -c 'cannot make a copy') 次"
