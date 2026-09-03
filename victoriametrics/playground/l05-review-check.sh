#!/bin/bash
# 课 5 交付前结构与事实自检（WSL 下运行，避免 PowerShell 中文匹配缺陷）
cd /mnt/d/projects/learning/victoriametrics || exit 1
F="stages/3-凭什么快凭什么省/5-存储引擎MergeSet与磁盘结构.md"
STAGE="stages/3-凭什么快凭什么省"
MISS=0

chk() {
  if grep -qF "$1" "$F"; then echo "[OK]   $2"
  else echo "[MISS] $2"; MISS=$((MISS+1)); fi
}
cnt() {
  local n
  n=$(grep -cF "$1" "$F")
  if [ "$n" -ge "$2" ]; then echo "[OK]   $3  (出现 $n 次 / 需 ≥$2)"
  else echo "[MISS] $3  (出现 $n 次 / 需 ≥$2)"; MISS=$((MISS+1)); fi
}
file() {
  if [ -f "$1" ]; then echo "[OK]   $2  -> $1"
  else echo "[MISS] $2  -> $1"; MISS=$((MISS+1)); fi
}

echo "=============================================="
echo " A 组 · 结构合规"
echo "=============================================="
chk "## 第一幕：场景引入"     "A1  第一幕 场景引入"
chk "## 第二幕：认知冲突"     "A2  第二幕 认知冲突"
chk "## 第三幕：层层揭示"     "A3  第三幕 层层揭示"
chk "## 第四幕：实操验证"     "A4  第四幕 实操验证"
chk "## 第五幕：体系收束"     "A5  第五幕 体系收束"
chk "🚀 下一批接力提示词"      "A6  下一批接力提示词段"
chk "🧭 课程导航"              "A7  课程导航段"

cnt "**一句话定义**"   3 "A8  六要素·一句话定义 ×3"
cnt "#### 直觉建立"    3 "A9  六要素·直觉建立 ×3"
cnt "#### 核心原理"    3 "A10 六要素·核心原理 ×3"
cnt "#### 示例演示"    3 "A11 六要素·示例演示 ×3"
cnt "#### 常见误区"    3 "A12 六要素·常见误区 ×3"
cnt "#### 一句话记住"  3 "A13 六要素·一句话记住 ×3"

cnt "⚠️ **类比失效的边界**" 3 "A14 类比失效边界 ×3"
cnt '```mermaid'            2 "A15 Mermaid 图（≥2 块）"
chk "## 课后小测"            "A16 课后小测"
chk "## 一图总结"            "A17 一图总结"
chk "## 🐞 常见误区"          "A18 全局常见误区清单"
chk "### 你现在会了什么"      "A19 第五幕 你会了什么"
chk "### 关键伏笔"            "A20 第五幕 关键伏笔"

echo
echo "=============================================="
echo " B 组 · 数据事实 / 链接可达"
echo "=============================================="

echo "-- B1 讲义引用的实验脚本是否真实存在 --"
for s in $(grep -oE 'l05-[a-z0-9-]+\.sh' "$F" | sort -u); do
  file "playground/$s" "脚本 $s"
done

echo "-- B2 讲义引用的跨课文件是否可达 --"
file "stages/2-数据怎么进来怎么查/4-写入协议全家桶与基数治理.md" "上一课讲义"
file "$STAGE/README.md"                    "阶段 3 概览"
file "02-课程目录.md"                       "课程目录"
file "01-学习路径总览.md"                   "学习路径总览"

echo "-- B3 正文内 Markdown 链接目标是否存在（相对课文件所在目录解析）--"
python3 - "$F" "$STAGE" <<'PY'
import os, re, sys
f, stage = sys.argv[1], sys.argv[2]
base = os.path.dirname(f)
bad = 0
for m in re.finditer(r'\[([^\]]+)\]\(([^)]+)\)', open(f, encoding='utf-8').read()):
    tgt = m.group(2)
    if tgt.startswith(('http://', 'https://', '#')):
        continue
    p = os.path.normpath(os.path.join(base, tgt.split('#')[0]))
    ok = os.path.exists(p)
    print(("[OK]   链接 %-58s -> %s" if ok else "[BAD]   链接 %-58s -> %s") % (tgt, p))
    if not ok:
        bad += 1
print("本地链接断链数：%d" % bad)
PY

echo "-- B4 错别字 / 繁简混用扫描（本课应为简体）--"
for w in 本課 課件 存儲 壓縮 機制; do
  n=$(grep -oF "$w" "$F" | wc -l)
  if [ "$n" -gt 0 ]; then echo "[WARN] 疑似繁体词 '$w' 出现 $n 次"; MISS=$((MISS+1))
  else echo "[OK]   无繁体 '$w'"; fi
done

echo
echo "=============================================="
echo " 合计问题数：$MISS"
echo "=============================================="
