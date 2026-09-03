#!/bin/bash
# 课 8：搭建最小集群 —— 1 vmstorage + 1 vminsert + 1 vmselect
# 端口规划（避开已占用的 8428/9090/2003/4242）
#   vmstorage : 8482(http) 8400(给vminsert) 8401(给vmselect)
#   vminsert  : 8480(http)
#   vmselect  : 8481(http)
# 内部通信用 Docker 网络 vm-cluster-net，容器名即主机名

set -u
NET=vm-cluster-net
VER=v1.151.0-cluster
DATA=/mnt/d/projects/learning/victoriametrics/playground/cluster-data

echo "=============================================="
echo " S0 清理旧集群（幂等，允许失败）"
echo "=============================================="
for c in vminsert-learn vmselect-learn vmstorage-learn; do
  docker rm -f "$c" >/dev/null 2>&1 && echo "  已删除 $c"
done
docker network rm "$NET" >/dev/null 2>&1 && echo "  已删除网络 $NET"

echo
echo "=============================================="
echo " S1 创建专用网络 + 数据目录"
echo "=============================================="
docker network create "$NET" 2>&1 | tail -1
mkdir -p "$DATA/storage" 2>&1
echo "  数据目录: $DATA/storage"

echo
echo "=============================================="
echo " S2 启动 vmstorage（先启动，另外两个依赖它）"
echo "=============================================="
docker run -d --name vmstorage-learn \
  --network "$NET" \
  -p 8482:8482 -p 8400:8400 -p 8401:8401 \
  -v "$DATA/storage:/storage" \
  "victoriametrics/vmstorage:$VER" \
  -storageDataPath=/storage \
  -retentionPeriod=1d \
  -vminsertAddr=:8400 \
  -vmselectAddr=:8401 \
  -httpListenAddr=:8482 \
  2>&1 | tail -1

echo "  等待 vmstorage 就绪..."
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8482/health' 2>/dev/null)
  if [ "$code" = "200" ]; then echo "  第 ${i}×2 秒：vmstorage 就绪"; break; fi
  sleep 2
done

echo
echo "=============================================="
echo " S3 启动 vminsert"
echo "=============================================="
docker run -d --name vminsert-learn \
  --network "$NET" \
  -p 8480:8480 \
  "victoriametrics/vminsert:$VER" \
  -storageNode=vmstorage-learn:8400 \
  -httpListenAddr=:8480 \
  2>&1 | tail -1

echo
echo "=============================================="
echo " S4 启动 vmselect"
echo "=============================================="
docker run -d --name vmselect-learn \
  --network "$NET" \
  -p 8481:8481 \
  "victoriametrics/vmselect:$VER" \
  -storageNode=vmstorage-learn:8401 \
  -httpListenAddr=:8481 \
  2>&1 | tail -1

echo
echo "  等待 vminsert / vmselect 就绪..."
for i in $(seq 1 30); do
  a=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8480/health' 2>/dev/null)
  b=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8481/health' 2>/dev/null)
  if [ "$a" = "200" ] && [ "$b" = "200" ]; then
    echo "  第 ${i}×2 秒：vminsert=$a vmselect=$b 全部就绪"
    break
  fi
  sleep 2
done

echo
echo "=============================================="
echo " S5 集群状态总览"
echo "=============================================="
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' \
  --filter 'name=vmstorage-learn' --filter 'name=vminsert-learn' --filter 'name=vmselect-learn' 2>&1

echo
echo "=============================================="
echo " S6 三个组件的健康端点"
echo "=============================================="
for p in 8480 8481 8482; do
  echo -n "  port $p health: "
  curl -s --max-time 3 "http://localhost:$p/health" 2>&1 | head -1
done

echo
echo "=============================================="
echo " S7 关键：vminsert 有没有连上 vmstorage"
echo "=============================================="
echo "  -- vminsert 日志尾部 --"
docker logs vminsert-learn 2>&1 | tail -6
echo
echo "  -- vmselect 日志尾部 --"
docker logs vmselect-learn 2>&1 | tail -6
