#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 11《Kibana 从 Discover 到 Dashboard》演示脚本：批量建 4 个 metric Lens
+ 拼成 2x2 Dashboard。供正文"实操验证"小节调用。

前提:
  - ES + Kibana 9.5.3 跑在 localhost:9200 / 5601
  - 已 source /tmp/elk_env.sh(ES_AUTH / ES_URL / KB_URL)
  - data stream logs-appdemo-default 有 3h 内文档
  - Data View 'app-demo' (title=logs-appdemo-*, timeFieldName=@timestamp)

用法:
  python3 mk-dashboard.py
"""

import json
import os
import sys
import urllib.parse
import urllib.request
from base64 import b64encode

ES_AUTH = os.environ.get("ES_AUTH", "elastic:ELKlearn2026")
ES_URL = os.environ.get("ES_URL", "http://localhost:9200")
KB_URL = os.environ.get("KB_URL", "http://localhost:5601")


def call(method, url, payload=None, base=KB_URL):
    """简易 HTTP 客户端，复用 kibana 需要的 kbn-xsrf 头。"""
    req = urllib.request.Request(base + url, method=method)
    auth = "Basic " + b64encode(ES_AUTH.encode()).decode()
    req.add_header("Authorization", auth)
    req.add_header("kbn-xsrf", "true")
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        req.add_header("Content-Type", "application/json")
        req.data = body
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.status, json.loads(r.read() or b"{}")


def make_lens(title, description, kql_filter):
    """POST 一个 lnsMetric 类型的 Lens saved object。"""
    metric_col = {
        "operationType": "count",
        "sourceField": "___records___",
        "params": {},
    }
    if kql_filter:
        metric_col["filter"] = {"language": "kuery", "query": kql_filter}

    payload = {
        "attributes": {
            "title": title,
            "description": description,
            "visualizationType": "lnsMetric",
            "state": {
                "datasourceStates": {
                    "formBased": {
                        "layers": {
                            "layer1": {
                                "indexPatternId": "app-demo",
                                "columns": {"metric": metric_col},
                                "columnOrder": ["metric"],
                                "incompleteColumns": {},
                            }
                        }
                    },
                    "textBased": {"layers": {}},
                },
                "visualization": {
                    "layerId": "layer1",
                    "layerType": "data",
                    "metricAccessor": "metric",
                },
                "query": {"language": "kuery", "query": ""},
                "filters": [],
            },
        },
        "references": [
            {
                "name": "indexpattern-datasource-layer-layer1",
                "type": "index-pattern",
                "id": "app-demo",
            }
        ],
    }
    return call("POST", "/api/saved_objects/lens", payload)


def make_dashboard(title, lens_ids):
    """把 4 个 lens 拼成 2x2 dashboard。"""
    panels = []
    refs = []
    positions = [(0, 0), (12, 0), (0, 8), (12, 8)]
    for i, (lens_id, (x, y)) in enumerate(zip(lens_ids, positions)):
        ref_name = f"p{i+1}"
        panels.append({
            "version": "8.13.0",
            "type": "lens",
            "gridData": {"x": x, "y": y, "w": 12, "h": 8, "i": ref_name},
            "panelIndex": ref_name,
            "embeddableConfig": {"enhancements": {}},
            "panelRefName": ref_name,
        })
        refs.append({"name": ref_name, "type": "lens", "id": lens_id})

    payload = {
        "attributes": {
            "title": title,
            "description": "用 Kibana 9.5.3 + 600 条演示日志自动生成，1 分钟刷新",
            "panelsJSON": json.dumps(panels, ensure_ascii=False),
            "optionsJSON": json.dumps({
                "useMargins": True,
                "syncColors": True,
                "syncCursor": True,
                "syncTooltips": True,
                "hidePanelTitles": False,
            }),
            "timeRestore": False,
            "timeTo": "now",
            "timeFrom": "now-3h",
            "refreshInterval": {"pause": False, "value": 60000},
            "version": 1,
            "kibanaSavedObjectMeta": {
                "searchSourceJSON": json.dumps({
                    "query": {"language": "kuery", "query": ""},
                    "filter": [],
                })
            },
        },
        "references": refs,
    }
    return call("POST", "/api/saved_objects/dashboard", payload)


def main():
    # 1) 4 个 metric
    lens_specs = [
        ("错误数(3h)",            "log.level: ERROR 的文档数",        "log.level: ERROR"),
        ("5xx请求数(3h)",          "status_code >= 500 的请求数",      "http.response.status_code >= 500"),
        ("支付慢调用(>500ms,3h)",   "payment-service 慢调用数",          "service.name: payment-service and duration_ms > 500"),
        ("全部文档数(3h)",          "近 3 小时文档总数",                None),
    ]
    lens_ids = []
    for title, desc, kql in lens_specs:
        code, body = make_lens(title, desc, kql)
        if code == 200 and "id" in body:
            print(f"  [lens] {title:25s} -> {body['id']}")
            lens_ids.append(body["id"])
        else:
            print(f"  [lens] {title:25s} FAILED http={code} {json.dumps(body, ensure_ascii=False)[:200]}")
            sys.exit(1)

    # 2) 拼成 1 个 dashboard
    code, body = make_dashboard("ELK 演示看板 — 3h 关键指标", lens_ids)
    if code == 200 and "id" in body:
        view_url = f"{KB_URL}/app/dashboards#/view/{body['id']}?_g=(time:(from:now-3h,to:now))"
        print()
        print("  打开:")
        print(f"    {view_url}")
    else:
        print(f"  [dash] FAILED http={code} {json.dumps(body, ensure_ascii=False)[:300]}")
        sys.exit(1)


if __name__ == "__main__":
    main()
