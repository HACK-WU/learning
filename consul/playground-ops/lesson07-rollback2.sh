#!/usr/bin/env bash
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
D=/tmp/consul-ops
echo "########## 修正版回滚实验（快照在基线写入【之后】存）##########"
echo
echo "--- 1. 先写基线数据 ---"
curl -s -X PUT -d 'v1-before-upgrade' $CONSUL_HTTP_ADDR/v1/kv/app/version > /dev/null
curl -s -X PUT -d 'existing-service' $CONSUL_HTTP_ADDR/v1/kv/app/oldsvc > /dev/null
echo "  app/version = $(curl -s $CONSUL_HTTP_ADDR/v1/kv/app/version?raw)"
echo "  app/oldsvc  = $(curl -s $CONSUL_HTTP_ADDR/v1/kv/app/oldsvc?raw)"

echo
echo "--- 2. 【基线之后】存快照（这才是正确的升级前快照）---"
consul snapshot save $D/tls/upgrade-baseline.snap 2>&1 | sed 's/^/  /'

echo
echo "--- 3. 模拟升级过程中的数据变更 ---"
curl -s -X PUT -d 'v2-after-upgrade' $CONSUL_HTTP_ADDR/v1/kv/app/version > /dev/null
curl -s -X PUT -d 'new-service-registered-during-upgrade' $CONSUL_HTTP_ADDR/v1/kv/app/newsvc > /dev/null
curl -s -X PUT -d 'migration-artifact' $CONSUL_HTTP_ADDR/v1/kv/app/migration > /dev/null
echo "  app/version  = $(curl -s $CONSUL_HTTP_ADDR/v1/kv/app/version?raw)  (已升到 v2)"
echo "  app/newsvc   = $(curl -s $CONSUL_HTTP_ADDR/v1/kv/app/newsvc?raw)  ← 升级中新增"
echo "  app/migration= $(curl -s $CONSUL_HTTP_ADDR/v1/kv/app/migration?raw)  ← 升级中新增"

echo
echo "--- 4. 升级失败 → 回滚（恢复基线快照）---"
consul snapshot restore $D/tls/upgrade-baseline.snap 2>&1 | sed 's/^/  /'
sleep 4

echo
echo "--- 5. 回滚代价清点（关键判据）---"
V=$(curl -s $CONSUL_HTTP_ADDR/v1/kv/app/version?raw 2>/dev/null)
N=$(curl -s $CONSUL_HTTP_ADDR/v1/kv/app/newsvc?raw 2>/dev/null)
M=$(curl -s $CONSUL_HTTP_ADDR/v1/kv/app/migration?raw 2>/dev/null)
O=$(curl -s $CONSUL_HTTP_ADDR/v1/kv/app/oldsvc?raw 2>/dev/null)
echo "  app/version  = '$V'   (期望 v1-before-upgrade = 回到升级前)"
echo "  app/oldsvc   = '$O'   (期望 existing-service = 老数据还在)"
echo "  app/newsvc   = '$N'   (期望 空 = 升级中新增的被抹掉)"
echo "  app/migration= '$M'   (期望 空 = 升级中新增的被抹掉)"
echo
if [ "$V" = "v1-before-upgrade" ] && [ -z "$N" ] && [ -z "$M" ]; then
  echo "  >>> 结论成立：回滚=回退到过去。老数据回来了，升级期间的新数据【全丢】"
else
  echo "  >>> 需复核：V='$V' N='$N' M='$M'"
fi
