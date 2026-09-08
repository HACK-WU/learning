#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
mkdir -p $D/rules
PT="docker run --rm -v $D/rules:/r --entrypoint promtool prom/prometheus:v3.14.0"

# 同样的规则，但把预期改成"不触发"（与真实行为相反），验证单测是否会 FAIL
cat > $D/rules/disk_test_neg.yml <<'YML'
rule_files:
  - disk.yml
evaluation_interval: 1m
tests:
  - interval: 1m
    input_series:
      - series: 'node_filesystem_free_bytes{mountpoint="/"}'
        values: '100000000000-1000000000x59'
    alert_rule_test:
      - eval_time: 10m
        alertname: DiskWillFillIn6h
        exp_alerts: []          # 故意写错：声称不该触发
YML

echo "===== 反向验证：期望写反，单测应当 FAIL ====="
$PT test rules /r/disk_test_neg.yml 2>&1; echo "exit=$?"
echo
echo "===== 再测一个边界：磁盘充足时不应触发 ====="
cat > $D/rules/disk_test_ok.yml <<'YML'
rule_files:
  - disk.yml
evaluation_interval: 1m
tests:
  - interval: 1m
    input_series:
      - series: 'node_filesystem_free_bytes{mountpoint="/"}'
        values: '100000000000+0x59'    # 恒定，不下降
    alert_rule_test:
      - eval_time: 10m
        alertname: DiskWillFillIn6h
        exp_alerts: []
YML
$PT test rules /r/disk_test_ok.yml 2>&1; echo "exit=$?"
