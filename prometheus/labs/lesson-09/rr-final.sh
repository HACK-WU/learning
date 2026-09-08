#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus
PASS=0; FAIL=0
ck(){ if [ "$2" = "$3" ]; then echo "PASS  $1"; PASS=$((PASS+1)); else echo "FAIL  $1 (expect=$3 actual=$2)"; FAIL=$((FAIL+1)); fi; }

echo "===== A. 全仓链接可达（只看正式交付物，排除 labs 中间产物）====="
python3 - "$D" <<'PY'
import os,re,sys
root=sys.argv[1]
bad=0;tot=0
for dp,dn,fn in os.walk(root):
    if 'labs' in dp or '.git' in dp: continue
    for f in fn:
        if not f.endswith('.md'): continue
        p=os.path.join(dp,f)
        try: s=open(p,encoding='utf-8').read()
        except: continue
        for m in re.finditer(r'\[([^\]]*)\]\(([^)]+)\)',s):
            t=m.group(2)
            if t.startswith(('http','#','mailto')): continue
            t=t.split('#')[0]
            if not t: continue
            rp=os.path.normpath(os.path.join(dp,t))
            tot+=1
            if not os.path.exists(rp):
                print("DEAD",os.path.relpath(p,root),"->",t); bad+=1
print(f"checked={tot} dead={bad}")
PY

echo ""
echo "===== B. 关键事实一致性 ====="
G7=$D/stages/3-规模化与生态/lessons/lesson-07-远程读写与Agent模式.md
G9=$D/stages/3-规模化与生态/lessons/lesson-09-长期存储选型.md
OV=$D/stages/3-规模化与生态/overview.md
AR=$D/00-学习档案.md
RV=$D/00-评审清单.md

c=$(grep -c "STREAMED_CHUNKS.*不存在\|并不存在" $G7); ck "课7标注该模式不存在" "$([ $c -ge 1 ] && echo yes || echo no)" "yes"
c=$(grep -c "两种 + 一个分帧参数" $G7); ck "课7含正确表述" "$([ $c -ge 1 ] && echo yes || echo no)" "yes"
c=$(grep -c "补做完成" $G9); ck "课9标注补做完成" "$([ $c -ge 1 ] && echo yes || echo no)" "yes"
c=$(grep -c "RR-DATA.md" $OV); ck "overview 引用 RR-DATA" "$([ $c -ge 1 ] && echo yes || echo no)" "yes"
c=$(grep -c "remote read" $AR); ck "学习档案含 remote read 记录" "$([ $c -ge 1 ] && echo yes || echo no)" "yes"
c=$(grep -c "remote read 分模式对照" $RV); ck "评审清单含补做记录" "$([ $c -ge 1 ] && echo yes || echo no)" "yes"

echo ""
echo "===== C. RR-DATA.md 存在且非空 ====="
n=$(wc -l < $D/labs/lesson-09/RR-DATA.md); ck "RR-DATA 行数>50" "$([ $n -gt 50 ] && echo yes || echo no)" "yes"

echo ""
echo "=============================="
echo "PASS=$PASS  FAIL=$FAIL"
