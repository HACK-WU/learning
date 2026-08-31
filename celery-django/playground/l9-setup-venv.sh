#!/usr/bin/env bash
# 课 9 环境搭建：创建 venv 并安装 celery[redis]（用于并发模型与停机行为实测）
set -u

VENV=/tmp/l9venv

echo "=== 1. 创建 venv ==="
python3 -m venv "$VENV" 2>&1 | tail -3

echo
echo "=== 2. 安装 celery[redis] ==="
"$VENV/bin/pip" install -q 'celery[redis]' 2>&1 | tail -5

echo
echo "=== 3. 版本确认 ==="
"$VENV/bin/python" -c 'import celery; print("celery", celery.__version__)'
"$VENV/bin/python" -c 'import kombu; print("kombu", kombu.__version__)'
