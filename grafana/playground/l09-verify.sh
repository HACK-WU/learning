#!/usr/bin/env bash
# 课 9 交付前结构校验（沿用课 4/课 8 的判据）
set -u
F="/mnt/d/projects/learning/grafana/stages/3-叫得醒/lessons/lesson-09-日志与链路：指标之外的另外两只眼.md"
cd /mnt/d/projects/learning/grafana

echo "=== A. 基本统计 ==="
echo "  行数 = $(wc -l < "$F")"
echo "  字节 = $(wc -c < "$F")"

echo ""
echo "=== B. 代码块围栏配对 ==="
python3 - "$F" <<'PY'
import sys,re
p=sys.argv[1]
raw=open(p,encoding="utf-8").read().split("\n")
in_block=False; opens=0; closes=0; bad=[]
for i,l in enumerate(raw,1):
    s=l.strip()
    # 处理 Markdown 引用块：去掉 > 前缀后再判
    t=re.sub(r'^\s*>\s?','',s)
    if t.startswith("```"):
        if not in_block:
            in_block=True; opens+=1
        else:
            in_block=False; closes+=1
print(f"  开头 ``` = {opens}   结尾 ``` = {closes}")
print(f"  {'✅ 配对正常' if opens==closes and not in_block else '❌ 不配对或结尾仍在块内'}")
PY

echo ""
echo "=== C. 代码块外的反斜杠续行（课 4 P0，PowerShell 不兼容）==="
python3 - "$F" <<'PY'
import sys,re
p=sys.argv[1]
lines=open(p,encoding="utf-8").read().split("\n")
in_block=False; bad=[]
for i,l in enumerate(lines,1):
    s=l.strip()
    t=re.sub(r'^\s*>\s?','',s)
    if t.startswith("```"):
        in_block = not in_block
        continue
    if not in_block and re.search(r'\\[ \t]*$', l):
        bad.append((i, l[:80]))
print(f"  代码块外续行 = {len(bad)}")
for i,l in bad[:10]:
    print(f"    L{i}: {l}")
PY

echo ""
echo "=== D. Python 多行字符串里的续行（应排除，非 bash 命令）==="
python3 - "$F" <<'PY'
import sys,re
p=sys.argv[1]
lines=open(p,encoding="utf-8").read().split("\n")
in_block=False; lang=""; bad=[]
for i,l in enumerate(lines,1):
    s=l.strip()
    t=re.sub(r'^\s*>\s?','',s)
    if t.startswith("```"):
        if not in_block:
            in_block=True; lang=t[3:].strip().lower()
        else:
            in_block=False; lang=""
        continue
    if in_block and lang in ("bash","sh","shell","powershell") and re.search(r'\\[ \t]*$', l):
        bad.append((i,lang,l[:70]))
print(f"  bash/sh 块内续行 = {len(bad)}")
for i,lg,l in bad[:10]:
    print(f"    L{i} [{lg}]: {l}")
PY

echo ""
echo "=== E. 死链检查（含返回根目录链接层级）==="
python3 - "$F" <<'PY'
import sys,re,os
p=sys.argv[1]
base=os.path.dirname(os.path.abspath(p))
txt=open(p,encoding="utf-8").read()
links=re.findall(r'\[([^\]]*)\]\(([^)]+)\)', txt)
bad=[]; ok=0
for name,tgt in links:
    if tgt.startswith(("http://","https://","#","mailto:")):
        continue
    t=tgt.split("#")[0]
    if not t: continue
    full=os.path.normpath(os.path.join(base,t))
    if os.path.exists(full): ok+=1
    else: bad.append((name,tgt))
print(f"  本地链接可解析 = {ok}   死链 = {len(bad)}")
for n,t in bad:
    print(f"    ❌ [{n}]({t})")
PY

echo ""
echo "=== F. 章节完整性（对照课 8 体例）==="
for k in "## 🎯 本课目标" "## 知识点导航" "## 📖 开篇" "## 🧠 9.1" "## 🧠 9.2" "## 🧠 9.3" "## 🔗 跨课串联" "## 🧪 实验记录" "## ✅ 本课验收" "## 🔍 评审结论" "## 🎯 小测" "## 📚 课程导航" "## 🚀 下一批接力提示词"; do
  if grep -qF "$k" "$F"; then echo "  ✅ $k"; else echo "  ❌ 缺失: $k"; fi
done

echo ""
echo "=== G. 六要素检查（每个知识点：定义/直觉/原理/示例/误区/一句话）==="
python3 - "$F" <<'PY'
import sys,re
p=sys.argv[1]
lines=open(p,encoding="utf-8").read().split("\n")
secs={}; cur=None
for i,l in enumerate(lines,1):
    m=re.match(r'^## 🧠 (9\.\d)', l)
    if m:
        cur=m.group(1); secs[cur]=[]
    elif re.match(r'^## ', l) and cur:
        cur=None
    if cur:
        secs[cur].append(l)
need=["### 一句话定义","### 直觉建立","### 核心原理","### 示例演示","### 常见误区","### 一句话记住"]
for k in sorted(secs):
    body="\n".join(secs[k])
    miss=[n for n in need if n not in body]
    print(f"  {k}: {'✅ 六要素齐全' if not miss else '❌ 缺 '+', '.join(miss)}")
PY
