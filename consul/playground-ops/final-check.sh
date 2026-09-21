#!/usr/bin/env bash
python3 - <<'PYEOF'
import os,re,glob
import xml.etree.ElementTree as ET
root="/mnt/d/projects/learning/consul"
md=[p for p in glob.glob(root+"/**/*.md",recursive=True)]
pat=re.compile(r'\[([^\]]*)\]\((\.[^)#]+)\)')
dead=[];total=0
for f in md:
    d=os.path.dirname(f)
    txt=open(f,encoding='utf-8',errors='replace').read()
    for label,rel in pat.findall(txt):
        if rel.startswith('./') or rel.startswith('../') or '/' in rel:
            total+=1
            t=os.path.normpath(os.path.join(d,rel))
            if not os.path.exists(t):
                dead.append((os.path.relpath(f,root),rel))
print(f"markdown 文件: {len(md)}")
print(f"相对链接总数: {total}")
print(f"断链: {len(dead)}")
for f,r in dead: print("   DEAD",f,"->",r)

svgs=glob.glob(root+"/**/*.svg",recursive=True)
bad=0
for s in svgs:
    try: ET.parse(s)
    except Exception as e: bad+=1; print("   SVG FAIL",s,e)
print(f"SVG: {len(svgs)} 张, 非法 {bad}")
PYEOF
