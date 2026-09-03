#!/bin/bash
# 课 10 交付前结构与事实自检
cd /mnt/d/projects/learning/victoriametrics || exit 1
F="stages/4-怎么横向扩展/10-多租户与vmauth.md"
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
for s in $(grep -oE 'l10-[a-z0-9-]+\.sh' "$F" | sort -u); do
  file "playground/$s" "脚本 $s"
done
file "stages/4-怎么横向扩展/9-复制去重与高可用.md" "上一课讲义"
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
for w in 本課 課件 存儲 壓縮 機制 數據 內存 緩存 複製 租戶 認證 權限 負載; do
  n=$(grep -oF "$w" "$F" | wc -l)
  if [ "$n" -gt 0 ]; then echo "[WARN] 繁体 '$w' x $n"; MISS=$((MISS+1)); else echo "[OK]   无繁体 '$w'"; fi
done

echo
echo "=============================================="
echo " D 组 - 线上配置复核"
echo "=============================================="
echo "  -- vmauth 实例 --"
for c in vmauth-learn vmauth-2 vmauth-limit vmauth-strict; do
  printf "    %-14s " "$c"
  docker inspect "$c" --format '{{.State.Status}}  {{range .Args}}{{.}} {{end}}' 2>&1 | head -c 160
  echo
done

echo
echo "  -- vmauth 认证实测 --"
printf "    无凭证:          "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 10 \
  --data-urlencode 'query=up' 'http://localhost:8427/api/v1/query'
printf "    backend(正确):   "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 10 -u backend:backend-pass-123 \
  --data-urlencode 'query=l10_va_value' 'http://localhost:8427/api/v1/query'
printf "    frontend(正确):  "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 10 -u frontend:frontend-pass-456 \
  --data-urlencode 'query=l10_va_value' 'http://localhost:8427/api/v1/query'

echo
echo "  -- 租户绑定复核 --"
for u in backend:backend-pass-123 frontend:frontend-pass-456; do
  printf "    %-10s " "${u%%:*}"
  curl -s --max-time 20 -u "$u" --data-urlencode 'query=l10_va_value' \
    'http://localhost:8427/api/v1/query' \
    | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
    print(sorted(set(x["value"][1] for x in r)) if r else "空")
except Exception: print("N/A")' 2>&1
done

echo
echo "  -- 全局 tsid 缓存（对比讲义中的 2932 → 10932）--"
for p in 8482 8492; do
  printf "    vmstorage(%s) tsid: " "$p"
  curl -s --max-time 15 "http://localhost:$p/metrics" 2>/dev/null \
    | grep 'vm_cache_entries{type="storage/tsid"' | head -1 | awk '{print $2}'
done

echo
echo "=============================================="
echo " 合计问题数：$MISS"
echo "=============================================="
