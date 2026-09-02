#!/bin/bash
# 结课实战项目 · 复制排查 + ACL 验证（用环境变量传密码消除告警，拿到真实返回值）
set -u
export REDISCLI_AUTH='AppPass123!'

echo "===== 1. 从库复制失败日志（真实原因） ====="
grep -iE 'replica|master|auth|denied|error' /tmp/redis-final/7202/redis.log 2>/dev/null | tail -15

echo
echo "===== 2. ACL 验证（环境变量方式，取真实返回） ====="
echo -n "  appuser PING            : "; redis-cli -p 7201 --user appuser PING 2>/dev/null | head -1
echo -n "  readonly SET（应NOPERM）: "; redis-cli -p 7201 --user readonly --pass 'ReadOnly123!' SET probe 1 2>/dev/null | head -1
echo -n "  readonly GET            : "; redis-cli -p 7201 --user readonly --pass 'ReadOnly123!' GET cache:probe 2>/dev/null | head -1
echo -n "  appuser KEYS（应NOPERM）: "; redis-cli -p 7201 --user appuser KEYS '*' 2>/dev/null | head -1
echo -n "  appuser FLUSHALL(应拒绝): "; redis-cli -p 7201 --user appuser FLUSHALL 2>/dev/null | head -1
echo -n "  appuser SET cache:probe : "; redis-cli -p 7201 --user appuser SET cache:probe ok 2>/dev/null | head -1
echo -n "  appuser SET other:probe : "; redis-cli -p 7201 --user appuser SET other:probe bad 2>/dev/null | head -1

echo
echo "===== 3. 反例实例 7203 出厂默认（无任何防护） ====="
echo -n "  无认证写任意 key: "; redis-cli -p 7203 SET attacker:owned 1 2>/dev/null | head -1
echo -n "  无认证执行 FLUSHALL: "; redis-cli -p 7203 FLUSHALL 2>/dev/null | head -1
echo -n "  default 权限串: "; redis-cli -p 7203 ACL LIST 2>/dev/null | head -1

echo
echo "===== 4. 主库 7201 关闭 default 后的默认行为 ====="
echo -n "  无认证 PING: "; redis-cli -p 7201 PING 2>/dev/null | head -1
