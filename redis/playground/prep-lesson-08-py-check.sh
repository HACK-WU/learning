#!/usr/bin/env bash
set -u
cd /tmp
python3 -c "import redis; print('redis-py', redis.__version__)" 2>&1 | tail -3
echo "--- pip ---"
python3 -m pip --version 2>&1 | head -2
