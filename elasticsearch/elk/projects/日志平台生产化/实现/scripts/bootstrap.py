#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
结课实战《日志平台生产化》 —— 一键初始化脚本

把"手工点出来的配置"变成可重放的代码。这正是课 12 讲的"配置资产要能备份/重建"的实践：
    Saved Objects 导出是"应急手段"，而把配置写成脚本才是"可重建"的正解。

做四件事：
  ① ES 侧：自定义 ILM 策略 shopapi-7d + 索引模板 logs-shopapi（覆盖内置 logs 模板）
  ② Kibana 侧：Data View  logs-shopapi-*
  ③ Kibana 侧：.index 连接器（basic 许可下唯一能用的落盘类连接器）
  ④ Kibana 侧：.es-query 告警规则"shopapi ERROR 激增"

用法：
    python3 bootstrap.py            # 全量执行（幂等，可重复跑）
    python3 bootstrap.py --check    # 只做体检，不创建
"""
import base64
import json
import sys
import urllib.error
import urllib.request

ES = "http://localhost:9200"
KB = "http://localhost:5601"
AUTH = base64.b64encode(b"elastic:ELKlearn2026").decode()
HDRS = {
    "Authorization": "Basic " + AUTH,
    "Content-Type": "application/json",
    "kbn-xsrf": "true",
}


def call(method, url, body=None, expect=(200, 201, 204)):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=HDRS, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw.strip() else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw}


def ok(label, status, body):
    mark = "✅" if status in (200, 201, 204) else "❌"
    print(f"  {mark} {label}  [HTTP {status}]")
    if status not in (200, 201, 204):
        print("     ", json.dumps(body, ensure_ascii=False)[:400])
    return status in (200, 201, 204)


# ── ① ILM 策略 + 索引模板 ─────────────────────────────────────────────
ILM_POLICY = {
    "policy": {
        "phases": {
            "hot": {
                "actions": {
                    "rollover": {"max_primary_shard_size": "1gb", "max_age": "1d"},
                    "set_priority": {"priority": 100},
                }
            },
            "warm": {
                "min_age": "1d",
                "actions": {
                    "set_priority": {"priority": 50},
                    "forcemerge": {"max_num_segments": 1},
                },
            },
            "delete": {"min_age": "7d", "actions": {"delete": {}}},
        }
    }
}

INDEX_TEMPLATE = {
    "index_patterns": ["logs-shopapi-*"],
    "data_stream": {},
    "priority": 200,          # 高于内置 logs 模板（priority=100），保证我们的设置生效
    # ⚠️ ⚠️ 本项目【最凶险的一个坑】，真跑 + 真查映射才会暴露：
    #    自定义模板一旦 priority 高于内置 logs 模板，就会【顶掉】它——
    #    如果这里不写 composed_of，内置那套 ECS 字段映射（logs@mappings / ecs@mappings）
    #    就全部不生效了。后果是 log.level 之类的字段退回 Elasticsearch 的
    #    【默认动态映射】（text + keyword 子字段），而老一代索引里它是 keyword。
    #    于是同一个 data stream 的不同 generation 出现【字段类型漂移】：
    #        gen1  log.level = keyword                       → term 查询能命中
    #        gen2  log.level = text(+keyword 子字段)          → term "ERROR" 永远命中 0 条
    #    最终现象极具迷惑性：全时段 term ERROR = 118 条，近 5 分钟 = 50 条，
    #    但两者取交集 = 0 —— 于是告警规则窗口里永远是 0，【告警永远不触发】。
    #    这正是"静默失效"类故障：不报错、不告警，只是永远没有数据。
    #    解法：显式继承内置组件模板。
    "composed_of": ["logs@mappings", "logs@settings", "ecs@mappings"],
    "template": {
        "settings": {
            "index.lifecycle.name": "shopapi-7d",
            "index.number_of_shards": 1,
            "index.number_of_replicas": 0,
        }
    },
}

# ── ④ 告警规则参数 ────────────────────────────────────────────────────
ES_QUERY = json.dumps({
    "query": {
        "bool": {
            "filter": [
                {"term": {"log.level": "ERROR"}},
                {"range": {"@timestamp": {"gte": "now-5m"}}},
            ]
        }
    }
})

RULE = {
    "name": "shopapi ERROR 激增",
    "rule_type_id": ".es-query",
    "consumer": "alerts",
    "schedule": {"interval": "1m"},
    "params": {
        "searchType": "esQuery",
        "index": ["logs-shopapi-*"],
        "timeField": "@timestamp",
        "esQuery": ES_QUERY,
        "threshold": [5],
        "thresholdComparator": ">",
        "size": 100,
        "timeWindowSize": 5,
        "timeWindowUnit": "m",
        "groupBy": "all",
        "aggType": "count",
    },
    "actions": [
        {
            "group": "query matched",
            "id": "<CONNECTOR_ID>",          # 运行时替换
            # ⚠️ notify_when 的口径很关键：
            #    onActionGroupChange（默认）—— 只在"动作组发生变化"时通知。
            #       也就是说告警从 untracked → active 时才通知一次，
            #       之后一直 active 就不再重复通知。做演示时会误以为"告警没生效"。
            #    onActiveAlert —— 每次执行只要告警处于 active 就通知。
            #       教学/压测场景更直观，也更容易验证链路。
            "frequency": {"summary": False, "notify_when": "onActiveAlert"},
            "params": {
                "documents": [
                    {
                        # ⚠️ 这里的 mustache 变量【不是随便写的】，实测可用的是下面这 5 个；
                        #    曾经写过 {{alert.status}}，渲染出来是空字符串（本版本拿不到该变量），
                        #    所以"能用哪些变量"要以实际渲染结果为准，不要照着直觉写。
                        "rule": "{{rule.name}}",
                        "group": "{{alert.actionGroup}}",       # 动作组名，ES query 规则固定是 "query matched"
                        "instance": "{{alert.id}}",             # 告警实例 id；groupBy=all 时它就等于动作组名
                        "hit_count": "{{context.value}}",       # 触发的文档数
                        "hit_host": "{{context.hits.0._source.host.name}}",
                        "hit_level": "{{context.hits.0._source.log.level}}",
                        "hit_path": "{{context.hits.0._source.url.path}}",
                    }
                ]
            },
        }
    ],
}


def main():
    check_only = "--check" in sys.argv

    print("\n【体检】")
    s, _ = call("GET", ES + "/_cluster/health")
    ok("Elasticsearch 可达", s, {})
    s, b = call("GET", KB + "/api/status")
    level = b.get("status", {}).get("overall", {}).get("level") if isinstance(b, dict) else None
    print(f"  {'✅' if level == 'available' else '❌'} Kibana 状态 = {level}")
    if level != "available":
        print("     ⚠️ Kibana 未就绪。若是首次启动，先执行： docker compose up -d setup")
        if check_only:
            return
    if check_only:
        return

    print("\n【① ES：ILM 策略 + 索引模板】")
    s, b = call("PUT", ES + "/_ilm/policy/shopapi-7d", ILM_POLICY)
    ok("创建 ILM 策略 shopapi-7d", s, b)
    s, b = call("PUT", ES + "/_index_template/logs-shopapi", INDEX_TEMPLATE)
    ok("创建索引模板 logs-shopapi（priority=200）", s, b)

    print("\n【② Kibana：Data View】")
    # ⚠️ 查重要用 GET /api/data_views（列表接口），返回体里的键是单数 data_view
    s, b = call("GET", KB + "/api/data_views")
    existing = {dv["title"]: dv for dv in b.get("data_view", [])} if isinstance(b, dict) else {}
    if "logs-shopapi-*" in existing:
        print(f"  ✅ Data View logs-shopapi-* 已存在（id={existing['logs-shopapi-*']['id']}）")
    else:
        s, b = call("POST", KB + "/api/data_views/data_view", {
            "data_view": {"title": "logs-shopapi-*", "name": "shopapi 日志",
                          "timeFieldName": "@timestamp", "allowNoIndex": True}
        })
        ok("创建 Data View logs-shopapi-*", s, b)

    print("\n【③ Kibana：.index 连接器】")
    s, b = call("GET", KB + "/api/actions/connectors")
    conn = None
    if isinstance(b, list):
        conn = next((c for c in b if c.get("name") == "capstone-index"), None)
    if conn:
        print(f"  ✅ 连接器 capstone-index 已存在（id={conn['id']}）")
    else:
        s, b = call("POST", KB + "/api/actions/connector", {
            "name": "capstone-index",
            "connector_type_id": ".index",
            "config": {"index": "shopapi-alerts", "refresh": True},
        })
        if ok("创建 .index 连接器 capstone-index", s, b):
            conn = b
    if not conn or "id" not in conn:
        print("  ⚠️ 连接器不可用，跳过告警规则创建")
        return

    print("\n【④ Kibana：告警规则】")
    s, b = call("GET", KB + "/api/alerting/rules/_find?per_page=100")
    rules = b.get("data", []) if isinstance(b, dict) else []
    rule = next((r for r in rules if r.get("name") == RULE["name"]), None)
    payload = json.loads(json.dumps(RULE).replace("<CONNECTOR_ID>", conn["id"]))
    # ⚠️ PUT 的 body 要【自己拼干净的】：把 GET 回来的整个 rule 对象原样 PUT 回去会 400，
    #    因为响应里含 id / revision / created_at / execution_status 等只读字段。
    #    所以这里始终用本地 RULE 定义（+连接器 id）作为唯一事实源。
    if rule:
        # ⚠️ 还有第二个坑：PUT（更新）不接受两个【创建后不可变】的字段，
        #    带上就 400，而且一次只报一个，得踩两次才看清：
        #      [request body.rule_type_id]: Additional properties are not allowed
        #      [request body.consumer]:     Additional properties are not allowed
        #    结论：更新时必须同时摘掉 rule_type_id 与 consumer。
        immutable = {"rule_type_id", "consumer"}
        put_payload = {k: v for k, v in payload.items() if k not in immutable}
        s, b = call("PUT", KB + "/api/alerting/rule/" + rule["id"], put_payload)
        if ok(f"更新规则「{RULE['name']}」（id={rule['id']}）", s, b):
            rule = b
    else:
        s, b = call("POST", KB + "/api/alerting/rule", payload)
        if ok(f"创建规则「{RULE['name']}」", s, b):
            rule = b
    if rule and "params" in rule:
        print(f"  · 阈值 = {rule['params']['thresholdComparator']} {rule['params']['threshold']}"
              f"，窗口 = {rule['params']['timeWindowSize']}{rule['params']['timeWindowUnit']}")

    rid = rule.get("id", "<RULE_ID>") if rule else "<RULE_ID>"
    print("\n完成。下一步验证告警闭环：")
    print("  1) 灌一批 ERROR（时间戳=此刻，才会落进规则的 5 分钟窗口）：")
    print("       python3 gen-logs.py 30 1 --burst")
    print("  2) 等 1~2 分钟（规则 schedule 是 1m），看规则执行状态：")
    print(f"       curl -s -u elastic:ELKlearn2026 {KB}/api/alerting/rule/{rid} | python3 -m json.tool")
    print("  3) 看 .index 连接器落盘的告警文档：")
    print(f"       curl -s -u elastic:ELKlearn2026 '{ES}/shopapi-alerts/_search?pretty'")


if __name__ == "__main__":
    main()
