#!/usr/bin/env bash
cd /tmp && rm -rf cmdbchart && mkdir -p cmdbchart && cd cmdbchart
echo "=== 下载 bk-cmdb chart ==="
timeout 120 curl -sS -k -o bk-cmdb.tgz "https://hub.bktencent.com/chartrepo/blueking/charts/bk-cmdb-3.15.8-beta1.tgz" 2>&1
ls -la bk-cmdb.tgz 2>/dev/null
tar xzf bk-cmdb.tgz 2>/dev/null && echo "解压 OK" || { echo "解压失败"; exit 1; }

echo ""
echo "=== chart 内镜像定义 ==="
grep -rhoE '(repository|image|registry): *[^ ]+' bk-cmdb/values.yaml 2>/dev/null | sort -u | head -10

echo ""
echo "=== 实测拉取真实镜像 ==="
IMG=$(grep -rhoE 'repository: *[^ ]+' bk-cmdb/values.yaml 2>/dev/null | head -1 | awk '{print $2}')
TAG=$(grep -rhoE 'tag: *[^ ]+' bk-cmdb/values.yaml 2>/dev/null | head -1 | awk '{print $2}')
echo "探测到: $IMG : $TAG"
if [ -n "$IMG" ]; then
  timeout 300 docker pull "$IMG:$TAG" >/tmp/p72.log 2>&1 \
    && echo "PULL OK" || { echo "PULL FAILED"; tail -4 /tmp/p72.log; }
fi
