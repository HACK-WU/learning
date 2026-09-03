#!/bin/bash
# 课 9 交付前结构与事实自检
cd /mnt/d/projects/learning/victoriametrics || exit 1
F="stages/4-怎么横向扩展/9-复制去重与高可用.md"
MISS=0

chk() {
  if grep -qF "$1" "$F"; then echo "[OK]   $2"
  else echo "[MISS] $2"; MISS=$((MISS+1)); fi
}
cnt() {
  local n
  n=$(grep -cF "$1" "$F")
  if [ "$n" -ge "$2" ]; then echo "[OK]   $3  (出现 $n 次 / 需 >=$2)"
  else echo "[MISS] $3  (出现 $n 次 / 需 >=$2)"; MISS=$((MISS+1)); fi
}
file() {
  if [ -f "$1" ]; then echo "[OK]   $2"
  else echo "[MISS] $2 -> $1"; MISS=$((MISS+1)); fi
}

echo "=============================================="
echo " A 组 - 结构合规"
echo "=============================================="
chk "## 第一幕：场景引入"     "A1  第一幕"
chk "## 第二幕：认知冲突"     "A2  第二幕"
chk "## 第三幕：层层揭示"     "A3  第三幕"
chk "## 第四幕：实操验证"     "A4  第四幕"
chk "## 第五幕：体系收束"     "A5  第五幕"
chk "下一批接力提示词"         "A6  接力提示词"
chk "课程导航"                 "A7  课程导航"

cnt "**一句话定义**"   3 "A8  一句话定义 x3"
cnt "#### 直觉建立"    3 "A9  直觉建立 x3"
cnt "#### 核心原理"    3 "A10 核心原理 x3"
cnt "#### 示例演示"    3 "A11 示例演示 x3"
cnt "#### 常见误区"    3 "A12 常见误区 x3"
cnt "#### 一句话记住"  3 "A13 一句话记住 x3"
cnt "类比失效的边界"     3 "A14 类比失效边界 x3"
cnt '```mermaid'            1 "A15 Mermaid 图"

chk "## 课后小测"            "A16 课后小测"
chk "## 一图总结"            "A17 一图总结"
chk "## 常见误区"            "A18 全局常见误区"
chk "### 你现在会了什么"      "A19 你会了什么"
chk "### 关键伏笔"            "A20 关键伏笔"

echo
echo "=============================================="
echo " B 组 - 脚本存在性 / 链接可达"
echo "=============================================="
for s in $(grep -oE 'l09-[a-z0-9-]+\.sh' "$F" | sort -u); do
  file "playground/$s" "脚本 $s"
done
file "stages/4-怎么横向扩展/8-集群三件套与最小集群实战.md" "上一课讲义"
file "stages/4-怎么横向扩展/README.md" "阶段 4 概览"
file "02-课程目录.md"   "课程目录"
file "01-学习路径总览.md" "学习路径总览"

echo
echo "-- 正文内 Markdown 链接目标是否存在 --"
python3 - "$F" <<'PY'
import os, re, sys
f = sys.argv[1]
base = os.path.dirname(f)
bad = 0
for m in re.finditer(r'\[([^\]]+)\]\(([^)]+)\)', open(f, encoding='utf-8').read()):
    tgt = m.group(2)
    if tgt.startswith(('http://', 'https://', '#')):
        continue
    p = os.path.normpath(os.path.join(base, tgt.split('#')[0]))
    if not os.path.exists(p):
        print("[BAD]   %s -> %s" % (tgt, p)); bad += 1
print("本地链接断链数：%d" % bad)
PY

echo
echo "=============================================="
echo " C 组 - 繁简检查"
echo "=============================================="
for w in 本課 課件 存儲 壓縮 機制 數據 內存 緩存 複製 副本數; do
  n=$(grep -oF "$w" "$F" | wc -l)
  if [ "$n" -gt 0 ]; then echo "[WARN] 繁体 '$w' x $n"; MISS=$((MISS+1)); else echo "[OK]   无繁体 '$w'"; fi
done

echo
echo "=============================================="
echo " D 组 - 关键数字与线上复核"
echo "=============================================="
echo "  集群组件存活:"
for pair in "vminsert-learn:8480" "vminsert-learn2:8488" "vmselect-learn:8481" \
            "vmsel-n1:8485" "vmsel-n2:8486" "vmsel-dedup:8487" "vmsel-d5:8489" \
            "vmstorage-learn:8482" "vmstorage-learn2:8492"; do
  name="${pair%%:*}"; port="${pair##*:}"
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://localhost:$port/health" 2>/dev/null)
  echo "    $name (port $port): HTTP $c"
done

echo
echo "  -- 复制因子是否生效 --"
docker inspect vminsert-learn --format '    vminsert 参数: {{.Args}}' 2>&1
echo -n "    vminsert2 参数: "
docker inspect vminsert-learn2 --format '{{.Args}}' 2>&1

echo
echo "  -- dedup 配置核查 --"
for c in vmselect-learn vmsel-dedup vmsel-d5; do
  echo -n "    $c: "
  docker inspect "$c" --format '{{.Args}}' 2>&1 | tr '\n' ' '
  echo
done

echo
echo "  -- 副本失败日志累计 --"
echo "    $(docker logs vminsert-learn 2>&1 | grep -c 'cannot make a copy') 次"

echo
echo "=============================================="
echo " 合计问题数：$MISS"
echo "=============================================="
