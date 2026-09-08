#!/usr/bin/env bash
echo "=== 1) 基础镜像是否已带 snappy ==="
docker run --rm python:3.11-slim python -c "import snappy; print('snappy ok')" 2>&1 | tail -n 3

echo
echo "=== 2) 尝试 pip 安装 cramjam（纯 wheel，含 snappy 解压） ==="
docker run --rm python:3.11-slim sh -c 'pip install -q cramjam 2>&1 | tail -n 2; python -c "import cramjam; print(\"cramjam ok\")"' 2>&1 | tail -n 5

echo
echo "=== 3) 尝试 pip 安装 python-snappy（需系统库，预计失败） ==="
docker run --rm python:3.11-slim sh -c 'pip install -q python-snappy 2>&1 | tail -n 3; python -c "import snappy; print(\"python-snappy ok\")"' 2>&1 | tail -n 6
