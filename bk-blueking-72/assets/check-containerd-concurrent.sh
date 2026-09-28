#!/usr/bin/env bash
# 只读检查：kind 节点 containerd 的并发下载配置
set -uo pipefail
N=k8s-c1-calico-worker2

echo "===== 1. containerd 配置文件位置与并发项 ====="
docker exec "$N" sh -c 'ls -la /etc/containerd/config.toml 2>/dev/null; echo "--- max_concurrent / concurrent 相关 ---"; grep -nE "max_concurrent|concurrent" /etc/containerd/config.toml 2>/dev/null || echo "  配置中无显式并发项"'

echo ""
echo "===== 2. containerd 实际运行时配置（CRI 部分）====="
docker exec "$N" sh -c 'ctr --address /run/containerd/containerd.sock info 2>/dev/null | head -20' || echo "  ctr info 不可用"

echo ""
echo "===== 3. 检查是否有镜像仓库 mirror 配置 ====="
docker exec "$N" sh -c 'grep -nA5 "registry" /etc/containerd/config.toml 2>/dev/null | head -30 || echo "  无 registry 段"'

echo ""
echo "===== 4. 节点内到 COS 的裸速（对照宿主机 114KiB/s）====="
BIG="sha256:73b36880f2edfa16fbc4a0030247398193e45d26ecce9a6cb396a8bc31787f4d"
TOKEN=$(docker exec "$N" curl -s "https://hub.bktencent.com/service/token?service=harbor-registry&scope=repository:bitnami/elasticsearch:pull" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('token') or d.get('access_token') or '')" 2>/dev/null)
LOC=$(docker exec "$N" curl -s -o /dev/null -w "%{redirect_url}" --max-time 10 -H "Authorization: Bearer $TOKEN" "https://hub.bktencent.com/v2/bitnami/elasticsearch/blobs/$BIG" 2>/dev/null)
echo "  Location 长度: ${#LOC}"
docker exec "$N" curl -sL -o /dev/null -w "  节点内 COS 速度: %{speed_download} B/s\n" --max-time 8 "$LOC" 2>/dev/null

echo ""
echo "===== 5. 宿主机总出口带宽粗测（多连接并发上限）====="
echo "  已由上层脚本测得 8 并发 684 KiB/s，仍在线性区"
