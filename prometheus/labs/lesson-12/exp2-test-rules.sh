#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
mkdir -p $D/rules
PT="docker run --rm -v $D/rules:/r --entrypoint promtool prom/prometheus:v3.14.0"

# 被测规则：磁盘 6 小时内将满
cat > $D/rules/disk.yml <<'YML'
groups:
  - name: disk
    rules:
      - alert: DiskWillFillIn6h
        expr: predict_linear(node_filesystem_free_bytes[1h], 6*3600) < 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "disk will fill in 6h"
YML

# 单测：注入 1 小时下降趋势样本，验证 6 小时后是否会触发
cat > $D/rules/disk_test.yml <<'YML'
rule_files:
  - disk.yml
evaluation_interval: 1m
tests:
  - interval: 1m
    input_series:
      # 从 100GB 每分钟掉 1GB，共 60 个点（覆盖 1h 窗口）
      - series: 'node_filesystem_free_bytes{mountpoint="/"}'
        values: '100000000000-1000000000x59'
    alert_rule_test:
      # 期望：5m for 之后触发
      - eval_time: 10m
        alertname: DiskWillFillIn6h
        exp_alerts:
          - exp_labels:
              severity: warning
              mountpoint: "/"
            exp_annotations:
              summary: "disk will fill in 6h"
YML

echo "===== [1] 规则语法检查 ====="
$PT check rules /r/disk.yml 2>&1; echo "exit=$?"
echo
echo "===== [2] 规则单测 ====="
$PT test rules /r/disk_test.yml 2>&1; echo "exit=$?"
