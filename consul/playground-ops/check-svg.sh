#!/usr/bin/env bash
python3 - <<'PYEOF'
import xml.etree.ElementTree as ET, sys, glob, os
base="/mnt/d/projects/learning/consul/子教程/运维专项/assets"
files=sorted(glob.glob(base+"/*.svg"))
print("SVG files:",len(files))
bad=0
for f in files:
    try:
        t=ET.parse(f); r=t.getroot()
        n=len(list(r.iter()))
        print(f"  OK  {os.path.basename(f)}  root={r.tag.split('}')[-1]} nodes={n}")
    except Exception as e:
        bad+=1
        print(f"  FAIL {os.path.basename(f)}  {e}")
print("BAD:",bad)
PYEOF
