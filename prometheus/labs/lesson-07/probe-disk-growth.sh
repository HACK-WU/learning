#!/usr/bin/env bash
# 严谨对照：观察 agent 与 server 磁盘在 120 秒内的增长，判断谁已收敛
echo "=== 起点 ==="
P0=$(docker exec l7-prom  sh -c 'du -sk /prometheus 2>/dev/null' | cut -f1)
A0=$(docker exec l7-agent sh -c 'du -sk /data-agent 2>/dev/null' | cut -f1)
echo "  server(prom) = ${P0} KB   agent = ${A0} KB"
echo "  运行时长:"
docker ps --format "{{.Names}} {{.Status}}" --filter "name=l7-prom$" --filter "name=l7-agent"

sleep 120

P1=$(docker exec l7-prom  sh -c 'du -sk /prometheus 2>/dev/null' | cut -f1)
A1=$(docker exec l7-agent sh -c 'du -sk /data-agent 2>/dev/null' | cut -f1)
echo "=== 120 秒后 ==="
echo "  server(prom) = ${P1} KB   (增量 $((P1-P0)) KB)"
echo "  agent        = ${A1} KB   (增量 $((A1-A0)) KB)"
echo "=== 内存 ==="
docker stats --no-stream --format "{{.Name}}|{{.MemUsage}}" l7-prom l7-agent
