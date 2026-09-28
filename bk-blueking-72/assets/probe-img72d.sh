#!/usr/bin/env bash
echo "=== 用正确拼接实测拉取真实 7.2 镜像 ==="
for img in \
  "hub.bktencent.com/blueking/cmdb_adminserver:v2.0.0" \
  "hub.bktencent.com/blueking/cmdb_coreservice:v2.0.0" ; do
  echo "--- $img ---"
  timeout 300 docker pull "$img" >/tmp/p72b.log 2>&1 \
    && echo "PULL OK" || { echo "PULL FAILED"; tail -4 /tmp/p72b.log; }
done

echo ""
echo "=== 复核 chart 里 tag 的真实值 ==="
grep -A3 'repository: blueking/cmdb_adminserver' /tmp/cmdbchart/bk-cmdb/values.yaml 2>/dev/null | head -6
grep -E '^ *tag:' /tmp/cmdbchart/bk-cmdb/values.yaml 2>/dev/null | sort -u | head -5
