#!/usr/bin/env bash
# 课 7 讲义双视角评审辅助校验
F=/mnt/d/projects/learning/prometheus/stages/3-规模化与生态/lessons/lesson-07-远程读写与Agent模式.md
V=0   # 违规计数

echo "=== pedagogy 视角：结构完整性 ==="
for h in "## 一、场景引入" "## 二、认知冲突" "## 三、层层揭示" "## 四、实操验证" "## 五、体系收束"; do
  n=$(grep -c "^$h" "$F")
  [ "$n" -eq 1 ] && echo "  OK   $h" || { echo "  BAD  $h (出现 $n 次)"; V=$((V+1)); }
done

echo
echo "=== pedagogy 视角：六要素（三个知识点各 6 项） ==="
python3 - "$F" <<'PY'
import re,sys
t=open(sys.argv[1],encoding='utf-8').read()
kps=re.split(r'\n### 知识点 ', t)[1:]
for kp in kps:
    name=kp.split('\n')[0]
    items={}
    for m in re.finditer(r'\n#### \d+\. ([^\n]+)', kp):
        items[m.group(1).strip()]=True
    print(f"  知识点 {name}: {len(items)} 项 -> {list(items.keys())}")
PY

echo
echo "=== learner 视角：可执行 bash 块内的可疑项 ==="
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
        # 失效路径 /d/
        if re.search(r'(?<![\w/])/d/', s):
            print(f"  [P0] 块{i} 行{ln}: 失效路径 /d/ -> {s}"); issues+=1
        # 未编码的 curl 加号
        if 'curl' in s and re.search(r'~\s*"?\.\+"?', s) and '%2B' not in s:
            print(f"  [P1] 块{i} 行{ln}: curl 内 .+ 未编码 -> {s}"); issues+=1
        # head 命令（bash 可用，但提醒）
    # 缺 sleep 说明
    m=re.search(r'^\s*sleep (\d+)\s*$', b, re.M)
    if m:
        seg=b[m.start():m.end()+120]
        if '#' not in seg:
            print(f"  [P2] 块{i}: sleep {m.group(1)} 附近无注释说明")
print(f"  可疑项 = {issues}")
PY

echo
echo "=== learner 视角：旧指标名是否残留（应只在对照表/历史说明中） ==="
python3 - "$F" <<'PY'
import re,sys
t=open(sys.argv[1],encoding='utf-8').read()
lines=t.split('\n')
for i,l in enumerate(lines,1):
    if 'samples_out_total' in l or 'samples_dropped_total' in l or 'bytes_sent_total' in l:
        ctx='对照/历史' if any(k in l for k in ['旧','改名','移除','已不存在','改为']) else '⚠需人工确认'
        print(f"  行{i}: [{ctx}] {l.strip()[:100]}")
PY

echo
echo "=== learner 视角：端口一致性（本课应为 19099~19107） ==="
grep -oE 'localhost:19[0-9]{3}' "$F" | sort | uniq -c | sort -rn
echo "  --- 非本课端口（应只出现在说明性对比中）---"
grep -nE '1909[0-4]|1908[0-9]' "$F" | sed 's/^/  /' | head -n 5

echo
echo "=== learner 视角：导航链接存在性 ==="
for lk in $(grep -oE '\]\(\.\.?[^)]+\.md\)' "$F" | tr -d '](' | tr -d ')'); do
  p="/mnt/d/projects/learning/prometheus/stages/3-规模化与生态/lessons/$lk"
  if [ -f "$p" ]; then echo "  OK   $lk"; else echo "  BAD  $lk"; V=$((V+1)); fi
done

echo
echo "=== 文档规模 ==="
echo "  字节数 = $(wc -c < "$F")"
echo "  行数   = $(wc -l < "$F")"
echo
echo "=== 结构违规总数 = $V ==="
