#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
mkdir -p $D/cfg
PT="docker run --rm -v $D/cfg:/cfg --entrypoint promtool prom/prometheus:v3.14.0"

# 1) 正确配置
cat > $D/cfg/good.yml <<'YML'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
scrape_configs:
  - job_name: demo
    static_configs:
      - targets: ["localhost:9090"]
YML

# 2) 错误配置：scrape_timeout > scrape_interval（课 11 已实测会导致启动失败）
cat > $D/cfg/bad-timeout.yml <<'YML'
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: demo
    scrape_timeout: 60s
    static_configs:
      - targets: ["localhost:9090"]
YML

# 3) 错误配置：缩进错误（YAML 语法）
cat > $D/cfg/bad-yaml.yml <<'YML'
global:
  scrape_interval: 15s
scrape_configs:
- job_name: demo
   static_configs:
      - targets: ["localhost:9090"]
YML

# 4) 错误配置：relabel 引用不存在的字段
cat > $D/cfg/bad-relabel.yml <<'YML'
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: demo
    static_configs:
      - targets: ["localhost:9090"]
    relabel_configs:
      - source_labels: [__meta_nonexistent__]
        target_label: foo
YML

echo "===== [1] good.yml ====="
$PT check config /cfg/good.yml; echo "exit=$?"
echo
echo "===== [2] bad-timeout.yml (timeout > interval) ====="
$PT check config /cfg/bad-timeout.yml; echo "exit=$?"
echo
echo "===== [3] bad-yaml.yml (缩进) ====="
$PT check config /cfg/bad-yaml.yml; echo "exit=$?"
echo
echo "===== [4] bad-relabel.yml (不存在的元标签) ====="
$PT check config /cfg/bad-relabel.yml; echo "exit=$?"
