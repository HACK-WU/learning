#!/usr/bin/env bash
# 生成按租户拆分的抓取配置与告警规则
# 为什么不用一个 vmagent 抓两个租户？
#   因为 vmagent 的 -remoteWrite.url 是实例级的，一个 vmagent 只能写一个 accountID。
#   真正的租户隔离必须靠「每个租户一个 vmagent」或「写入侧 URL 携带 accountID」。
# 本文件从 prometheus.yml / alerts.yml 渲染出 a、b 两份。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

# ---------- 渲染抓取配置 ----------
for t in a b; do
  if [ "$t" = "a" ]; then
    TARGET="capstone-exporter-a:9100"
    NICE="backend-01"
  else
    TARGET="capstone-exporter-b:9100"
    NICE="web-01"
  fi
  cat > "prometheus-$t.yml" <<EOF
# 由 p00-render.sh 自动生成，请勿手工编辑（改 prometheus.yml 后重跑本脚本）
global:
  scrape_interval: 5s
  scrape_timeout: 4s

scrape_configs:
  - job_name: tenant-$t-app
    metrics_path: /metrics
    static_configs:
      - targets: ["$TARGET"]
        labels:
          tenant: tenant-$t
    # ⚠ 关键区分（课 4 的 relabeling 阶段）：
    #   relabel_configs        —— 作用于「抓谁、怎么抓」的 target 标签
    #                             （__address__ / __meta_* / 静态注入的标签）
    #   metric_relabel_configs —— 作用于「抓回来的指标自带的标签」
    #   user_id 是导出器指标自带的，所以必须写在 metric_relabel_configs 里。
    #   写在 relabel_configs 里不报错，但也不生效 —— 静默失败。
    relabel_configs:
      # 把 target 的 IP:Port 收敛成有语义的实例名
      - source_labels: [__address__]
        target_label: instance
        regex: "$TARGET"
        replacement: "$NICE"

    metric_relabel_configs:
      # 高基数红线：这三类标签绝不该进存储
      # ⚠ 括号不能省！relabel 的 regex 是「隐式全匹配」，
      #   会自动变成 ^(...)$，不写括号时 user_id|request_id|trace_id
      #   会被拆成三个破损分支，一个都匹配不上。
      - action: labeldrop
        regex: "(user_id|request_id|trace_id)"

  - job_name: vmagent-self
    static_configs:
      - targets: ["localhost:8429"]
        labels:
          tenant: platform
EOF
  echo "生成 prometheus-$t.yml"
done

# ---------- 渲染告警规则 ----------
for t in a b; do
  sed "s|%TENANT%|tenant-$t|g" alerts.yml > "alerts-$t.yml"
  echo "生成 alerts-$t.yml"
done

echo "渲染完成"
