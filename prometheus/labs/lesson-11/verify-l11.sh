#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus
PASS=0; FAIL=0
ck(){ if [ "$2" = "$3" ]; then echo "PASS  $1"; PASS=$((PASS+1)); else echo "FAIL  $1 (expect=$3 actual=$2)"; FAIL=$((FAIL+1)); fi; }
gc(){ grep -c -- "$2" "$1" 2>/dev/null || echo 0; }
G=$D/stages/4-生产运维/lessons/lesson-11-容量规划与调优.md
AR=$D/00-学习档案.md; RV=$D/00-评审清单.md; OV=$D/stages/4-生产运维/overview.md
CD=$D/02-课程目录.md; LP=$D/01-学习路径总览.md

echo "===== A. 四处档案同步 ====="
ck "学习档案：课11 三知识点已完成" "$(gc $AR '| 4 | 课 11 |.*✅ 已完成')" "3"
ck "评审清单：含课11评审记录"      "$(gc $RV '课 11《容量规划与调优》')" "2"
ck "阶段overview：课11 已勾选"     "$(gc $OV '\- \[x\] `lessons/lesson-11-容量规划与调优.md`')" "1"
ck "课程目录：课11 标 ✅"          "$(gc $CD '| 11 | 容量规划与调优 |.*✅')" "1"
ck "路径总览：阶段4 进行中"        "$(gc $LP '阶段 4：生产运维（🔄 进行中')" "1"
ck "路径总览：总进度 33/36"        "$(gc $LP '33/36')" "1"

echo ""
echo "===== B. 关键事实入档 ====="
ck "档案含 self-scrape 纠正课10（进度表+事实核查各1）" "$(gc $AR '纠正课 10 错误结论')" "2"
ck "档案含 docker stats 不成立"    "$(gc $AR '`docker stats` 足以测量内存')" "1"
ck "档案含业界值部分不成立"        "$(gc $AR '每百万序列 4~8 GiB')" "1"
ck "档案含本机上限 15 万"          "$(gc $AR '20 万序列可测')" "1"

echo ""
echo "===== C. 讲义与底稿一致性（关键数字）====="
for n in "1.66" "1.662" "0.202" "27.71" "29.10" "2.96" "335" "7.2" "328" "0.9969"; do
  c=$(gc "$G" "$n")
  ck "讲义含 [$n]" "$([ $c -ge 1 ] && echo yes || echo no)" "yes"
done
for n in "1.662" "0.202" "27.71" "2.96" "7.2" "328"; do
  c=$(gc "$D/labs/lesson-11/CAPACITY-DATA.md" "$n")
  if [ "$c" -ge 1 ]; then r=yes; else r=no; fi
  ck "底稿含 [$n]" "$r" "yes"
done

echo ""
echo "===== D. 讲义结构 ====="
for s in "第一幕：场景引入" "第二幕：认知冲突" "第三幕：层层揭示" "第四幕：实操验证" "第五幕：体系收束" \
         "知识点清单" "评审结论" "速览卡" "小测" "接力提示词" "未实测"; do
  ck "含 $s" "$(gc "$G" "$s" | awk '{print ($1>0)?"yes":"no"}')" "yes"
done

echo ""
echo "===== E. 全仓链接（排除 labs）====="
python3 - "$D" <<'PY'
import os,re,sys
root=sys.argv[1]; bad=0; tot=0
for dp,dn,fn in os.walk(root):
    if 'labs' in dp or '.git' in dp: continue
    for f in fn:
        if not f.endswith('.md'): continue
        p=os.path.join(dp,f)
        for m in re.finditer(r'\[([^\]]*)\]\(([^)]+)\)', open(p,encoding='utf-8').read()):
            t=m.group(2)
            if t.startswith(('http','#','mailto')): continue
            t=t.split('#')[0]
            if not t: continue
            tot+=1
            if not os.path.exists(os.path.normpath(os.path.join(dp,t))):
                print("DEAD",os.path.relpath(p,root),"->",t); bad+=1
print(f"checked={tot} dead={bad}")
PY

echo ""
echo "=============================="
echo "PASS=$PASS  FAIL=$FAIL"
