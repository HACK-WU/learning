#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用 Python 提交告警规则，避开 shell 转义陷阱。"""
import json
import os
import sys
import urllib.request

BASE = "http://localhost:3130"
AUTH = ("admin", "admin")
FUID = os.getenv("FUID", "afxi23vi14lq8c")


def req(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(
        BASE + path, data=data, method=method,
        headers={"Content-Type": "application/json"},
    )
    import base64
    tok = base64.b64encode(b"admin:admin").decode()
    r.add_header("Authorization", "Basic " + tok)
    try:
        with urllib.request.urlopen(r, timeout=20) as resp:
            return resp.status, resp.read().decode()[:400]
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:600]


def make_rule(uid, title, summary, expr):
    return {
        "uid": uid, "title": title, "folderUID": FUID,
        "ruleGroup": "tpl-verify", "orgId": 1, "condition": "C",
        "noDataState": "OK", "execErrState": "Error", "for": "0s",
        "isPaused": False,
        "annotations": {"summary": summary, "description": "模板验证"},
        "labels": {"severity": "critical", "team": "shop", "signal": "tmp"},
        "data": [
            {"refId": "A", "relativeTimeRange": {"from": 300, "to": 0},
             "datasourceUid": "shop-prom",
             "model": {"editorMode": "code", "expr": expr, "instant": False,
                       "intervalMs": 1000, "maxDataPoints": 43200}},
            {"refId": "B", "relativeTimeRange": {"from": 300, "to": 0},
             "datasourceUid": "-100",
             "model": {"type": "reduce", "reducer": "last", "expression": "A"}},
            {"refId": "C", "relativeTimeRange": {"from": 0, "to": 0},
             "datasourceUid": "-100",
             "model": {"type": "threshold", "expression": "B",
                       "conditions": [{"type": "query",
                                       "evaluator": {"type": "gt", "params": [0]}}]}},
        ],
    }


# 三种写法一次性验证
EXPR = 'sum by (route) (rate(shop_requests_total[2m]))'
CASES = [
    ("tmp-a", "[TMP-A] index $labels",
     'route={{ index $labels "route" }} value={{ humanize (index $values "B").Value }}'),
    ("tmp-b", "[TMP-B] 点号 $labels.route",
     'route={{ $labels.route }} value={{ humanize $values.B.Value }}'),
    ("tmp-c", "[TMP-C] 纯文本对照",
     '这是一条纯文本 summary，不含任何模板变量'),
]

if __name__ == "__main__":
    import urllib.error
    for uid, title, summary in CASES:
        st, body = req("POST", "/api/v1/provisioning/alert-rules",
                       make_rule(uid, title, summary, EXPR))
        print(f"{uid}: create={st} {body[:150] if st >= 400 else ''}")
