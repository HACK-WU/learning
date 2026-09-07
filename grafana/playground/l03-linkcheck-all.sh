#!/usr/bin/env bash
# 全仓链接可达性检查（课 2 起强制）：扫描所有 md 里的相对链接
set -u
cd /mnt/d/projects/learning/grafana
python3 - <<'PYEOF'
import os, re, sys
ROOT='/mnt/d/projects/learning/grafana'
bad=0; total=0; per={}
skip=('assets/','http://','https://','#','mailto:')
for dp,dn,fn in os.walk(ROOT):
    if '/.git' in dp: continue
    for f in fn:
        if not f.endswith('.md'): continue
        p=os.path.join(dp,f)
        rel=os.path.relpath(p,ROOT)
        try: txt=open(p,encoding='utf-8').read()
        except Exception: continue
        for m in re.finditer(r'\[([^\]]*)\]\(([^)]+)\)', txt):
            t=m.group(2).split('#')[0].strip()
            if not t or any(t.startswith(s) for s in skip): continue
            target=os.path.normpath(os.path.join(dp,t))
            total+=1
            if not os.path.exists(target):
                bad+=1
                per.setdefault(rel,[]).append((m.group(1),t))
print(f"扫描链接总数 = {total}   缺失 = {bad}")
for f,items in per.items():
    print(f"\n  📄 {f}")
    for label,t in items[:8]:
        print(f"     ❌ {label} -> {t}")
if bad==0: print("\n  ✅ 全部可达，0 死链")
sys.exit(1 if bad else 0)
PYEOF
