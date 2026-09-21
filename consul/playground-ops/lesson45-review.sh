#!/usr/bin/env bash
# 课4/课5 讲义评审：每条判定先核验再写入
L4="/mnt/d/projects/learning/consul/子教程/运维专项/lessons/lesson-04-证书与密钥生命周期.md"
L5="/mnt/d/projects/learning/consul/子教程/运维专项/lessons/lesson-05-备份、恢复与灾备演练.md"
D=/tmp/consul-ops

echo "===== 核验 1：课4 引用的 gossip keygen 44 字符 ====="
GK=$(consul keygen)
echo "  keygen 实际长度 = ${#GK}（讲义写 44）  → $([ ${#GK} -eq 44 ] && echo 一致 || echo 不一致)"

echo
echo "===== 核验 2：课4 引用 CA 根 3650 天 ====="
curl -s http://127.0.0.1:8501/v1/connect/ca/roots > $D/tls/v_roots.json 2>&1
python3 -c "
import json,datetime
d=json.load(open('$D/tls/v_roots.json'))
for r in d.get('Roots',[]):
    f='%Y-%m-%dT%H:%M:%SZ'
    a=datetime.datetime.strptime(r['NotBefore'],f); b=datetime.datetime.strptime(r['NotAfter'],f)
    print(f'  实测跨度 = {(b-a).days} 天（讲义写 3650）  → {\"一致\" if (b-a).days==3650 else \"不一致\"}')
"

echo
echo "===== 核验 3：课4 引用 keyring is empty ====="
consul keyring -list 2>&1 | grep -o 'Keyring is empty' | head -1 | sed 's/^/  实测: /'

echo
echo "===== 核验 4：课4 引用 RotationPeriod 默认 2160h ====="
curl -s http://127.0.0.1:8501/v1/connect/ca/configuration | python3 -c "
import sys,json
d=json.load(sys.stdin)
rp=d.get('Config',{}).get('RotationPeriod'); ic=d.get('Config',{}).get('IntermediateCertTTL')
print(f'  实测 RotationPeriod={rp}（讲义写 2160h）')
print(f'  实测 IntermediateCertTTL={ic}（讲义写 8760h）')
"

echo
echo "===== 核验 5：课5 引用 snapshot inspect 的类型清单 ====="
consul snapshot inspect $D/tls/full.snap 2>&1 | grep -E 'ConnectCA|KVS|Register' | sed 's/^/  /'

echo
echo "===== 核验 6：课5 引用快照是 gzip ====="
file $D/tls/full.snap | sed 's/^/  /'

echo
echo "===== 核验 7：课5 引用恢复全量覆盖（after 已被抹）====="
echo "  after = '$(curl -s http://127.0.0.1:8501/v1/kv/lesson5/after?raw 2>/dev/null)'（应为空）"
echo "  marker = '$(curl -s http://127.0.0.1:8501/v1/kv/lesson5/marker?raw 2>/dev/null)'（应为 before-snap）"

echo
echo "===== 核验 8：两课引用的链接是否存在 ====="
B="/mnt/d/projects/learning/consul/子教程/运维专项/lessons"
for f in lesson-03-性能、容量与调优.md lesson-06-监控指标与告警.md; do
  [ -f "$B/$f" ] && echo "  ✅ $f" || echo "  ❌ $f 不存在"
done
for f in "/mnt/d/projects/learning/consul/09-排障速查手册.md" \
         "/mnt/d/projects/learning/consul/stages/4-决策落地/lessons/lesson-11-许可证成本与风险.md" \
         "/mnt/d/projects/learning/consul/stages/3-安全与多机房/lessons/lesson-08-ACL与安全模型.md" \
         "/mnt/d/projects/learning/consul/子教程/运维专项/overview.md"; do
  [ -f "$f" ] && echo "  ✅ $(basename $f)" || echo "  ❌ $(basename $f) 不存在"
done
