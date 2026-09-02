#!/bin/bash
# 结课实战项目 · 修复主从复制认证 + 连通性验证
set -u

echo "===== 1. 为从库 7202 配置复制认证 ====="
# 主库 7201 关闭了 default 用户，从库必须用 appuser 认证才能拉取复制流
redis-cli -p 7202 CONFIG SET masteruser appuser 2>&1 | head -1
redis-cli -p 7202 CONFIG SET masterauth 'AppPass123!' 2>&1 | head -1

echo
echo "===== 2. 用认证账号验证 7201 ====="
echo -n "  default 关闭验证（应报 NOAUTH）: "
redis-cli -p 7201 PING 2>&1 | head -1
echo -n "  appuser 认证后: "
redis-cli -p 7201 --user appuser --pass 'AppPass123!' PING 2>&1 | head -1
echo -n "  readonly 认证后: "
redis-cli -p 7201 --user readonly --pass 'ReadOnly123!' PING 2>&1 | head -1

echo
echo "===== 3. 重新检查复制状态 ====="
redis-cli -p 7202 INFO replication 2>/dev/null | grep -E 'role|master_link_status|master_port' || echo "(未建立)"

echo
echo "===== 4. 验证 ACL 最小权限是否真的生效 ====="
echo -n "  readonly 执行 GET（应 OK）: "
redis-cli -p 7201 --user readonly --pass 'ReadOnly123!' SET probe 1 2>&1 | head -1
echo -n "  readonly 执行 SET（应 NOPERM）: "
redis-cli -p 7201 --user readonly --pass 'ReadOnly123!' SET probe 1 2>&1 | head -1
echo -n "  appuser 执行 KEYS（应 NOPERM）: "
redis-cli -p 7201 --user appuser --pass 'AppPass123!' KEYS '*' 2>&1 | head -1
echo -n "  appuser 执行 FLUSHALL（应 NOPERM）: "
redis-cli -p 7201 --user appuser --pass 'AppPass123!' FLUSHALL 2>&1 | head -1
echo -n "  appuser 正常写入: "
redis-cli -p 7201 --user appuser --pass 'AppPass123!' SET cache:probe ok 2>&1 | head -1

echo
echo "===== 5. 反例实例 7203 的安全现状（出厂默认） ====="
redis-cli -p 7203 ACL LIST 2>&1 | head -5
echo -n "  无密码直接 KEYS: "
redis-cli -p 7203 SET stolen data 2>&1 | head -1
