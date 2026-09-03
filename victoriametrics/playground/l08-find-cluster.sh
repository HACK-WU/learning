#!/bin/bash
# 查找集群版镜像的正确 tag
echo "=== 尝试 1: latest-cluster ==="
timeout 180 docker pull victoriametrics/victoria-metrics:latest-cluster 2>&1 | tail -3

echo
echo "=== 尝试 2: 从 Docker Hub API 查可用 tags ==="
curl -s --max-time 30 "https://hub.docker.com/v2/repositories/victoriametrics/victoria-metrics/tags?page_size=100" \
  -o /tmp/vmtags.json 2>&1
python3 /mnt/d/projects/learning/victoriametrics/playground/l08-findtag.py 2>&1
