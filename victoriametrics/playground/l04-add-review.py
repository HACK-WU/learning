#!/usr/bin/env python3
"""往评审清单的评审记录表追加课 4 记录（在「评审报警真伪判定记录」行之前插入）。"""
import io

P = "/mnt/d/projects/learning/victoriametrics/00-评审清单.md"
ANCHOR = "| 2026-09-02 | 评审报警真伪判定记录"

NEW_ROW = (
    "| 2026-09-02 | 课 4《写入协议全家桶与基数治理》 | 主 agent 内联（pedagogy + learner） | 0 | "
    "**实测发现×3**："
    "① **CSV import 静默失败**——四种写法全部返回 HTTP 204，"
    "但 `vm_rows_inserted_total{type=\"csvimport\"}=0`，"
    "`vm_http_request_errors_total` 也是 0，服务端不报错就是不写。"
    "讲义给出「必须用 `sum(vm_rows_inserted_total) by (type)` 验证，不能信 HTTP 状态码」的硬规则。"
    "② **OpenTSDB telnet 与 HTTP 不能共用端口**，同设 4242 导致容器 fatal 启动失败。"
    "③ **InfluxDB 字段名会被拼进指标名**"
    "（`temperature`+`external` → `temperature_external`，连 `value` 也拼），不符合直觉。"
    "**方法论教训 1 条**：初判 `metric_relabel_configs` 未生效，"
    "是因拿「未过滤 job」与「已过滤 job」对比导致基准错误；"
    "改为按 job 拆解后确认 drop 生效（filtered job = 0 条），已作为排查经验写入讲义。"
    "learner 视角：基数治理三层用「生效时机」而非「工具」分类，"
    "避免把查询时聚合误当根治手段 |\n"
)

with io.open(P, "r", encoding="utf-8") as f:
    text = f.read()

if "课 4《写入协议全家桶与基数治理》" in text:
    print("课 4 记录已存在，跳过")
elif ANCHOR in text:
    idx = text.index(ANCHOR)
    text = text[:idx] + NEW_ROW + text[idx:]
    with io.open(P, "w", encoding="utf-8") as f:
        f.write(text)
    print("已追加课 4 评审记录")
else:
    print("未找到锚点行")
