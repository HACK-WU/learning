#!/usr/bin/env bash
BASE="/mnt/d/projects/learning/bk-blueking-72"
cd "$BASE" || exit 1
F="$BASE/00-学习档案.md"
echo "=== 1. 档案行数与新增节 ==="
echo "    总行数: $(wc -l < "$F")"
grep -nE '^#{2,4} E\.(8|9|10|11|12)|^## 九' "$F" | sed 's/^/    /'

echo ""
echo "=== 2. 新增的 E.11 / E.12 是否就位 ==="
grep -c 'E.11 八批验证收官' "$F" | sed 's/^/    E.11 出现次数: /'
grep -c 'E.12 经验沉淀' "$F" | sed 's/^/    E.12 出现次数: /'

echo ""
echo "=== 3. 档案内全部 md 链接可达性 ==="
python3 - "$BASE" <<'PY'
import re,os,sys
base=sys.argv[1]
txt=open(os.path.join(base,'00-学习档案.md'),encoding='utf-8').read()
links=re.findall(r'\]\(([^)]+\.md)\)',txt)
bad=0
for l in sorted(set(links)):
    t=l.split('#')[0]
    if not t: continue
    if os.path.isfile(os.path.join(base,t)): print("    OK   %s"%l)
    else: print("    断链 %s"%l); bad+=1
print("    链接 %d 条，断链 %d"%(len(set(links)),bad))
PY

echo ""
echo "=== 4. 档案内是否与集群实测矛盾（抽查硬数字）==="
printf "    deploy 实测在跑=%s 未起=%s（档案写 62/47）\n" \
  "$(kubectl get deploy -n blueking --no-headers 2>/dev/null | awk '$2!="0/0"' | wc -l)" \
  "$(kubectl get deploy -n blueking --no-headers 2>/dev/null | awk '$2=="0/0"' | wc -l)"
printf "    Pod 实测 Running=%s（档案写 95）\n" \
  "$(kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$3=="Running"' | wc -l)"
