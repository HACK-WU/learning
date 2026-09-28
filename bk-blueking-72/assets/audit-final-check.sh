#!/usr/bin/env bash
BASE="/mnt/d/projects/learning/bk-blueking-72"
cd "$BASE" || exit 1

echo "=== 1. 目录名与旧名残留 ==="
[ -d "/mnt/d/projects/learning/bk-blueking-72" ] && echo "    新目录存在 ✅"
[ -d "/mnt/d/projects/learning/bk-lite" ] && echo "    旧目录仍存在 ❌" || echo "    旧目录已不存在 ✅"
SELF=$(basename "$0")
echo "    文档路径残留: $(grep -rn --include='*.md' --include='*.sh' --include='*.ps1' -E 'projects/learning/bk-lite' . 2>/dev/null | grep -v "$SELF" | grep -v '27-改名与物料核查说明' | wc -l)  (应为 0)"

echo ""
echo "=== 2. 全部 md 的内部链接可达性 ==="
python3 - "$BASE" <<'PY'
import re,os,sys
base=sys.argv[1]
files=[f for f in os.listdir(base) if f.endswith('.md')]
files += [os.path.join('stages',r,f) for r,d,fs in os.walk(os.path.join(base,'stages')) for f in fs if f.endswith('.md')]
total=bad=0
badlist=[]
for f in files:
    p=os.path.join(base,f)
    if not os.path.isfile(p): continue
    txt=open(p,encoding='utf-8').read()
    for l in re.findall(r'\]\(([^)]+)\)',txt):
        if l.startswith(('http','#','mailto')): continue
        t=l.split('#')[0]
        if not t: continue
        tp=os.path.normpath(os.path.join(os.path.dirname(p),t))
        total+=1
        if not os.path.exists(tp):
            bad+=1; badlist.append("%s -> %s"%(f,l))
print("    检查链接 %d 条，断链 %d"%(total,bad))
for b in badlist[:20]: print("      断链: "+b)
PY

echo ""
echo "=== 3. 新增/改名物料是否就位 ==="
for f in README.md 27-改名与物料核查说明.md 00-学习档案.md 25-部署验收总报告-全8批合并.md; do
  [ -f "$f" ] && printf "    OK   %-45s %s 行\n" "$f" "$(wc -l < "$f")" || printf "    缺失 %s\n" "$f"
done

echo ""
echo "=== 4. 过时标注覆盖检查 ==="
for f in 08-实战经验.md 10-访问指南.md 11-组件部署清单.md 11-组件镜像与源码对照.md 12-WSL内存调优与集群稳定性.md 14-后台任务裁剪方案.md 15-部署流程走通性核验.md 16-分批启动验证方案.md; do
  printf "    %-45s banner=%s\n" "$f" "$(grep -c '过时时点' "$f" 2>/dev/null)"
done

echo ""
echo "=== 5. 文档数字 vs 集群实测 ==="
echo "    文档(README)写: release=28  Running=95  deploy(0/0)=47"
printf "    实测:           release=%s  Running=%s  deploy(0/0)=%s\n" \
  "$(helm list -n blueking --no-headers 2>/dev/null | wc -l)" \
  "$(kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$3=="Running"' | wc -l)" \
  "$(kubectl get deploy -n blueking --no-headers 2>/dev/null | awk '$2=="0/0"' | wc -l)"

echo ""
echo "=== 6. 标题里是否还有名不副实的 Lite ==="
grep -rn --include='*.md' -E '^#.*(BK-Lite|bk-lite)' . 2>/dev/null | sed 's/^/    /'
echo "    命中: $(grep -rn --include='*.md' -E '^#.*(BK-Lite|bk-lite)' . 2>/dev/null | wc -l)"
