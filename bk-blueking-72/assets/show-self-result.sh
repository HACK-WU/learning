#!/usr/bin/env bash
set -uo pipefail
F=/root/bk72/render_test/self_images2.txt
echo "总探测: $(wc -l < "$F")"
echo "--- 分布 ---"
cut -f1 "$F" | sort | uniq -c | sort -rn
echo "--- 非200 清单 ---"
grep -v '^200' "$F" | cut -f1,2 | head -20
