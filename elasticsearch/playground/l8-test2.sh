#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "=== l8_orders 实际 mapping ==="
$C "$ES/l8_orders/_mapping?pretty"
echo ""
echo "########## DONE-L8-2 ##########"
