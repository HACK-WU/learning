#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成项目的主 dashboard JSON。

为什么用脚本生成而不是手写 JSON：
  dashboard JSON 有几百行，手写容易出错且无法复用。
  用脚本生成可以：① 变量定义集中管理 ② 面板布局算出来 ③ 便于版本 diff

产出：dashboards/shop-overview.json
"""
import json
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "dashboards", "shop-overview.json")
os.makedirs(os.path.dirname(OUT), exist_ok=True)

DS_PROM = {"type": "prometheus", "uid": "shop-prom"}
DS_LOKI = {"type": "loki", "uid": "shop-loki"}

# ---------------------------------------------------------------- 变量
templating = {
    "list": [
        {
            "name": "route",
            "label": "接口",
            "type": "query",
            "datasource": DS_PROM,
            "query": "label_values(shop_requests_total, route)",
            "refresh": 1,
            "includeAll": True,
            "multi": True,
            "current": {"text": ["All"], "value": ["$__all"]},
            "options": [],
        },
        {
            "name": "level",
            "label": "日志级别",
            "type": "custom",
            "query": "INFO,DEBUG,WARN,ERROR",
            "current": {"text": "ERROR", "value": "ERROR"},
            "options": [],
            "includeAll": False,
            "multi": False,
        },
    ]
}

# ---------------------------------------------------------------- 面板
def panel(pid, title, ptype, targets, grid, extra=None):
    p = {
        "id": pid,
        "type": ptype,
        "title": title,
        "gridPos": grid,
        "targets": targets,
        "fieldConfig": {"defaults": {}, "overrides": []},
        "options": {},
    }
    if extra:
        p.update(extra)
    return p


panels = []

# --- 第一行：RED 三件套（Rate / Errors / Duration）---
panels.append(panel(
    1, "① 请求速率 QPS（按接口）", "timeseries",
    [{"refId": "A", "datasource": DS_PROM,
      "expr": 'sum(rate(shop_requests_total{route=~"$route"}[$__rate_interval])) by (route)',
      "legendFormat": "{{route}}"}],
    {"h": 8, "w": 8, "x": 0, "y": 0},
    {"fieldConfig": {"defaults": {"unit": "reqps", "custom": {"drawStyle": "line", "fillOpacity": 10}},
                     "overrides": []},
     "description": "Rate：每秒请求数。告警第一眼看这里，判断影响面。"},
))

panels.append(panel(
    2, "② 错误率（按接口）", "timeseries",
    [{"refId": "A", "datasource": DS_PROM,
      "expr": 'sum(rate(shop_requests_total{route=~"$route",status="500"}[$__rate_interval])) by (route)',
      "legendFormat": "{{route}} 5xx"}],
    {"h": 8, "w": 8, "x": 8, "y": 0},
    {"fieldConfig": {"defaults": {"unit": "reqps", "custom": {"drawStyle": "bars", "fillOpacity": 40}},
                     "overrides": []},
     "description": "Errors：每秒错误数。这里涨了说明真出问题了，不是流量大。"},
))

panels.append(panel(
    3, "③ P90 延迟（按接口）", "timeseries",
    [{"refId": "A", "datasource": DS_PROM,
      "expr": 'histogram_quantile(0.9, sum by (le, route) (rate(shop_request_duration_seconds_bucket{route=~"$route"}[$__rate_interval])))',
      "legendFormat": "{{route}} P90"},
     {"refId": "B", "datasource": DS_PROM,
      "expr": 'histogram_quantile(0.5, sum by (le, route) (rate(shop_request_duration_seconds_bucket{route=~"$route"}[$__rate_interval])))',
      "legendFormat": "{{route}} P50"}],
    {"h": 8, "w": 8, "x": 16, "y": 0},
    {"fieldConfig": {"defaults": {"unit": "s", "custom": {"drawStyle": "line"}}, "overrides": []},
     "description": "Duration：P90/P50 延迟。只盯平均值会被长尾骗，必须看分位数。"},
))

# --- 第二行：下钻区 ---
panels.append(panel(
    4, "④ 慢请求的 trace（exemplar，点圆点跳链路）", "timeseries",
    [{"refId": "A", "datasource": DS_PROM,
      "expr": 'histogram_quantile(0.9, sum by (le) (rate(shop_request_duration_seconds_bucket{route=~"$route"}[$__rate_interval])))',
      "legendFormat": "P90",
      # 关键：exemplar=true 才会把 trace_id 圆点画出来
      "exemplar": True}],
    {"h": 9, "w": 12, "x": 0, "y": 8},
    {"fieldConfig": {"defaults": {"unit": "s", "custom": {"drawStyle": "line"}}, "overrides": []},
     "description": "【指标 → 链路】hover 图上的小圆点即可跳到对应 trace。"
                    "前提是数据源配了 exemplarTraceIdDestinations。"},
))

panels.append(panel(
    5, "⑤ 原始日志（含 trace_id，点进去跳链路）", "logs",
    [{"refId": "A", "datasource": DS_LOKI,
      "expr": '{job="shop", service="shop-api"} | json | level="$level" | route=~"$route"',
      "refId": "A"}],
    {"h": 9, "w": 12, "x": 12, "y": 8},
    {"options": {"showLabels": False, "showTime": True, "wrapLogMessage": True,
                 "enableLogDetails": True, "dedupStrategy": "none", "sortOrder": "Descending"},
     "description": "【日志 → 链路】日志行里的 trace_id 是可点击链接，"
                    "由数据源的 derivedFields 配置生成。"},
))

# --- 第三行：定位区 ---
panels.append(panel(
    6, "⑥ 错误分布（哪个接口、哪种错误）", "barchart",
    [{"refId": "A", "datasource": DS_PROM,
      "expr": 'sum by (route, error_type) (increase(shop_errors_total{route=~"$route"}[$__range]))',
      "legendFormat": "{{route}} / {{error_type}}", "format": "table", "instant": True}],
    {"h": 8, "w": 8, "x": 0, "y": 17},
    {"options": {"orientation": "horizontal"},
     "description": "定位：错误集中在哪个接口、哪类错误，决定先修哪个。"},
))

panels.append(panel(
    7, "⑦ 当前并发请求数", "stat",
    [{"refId": "A", "datasource": DS_PROM,
      "expr": 'sum(shop_inflight_requests)', "legendFormat": "并发"}],
    {"h": 8, "w": 4, "x": 8, "y": 17},
    {"fieldConfig": {"defaults": {"unit": "short", "thresholds": {
        "mode": "absolute",
        "steps": [{"color": "green", "value": None},
                  {"color": "yellow", "value": 10},
                  {"color": "red", "value": 30}]}}, "overrides": []}},
))

panels.append(panel(
    8, "⑧ 健康状态总览", "stat",
    [{"refId": "A", "datasource": DS_PROM,
      "expr": 'min(up{job="shop"})', "legendFormat": "应用存活"}],
    {"h": 8, "w": 4, "x": 12, "y": 17},
    {"fieldConfig": {"defaults": {"unit": "short", "mappings": [
        {"type": "value", "options": {"0": {"text": "宕机", "color": "red"},
                                      "1": {"text": "正常", "color": "green"}}}],
        "thresholds": {"mode": "absolute",
                       "steps": [{"color": "red", "value": None},
                                 {"color": "green", "value": 1}]}}, "overrides": []}},
))

panels.append(panel(
    9, "⑨ 主机 CPU（排除干扰：是应用问题还是机器问题）", "timeseries",
    [{"refId": "A", "datasource": DS_PROM,
      "expr": '1 - avg(rate(node_cpu_seconds_total{mode="idle"}[$__rate_interval]))',
      "legendFormat": "CPU 使用率"}],
    {"h": 8, "w": 8, "x": 16, "y": 17},
    {"fieldConfig": {"defaults": {"unit": "percentunit", "custom": {"drawStyle": "line"}},
                     "overrides": []},
     "description": "排除法：如果应用慢但 CPU 正常，问题多半在下游或外部依赖。"},
))

# ---------------------------------------------------------------- 组装
dash = {
    "uid": "shop-overview",
    "title": "Shop 可观测性总览（告警 → 指标 → 日志 → 链路）",
    "tags": ["shop", "capstone"],
    "timezone": "browser",
    "schemaVersion": 41,
    "version": 1,
    "refresh": "10s",
    "time": {"from": "now-15m", "to": "now"},
    "templating": templating,
    "panels": panels,
    # 关键：告警注解，把告警触发时刻画在图上（课 8 的知识点）
    "annotations": {
        "list": [
            {
                "name": "Grafana 告警",
                "enable": True,
                "iconColor": "red",
                "datasource": {"type": "grafana", "uid": "grafana"},
                "type": "dashboard",
            }
        ]
    },
    "description": (
        "实战项目主盘。排查动线：①看 QPS 判断影响面 → ②看错误率确认是故障不是流量 → "
        "③看 P90 定位慢接口 → ④点 exemplar 跳链路 → ⑤看日志找 trace_id → ⑥定位错误类型。"
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(dash, f, ensure_ascii=False, indent=2)
print(f"OK: {os.path.abspath(OUT)}")
print(f"    面板数={len(panels)}")
