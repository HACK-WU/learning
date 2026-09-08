#!/usr/bin/env bash
echo "=== 宿主机经映射端口 19101 查 VM ==="
echo "--- health ---"
curl -s --max-time 5 http://localhost:19101/health || wget -qO- --timeout=5 http://localhost:19101/health
echo
echo "--- count(l7_card_balance) ---"
curl -s --max-time 10 --data-urlencode 'query=count(l7_card_balance)' http://localhost:19101/api/v1/query 2>/dev/null | head -c 400
echo
echo "--- 当前有哪些指标名 ---"
curl -s --max-time 10 http://localhost:19101/api/v1/label/__name__/values 2>/dev/null | head -c 800
echo
