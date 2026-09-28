#!/usr/bin/env bash
F=/root/bk72/install/blueking/base-blueking.yaml.gotmpl
echo "=== base-blueking.yaml.gotmpl (first 120 lines) ==="
sed -n '1,120p' "$F" 2>&1 | sed 's/^/  /'
