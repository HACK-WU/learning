#!/usr/bin/env bash
echo "=== 1. 取 bk-cmdb chart 的 values，找真实镜像地址 ==="
cd /tmp && rm -rf cmdbchart && mkdir cmdbchart && cd cmdbchart
timeout 60 curl -sS -k -O "https://hub.bktencent.com/chartrepo/blueking/charts/bk-cmdb-3.14.8-beta1.tgz" 2>&1 \
  && tar xzf bk-cmdb-3.14.8-beta1.tgz 2>/dev/null && echo "chart 下载解压 OK" || echo "chart 下载失败"

if [ -d bk-cmdb ]; then
  echo ""
  echo "=== 2. chart 内镜像地址 ==="
  grep -rhoE 'repository: *[^ ]+' bk-cmdb/values.yaml 2>/dev/null | sort -u | head -8
  grep -rhoE 'image: *[^ ]+' bk-cmdb/values.yaml 2>/dev/null | sort -u | head -8
fi

echo ""
echo "=== 3. 实测拉取一个7.2真实镜像 (关键验证) ==="
# 从已探测到的 registry 拉一个存在的镜像做连通性验证
timeout 200 docker pull hub.bktencent.com/blueking/bk-cmdb-coreservice:3.14.8-beta1 >/tmp/cmdbpull.log 2>&1 \
  && echo "PULL OK" || { echo "PULL FAILED:"; tail -5 /tmp/cmdbpull.log; }
