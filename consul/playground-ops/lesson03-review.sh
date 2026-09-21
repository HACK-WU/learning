#!/usr/bin/env bash
python3 - <<'PYEOF'
import os,re,glob,xml.etree.ElementTree as ET
root="/mnt/d/projects/learning/consul"
svgs=sorted(glob.glob(root+"/子教程/运维专项/assets/*.svg"))
bad=0
for s in svgs:
    try:
        r=ET.parse(s).getroot(); print(f"  OK   {os.path.basename(s)} nodes={len(list(r.iter()))}")
    except Exception as e:
        bad+=1; print(f"  FAIL {os.path.basename(s)} {e}")
print(f"SVG 非法数: {bad}")

M=root+"/子教程/运维专项/lessons/lesson-03-性能、容量与调优.md"
txt=open(M,encoding='utf-8').read()
print(f"\n讲义: {len(txt.splitlines())} 行")
for s in ['## 第一幕','## 第二幕','## 第三幕','## 第四幕','## 第五幕','## 📇 概念速查卡','## 🚀 下一批接力提示词','## 🧭 课程导航']:
    print(f"  {'OK  ' if s in txt else 'MISS'} {s}")
print("\n知识点:")
for m in re.findall(r'^### 知识点.*$',txt,re.M): print("  ",m)
print("\n图片:",re.findall(r'!\[[^\]]*\]\(([^)]+)\)',txt))

d=os.path.dirname(M)
print("\n链接:")
for r_ in sorted(set(re.findall(r'\]\((\.[^)#]+)\)',txt))):
    t=os.path.normpath(os.path.join(d,r_))
    print(("  OK   " if os.path.exists(t) else "  DEAD ")+r_)
PYEOF
