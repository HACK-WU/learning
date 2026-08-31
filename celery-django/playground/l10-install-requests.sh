#!/usr/bin/env bash
set -u
/tmp/l9venv/bin/pip install -q requests 2>&1 | tail -3 || true
/tmp/l9venv/bin/python -c "import requests; print('requests', requests.__version__)" 2>&1
exit 0
