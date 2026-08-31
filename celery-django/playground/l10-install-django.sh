#!/usr/bin/env bash
set -u
echo "=== 安装 Django ==="
/tmp/l9venv/bin/pip install -q django 2>&1 | tail -5 || true
echo
echo "=== 确认版本 ==="
/tmp/l9venv/bin/python -c "import django; print('django', django.get_version())" 2>&1
/tmp/l9venv/bin/python -c "import celery; print('celery', celery.__version__)" 2>&1
exit 0
