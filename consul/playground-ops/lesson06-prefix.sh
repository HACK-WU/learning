#!/usr/bin/env bash
# 核验：主机名前缀是哪来的？能不能去掉？
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501

echo "########## 1. 主机名 vs 前缀 ##########"
echo "  hostname    = $(hostname)"
echo "  hostname -s = $(hostname -s)"
echo "  指标前缀    = VWYPGWU-PC5 → 下划线化 = VWYPGWU_PC5"
echo "  → 前缀就是 hostname（点/横线换成下划线）"

echo
echo "########## 2. telemetry 能否控制这个前缀（prometheus_metrics_prefix）##########"
grep -i 'prefix' /tmp/consul-ops/conf/node1.hcl 2>/dev/null || echo "  当前配置未设 prefix（走默认 consul_）"

echo
echo "########## 3. 验证：加 prometheus_metrics_prefix 后名字会变 ##########"
cat > /tmp/consul-ops/conf/prefix-test.hcl <<'EOF'
telemetry {
  prometheus_metrics_prefix = "csl"
  prometheus_retention_time = "60s"
}
EOF
echo "  已写测试配置（不重启集群，仅说明配置项存在）"

echo
echo "########## 4. 关掉主机名前缀的正确做法 ##########"
echo "  Consul 2.x 默认格式: consul_<hostname>_<metric>"
echo "  可通过 prometheus_metrics_prefix 改\"consul_\"部分，但 hostname 段仍在"
echo "  → 写告警时要么用通配，要么按环境固定 hostname"

echo
echo "########## 5. 用通配写告警（PromQL 实测思路）##########"
echo "  错误写法（恒 0，永不触发）:"
echo "    consul_raft_last_index - consul_raft_applied_index > 100   → 0 - 0 = 0，永不 >100"
echo "  正确写法（匹配带前缀的真实名）:"
echo "    consul_VWYPGWU_PC5_raft_last_index - consul_VWYPGWU_PC5_raft_applied_index > 100"
echo "  或通配:"
echo "    {__name__=~\"consul_.*_raft_last_index\"} - on() {__name__=~\"consul_.*_raft_applied_index\"} > 100"

echo
echo "########## 6. 三步核验第 3 步：连续采样看是否单调 ##########"
for t in 1 2 3 4 5; do
  V=$(curl -s 'http://127.0.0.1:8501/v1/agent/metrics?format=prometheus' | grep -E '^consul_VWYPGWU_PC5_runtime_total_gc_runs ' | awk '{print $2}')
  L=$(curl -s 'http://127.0.0.1:8501/v1/agent/metrics?format=prometheus' | grep -E '^consul_VWYPGWU_PC5_raft_last_index ' | awk '{print $2}')
  echo "  第${t}次: gc_runs=$V  raft_last_index=$L"
  sleep 1
done

echo
echo "########## 7. 对比：哪些是无前缀空壳，哪些是真实指标 ##########"
curl -s 'http://127.0.0.1:8501/v1/agent/metrics?format=prometheus' > /tmp/consul-ops/p2.txt
echo "  同名指标（一个带前缀一个不带）对照:"
for m in autopilot_healthy server_isLeader raft_last_index state_servers; do
  A=$(grep -E "^consul_${m} " /tmp/consul-ops/p2.txt | awk '{print $2}')
  B=$(grep -E "^consul_VWYPGWU_PC5_${m} " /tmp/consul-ops/p2.txt | awk '{print $2}')
  echo "    consul_${m} = ${A:-无}   |   consul_VWYPGWU_PC5_${m} = ${B:-无}"
done
