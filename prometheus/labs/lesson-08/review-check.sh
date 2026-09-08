#!/usr/bin/env bash
# 课 8 讲义双视角评审校验
F=/mnt/d/projects/learning/prometheus/stages/3-规模化与生态/lessons/lesson-08-联邦与全局视图.md
V=0

echo "=== pedagogy：五幕结构 ==="
for h in "## 一、场景引入" "## 二、认知冲突" "## 三、层层揭示" "## 四、实操验证" "## 五、体系收束"; do
  n=$(grep -c "^$h" "$F")
  [ "$n" -eq 1 ] && echo "  OK   $h" || { echo "  BAD  $h (出现 $n 次)"; V=$((V+1)); }
done

echo
echo "=== pedagogy：六要素（三个知识点各 6 项）==="
python3 - "$F" <<'PY'
import re,sys
t=open(sys.argv[1],encoding='utf-8').read()
kps=re.split(r'\n### 知识点 ', t)[1:]
for kp in kps:
    name=kp.split('\n')[0]
    items=[m.group(1).strip() for m in re.finditer(r'\n#### \d+\. ([^\n]+)', kp)]
    print(f"  知识点 {name}: {len(items)} 项 -> {items}")
PY

echo
echo "=== learner：可执行 bash 块内的可疑项 ==="
python3 - "$F" <<'PY'
import re,sys
t=open(sys.argv[1],encoding='utf-8').read()
blocks=re.findall(r'```bash\n(.*?)```', t, re.S)
print(f"  可执行 bash 块总数 = {len(blocks)}")
issues=0
for i,b in enumerate(blocks,1):
    for ln,line in enumerate(b.split('\n'),1):
        s=line.strip()
        if s.startswith('#') or not s: continue
        if re.search(r'(?<![\w/])/d/', s):
            print(f"  [P0] 块{i} 行{ln}: 失效路径 /d/ -> {s}"); issues+=1
    m=re.search(r'^\s*sleep (?:"?\$?\w+"?|\d+)\s*$', b, re.M)
    if m:
        seg=b[max(0,m.start()-200):m.end()+120]
        if '等' not in seg and '#' not in seg:
            print(f"  [P2] 块{i}: sleep {m.group(0).strip()} 附近无中文说明")
print(f"  可疑 P0 项 = {issues}")
PY

echo
echo "=== learner：端口一致性（本课应为 19110~19121）==="
grep -oE 'localhost:19[0-9]{3}' "$F" | sort | uniq -c | sort -rn
echo "  --- 越界端口（非本课段）---"
grep -oE 'localhost:19[0-9]{3}' "$F" | sort -u | awk -F: '$2<19110 || $2>19121 {print "  OUT  "$0}'

echo
echo "=== learner：导航链接存在性 ==="
D=$(dirname "$F")
for lk in $(grep -oE '\]\(\.\.?[^)]+\.md\)' "$F" | sed 's/^](//; s/)$//' | sort -u); do
  if [ -e "$D/$lk" ]; then echo "  OK   $lk"; else echo "  DEAD $lk"; V=$((V+1)); fi
done

echo
echo "=== 文档规模 ==="
echo "  字节数 = $(wc -c < "$F")   行数 = $(wc -l < "$F")"
echo
echo "=== 结构违规总数 = $V ==="
