#!/usr/bin/env bash
NS=blueking
echo "=== TRIM CANDIDATES (by subsystem memory) ==="
kubectl top pods -n $NS --no-headers 2>/dev/null > /tmp/tp.txt 2>&1
if [ ! -s /tmp/tp.txt ]; then echo "  metrics unavailable"; exit 1; fi

awk '{m=$3+0; if($3 ~ /Gi/) m=m*1024; n=$1; split(n,p,"-"); k=p[1]"-"p[2]; t[k]+=m; c[k]++} END {for(x in t) printf "%8d %4d %s\n", t[x], c[x], x}' /tmp/tp.txt \
 | sort -rn | head -20 | awk '{printf "  %-30s pods=%-4d mem=%6dMi (%5.1fGi)\n", $3, $2, $1, $1/1024}'

echo ""
echo "=== TOTAL ==="
awk '{m=$3+0; if($3 ~ /Gi/) m=m*1024; s+=m} END {printf "  blueking total: %dMi (%.1fGi)\n", s, s/1024}' /tmp/tp.txt
