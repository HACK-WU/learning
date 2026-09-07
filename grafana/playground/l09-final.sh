#!/usr/bin/env bash
# 课 9 交付前全量复验
set -u
cd /mnt/d/projects/learning/grafana

echo "=== 1. 全仓死链检查（课 7/8 固化项）==="
python3 - <<'PY'
import os,re
root="/mnt/d/projects/learning/grafana"
bad=[];ok=0;files=0
for dp,dn,fn in os.walk(root):
    for f in fn:
        if not f.endswith(".md"): continue
        p=os.path.join(dp,f); files+=1
        txt=open(p,encoding="utf-8").read()
        for name,tgt in re.findall(r'\[([^\]]*)\]\(([^)]+)\)', txt):
            if tgt.startswith(("http://","https://","#","mailto:")): continue
            t=tgt.split("#")[0]
            if not t: continue
            full=os.path.normpath(os.path.join(dp,t))
            if os.path.exists(full): ok+=1
            else: bad.append((p.replace(root,""),name,tgt))
print(f"  扫描 {files} 个 md 文件：可解析 {ok} 条，死链 {len(bad)} 条")
for f,n,t in bad[:15]:
    print(f"    ❌ {f}  [{n}]({t})")
PY

echo ""
echo "=== 2. 课 9 正文结构（续行 / 围栏 / 六要素）==="
bash playground/l09-verify.sh 2>&1 | grep -E "续行|配对|9\.[123]|死链|章节|❌" | head -20

echo ""
echo "=== 3. 四处档案回写确认 ==="
echo -n "  档案 9.1 ✅: "; grep -c "| 9.1 | Loki 数据源与 LogQL 入门 | 课 9 | ✅ 已完成" 00-学习档案.md
echo -n "  档案 9.2 ✅: "; grep -c "| 9.2 | 从指标到日志：时间窗对齐与下钻链接 | 课 9 | ✅ 已完成" 00-学习档案.md
echo -n "  档案 9.3 ✅: "; grep -c "| 9.3 | 链路下钻：Jaeger 数据源与 exemplar | 课 9 | ✅ 已完成" 00-学习档案.md
echo -n "  进度 27/36 : "; grep -c "27 / 36" 00-学习档案.md
echo -n "  阶段3 9/9  : "; grep -c "阶段 3：9/9" 00-学习档案.md
echo -n "  overview 课9勾选: "; grep -c "\- \[x\] \`lessons/lesson-09" stages/3-叫得醒/overview.md
echo -n "  课程目录课9链接: "; grep -c "lesson-09-日志与链路" 02-课程目录.md
echo -n "  路径总览27/36  : "; grep -c "27 / 36" 01-学习路径总览.md

echo ""
echo "=== 4. 环境健康 ==="
echo -n "  Grafana(3001)   : "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 4 -u admin:admin http://localhost:3001/api/health
echo -n "  Loki(3101)      : "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 4 http://localhost:3101/ready
echo -n "  Jaeger(16687)   : "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 4 http://localhost:16687/api/services
echo -n "  Prom-ex(9202)   : "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 4 http://localhost:9202/-/ready
echo -n "  Prometheus(9201): "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 4 http://localhost:9201/-/ready

echo ""
echo "=== 5. 数据源清单 ==="
curl -s -u admin:admin http://localhost:3001/api/datasources 2>/dev/null \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);[print(f"    {x[\"name\"]:<12} {x[\"type\"]:<12} {x[\"uid\"]}") for x in d]' 2>/dev/null

echo ""
echo "=== 6. exemplar 闭环仍成立 ==="
curl -s "http://localhost:9202/api/v1/query_exemplars?query=h_test_bucket" 2>/dev/null \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);n=sum(len(g.get("exemplars",[])) for g in (d.get("data") or []));print(f"    exemplar 条数 = {n}")' 2>/dev/null
