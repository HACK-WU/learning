#!/usr/bin/env bash
D1=http://127.0.1.1:8500
echo "########## WAN 故障检测时长实测（dc2 已于上一脚本停止）##########"
echo "  开始时间: $(date +%T)"
for t in 0 15 30 45 60 75 90; do
  [ $t -gt 0 ] && sleep 15
  S=$(CONSUL_HTTP_ADDR=$D1 consul members -wan 2>/dev/null | awk '$1=="dc2-s1.dc2"{print $3}')
  echo "  T+${t}s  dc2-s1 状态 = ${S:-（已消失）}"
  [ "$S" = "failed" ] && { echo "  >>> 于 T+${t}s 被标记为 failed"; break; }
done

echo
echo "########## 探测超时相关配置（解释原因）##########"
curl -s $D1/v1/agent/self 2>/dev/null | python3 -c "
import sys,json
c=json.load(open('/dev/stdin')) if False else json.load(sys.stdin).get('Config',{})
for k in ['GossipLANGossipInterval','GossipLANProbeInterval','GossipLANProbeTimeout',
          'GossipWANProbeInterval','GossipWANProbeTimeout','GossipWANGossipInterval',
          'ReconnectTimeoutWAN','SerfWANConfig']:
    print(f'  {k:28s} = {c.get(k)}')
" 2>/dev/null || echo "  (配置读取失败)"

echo
echo "########## 从日志找 WAN probe 线索 ##########"
grep -oE 'serf: EventMemberFailed[^"]*|memberlist: Suspect [a-z0-9-]+ has failed|Marking [a-z0-9.-]+ as failed' /tmp/consul-ops/dualdc/log/dc1-s1.log 2>/dev/null | tail -5 | sed 's/^/  /'
