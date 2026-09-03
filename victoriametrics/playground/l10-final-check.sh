#!/bin/bash
# 课 10 最终校验
cd /mnt/d/projects/learning/victoriametrics/playground || exit 1
echo "===== 1. 课 10 交付自检（仅看问题项）====="
bash l10-check-delivery.sh 2>&1 | grep -E 'MISS|BAD|合计问题|断链数'
echo
echo "===== 2. 全局链接可达性 ====="
python3 l05-link-check.py 2>&1 | tail -6
echo
echo "===== 3. 双 agent 评审（结论行）====="
bash l10-run-review.sh 2>&1 | grep -A5 '评审结论'
echo
echo "===== 4. 四处档案落盘确认 ====="
cd /mnt/d/projects/learning/victoriametrics
echo "-- 1) 00-学习档案.md（课 10 三行）--"
grep '^| 4 | 课 10' 00-学习档案.md
echo "-- 2) 00-评审清单.md --"
grep '课 10' 00-评审清单.md | head -2 | cut -c1-120
echo "-- 3) 阶段 4 概览 --"
grep -n 'status:\|课 10：多租户\|### 课 10 已验证' 'stages/4-怎么横向扩展/README.md'
echo "-- 4a) 课程目录 --"
grep -n '10-多租户与vmauth' 02-课程目录.md
echo "-- 4b) 学习路径总览 --"
grep -n '已完成 10 课\|34 个' 01-学习路径总览.md
echo
echo "===== 5. 阶段 5 目录（课 11 用）====="
ls -la 'stages/5-生产落地/' 2>&1 | head -4
echo
echo "===== 6. 线上实测复核（用 count_over_time，避开 5 分钟窗口陷阱）====="
for u in backend:backend-pass-123 frontend:frontend-pass-456 viewer:viewer-pass-000; do
  printf "  %-10s count_over_time(l10_vc_value[1h]): " "${u%%:*}"
  curl -s --max-time 20 -u "$u" \
    --data-urlencode 'query=count_over_time(l10_vc_value[1h])' \
    'http://localhost:8427/api/v1/query' \
    | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
    print(int(sum(float(x["value"][1]) for x in r)) if r else 0)
except Exception: print("N/A")' 2>&1
done
echo
echo "  租户绑定验证（instant query，数据在窗口内）:"
for u in backend:backend-pass-123 frontend:frontend-pass-456; do
  printf "    %-10s " "${u%%:*}"
  curl -s --max-time 20 -u "$u" --data-urlencode 'query=l10_vc_value' \
    'http://localhost:8427/api/v1/query' \
    | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
    print(sorted(set(x["value"][1] for x in r)) if r else "空")
except Exception: print("N/A")' 2>&1
done
echo
echo "===== 7. 容器总体状态 ====="
docker ps --format 'table {{.Names}}\t{{.Status}}' --filter 'name=vm' 2>&1 | head -25
echo "  总计: $(docker ps --filter 'name=vm' --format '{{.Names}}' | wc -l) 个 vm* 容器"
