#!/usr/bin/env bash
BASE="/mnt/d/projects/learning/bk-blueking-72"
cd "$BASE" || exit 1
python3 - "$BASE" <<'PY'
import re,os,sys
base=sys.argv[1]
bad=0
for doc in ["25-部署验收总报告-全8批合并.md","README-验证报告索引.md"]:
    try: txt=open(os.path.join(base,doc),encoding='utf-8').read()
    except Exception as e: print("  读取失败",doc,e); continue
    links=re.findall(r'\]\(([^)]+\.md)\)',txt)
    print("  [%s] 链接 %d 条"%(doc,len(links)))
    for l in sorted(set(links)):
        p=os.path.join(base,l)
        if os.path.isfile(p): print("    OK   %s"%l)
        else: print("    断链 %s"%l); bad+=1
print("  断链总数: %d"%bad)
PY
