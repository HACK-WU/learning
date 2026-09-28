#!/usr/bin/env bash
echo "=== POD MEMORY BY SUBSYSTEM (real, all pods up) ==="
kubectl top pods -n blueking --no-headers 2>/dev/null | awk '
{
  m=$3+0; if($3 ~ /Gi/) m=m*1024; if($3 ~ /Mi/) m=m+0;
  n=$1;
  split(n,p,"-");
  key=p[1];
  for(i=2;i<=3 && i<=NF && p[i]!="";i++) key=key"-"p[i];
  t[key]+=m; c[key]++
}
END {
  for(k in t) printf "%8d %4d %s\n", t[k], c[k], k
}' | sort -rn | head -22 | awk '{printf "  %-34s pods=%-4d mem=%6dMi (%5.1fGi)\n", $3, $2, $1, $1/1024}'
