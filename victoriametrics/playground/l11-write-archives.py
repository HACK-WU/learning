#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 11 档案回写：学习档案评审记录 + 评审清单"""
import io, sys, re
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

ARCHIVE = r"/mnt/d/projects/learning/victoriametrics/00-学习档案.md"
CHECKLIST = r"/mnt/d/projects/learning/victoriametrics/00-评审清单.md"

L11_ARCHIVE = """| 2026-09-02 | 课 11《vmagent 与 vmalert》 | 主 agent 内联（pedagogy + learner） | **P0×0 / P1×1（已修复）**。核心产出：① **持久化队列零丢失实测成立**——`docker stop` 断开后端 150 秒，`samples_dropped` 全程 0，恢复后 10 秒内 pending 归零、blocks_sent 从 307 续涨到 409。② **发现内存缓冲期**（推翻"数据立即落盘"直觉）：故障前 60 秒 `pending=0` 且队列目录大小纹丝不动（1,243,161 B），第 90 秒才开始增长到 225,586 B——说明 vmagent 崩溃而非后端故障时，队列保护不到。③ **队列文件只追加不截断**：pending 归零后文件仍为 1,238,996 B，重启后不变；`metainfo.json` 显示 `ReaderOffset:783845 < WriterOffset:1238996`，证明靠双偏移续传而非删文件。④ **`maxDiskUsagePerURL` 是软约束**：设 50KB 上限，队列涨到 242KB 仍未丢弃，官方 flag 说明揭示"Buffered data is stored in ~500MB chunks"。⑤ **vmalert 的 remoteWrite.url 路径坑**（与课 10 vmauth 同源）：vmalert 会自动追加 `/api/v1/write`，写成完整路径报 `unsupported path requested: /insert/0/prometheus/api/v1/write/api/v1/write`。⑥ **MetricsQL 可直接写进记录规则**：`lag(up{job="vmsingle"})` 产出 3.018，而同函数在 prom-learn 报 `unknown function`。⑦ **reload 必须查 `vmalert_config_last_reload_successful`**——我因把 label matcher 写进方括号（`lag(up[job="vmsingle"])`）导致 reload 返 200 但指标为 0，且 vmalert 重启直接 fatal。⑧ **vmalert 无 `/healthz` 端点**（返回 `unsupported path`），只有 `/health`。⑨ **兼容性端点表**：`/api/v1/status/flags` 在 vmagent/vmalert 均返 400 而 Prometheus 返 200；vmagent 无查询 API（`/api/v1/query` 返 400）。⑩ **流式聚合连踩三坑**：全量匹配+`keep_metric_names:false` 抹平所有指标名（341 个指标全丢原名）；`keep_metric_names:true` 与多 outputs 冲突直接 fatal；聚合结果**写回同名指标**（tenant 79 的 up 从 1 变成 6/10，是数据污染非优化）。**P1×1 已修**：知识点 3 缺「示例演示」六要素，已补三个示例（端点并排探测 / maxScrapeSize 硬拦截 / 流式聚合基数对照）。Agent A 报「绝不」绝对化表述——经核验为**误报**（原文是操作警告句式"被停的目标绝不能是 vmalert 的数据源"，有实测支撑）。**遗留未闭环×3**：磁盘队列文件长时间运行是否无限增长、`-remoteRead.url` 具体作用场景、流式聚合在 drop_input/keep_input 各种组合下的产物语义（本课只测一种组合） | 通过；P1 已落实 |
"""

L11_CHECKLIST = """| 2026-09-02 | 课 11《vmagent 与 vmalert》 | 主 agent 内联（pedagogy + learner） | 0 | **11 组实验全部真跑，均给出判据**。① 持久化队列零丢失：后端停机 150 秒 dropped 全程 0，恢复后 blocks_sent 307→409。② **内存缓冲期**（推翻直觉）：前 60 秒 pending=0 且目录不增长，90 秒起才落盘。③ 队列文件只追加不截断（metainfo.json 双偏移为证）。④ maxDiskUsagePerURL 是软约束（50KB 上限涨到 242KB 未丢）。⑤ vmalert remoteWrite.url 自动追加 `/api/v1/write` 导致 400——与课 10 vmauth 拼接坑同源。⑥ MetricsQL 可写进记录规则（lag 产出 3.018），Prometheus 对照报 unknown function。⑦ reload 返 200 但 `config_last_reload_successful=0` 是假成功，根因为 MetricsQL 语法错误（label matcher 误写进方括号）且导致重启 fatal。⑧ vmalert 无 `/healthz` 只有 `/health`。⑨ 兼容性端点表：status/flags 两边都 400、vmagent 无查询 API。⑩ 流式聚合三坑：全量匹配抹平指标名、keep_metric_names 与多 outputs 冲突 fatal、产物写回同名指标致 up 从 1 变 6。Agent A 报 P1×1（知识点 3 缺示例演示）——**真缺陷已修复**，补三个示例；另报「绝不」绝对化——经核验为**误报**（操作警告句式，有实测支撑）。Agent B 全部文件引用与链接可达性校验通过（9 个脚本 + 6 个配置文件均真实存在） |
"""

# ---- 学习档案：在评审记录表末尾追加 ----
txt = open(ARCHIVE, encoding='utf-8').read()
if '课 11《vmagent 与 vmalert》' in txt:
    print("[SKIP] 学习档案已含课 11 记录")
else:
    lines = txt.rstrip('\n').split('\n')
    # 找评审记录表最后一行（以 | 开头且在"大纲调整记录"之前）
    idx = None
    for i, l in enumerate(lines):
        if l.startswith('## 大纲调整记录'):
            idx = i
            break
    if idx is None:
        print("[FAIL] 未找到锚点")
        sys.exit(1)
    # 往前找最后一个非空、以 | 开头的行
    j = idx - 1
    while j >= 0 and not lines[j].strip().startswith('|'):
        j -= 1
    lines.insert(j + 1, L11_ARCHIVE.rstrip('\n'))
    open(ARCHIVE, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
    print("[OK] 学习档案已追加课 11 评审记录")

# ---- 评审清单：勾选 + 追加评审记录 ----
txt2 = open(CHECKLIST, encoding='utf-8').read()

old_item = "- [ ] 阶段 5·课 11《vmagent 与 vmalert》 — pedagogy + learner 双视角"
new_item = "- [x] 阶段 5·课 11《vmagent 与 vmalert》 — pedagogy + learner 双视角 — P0=0（2026-09-02）"
if old_item in txt2:
    txt2 = txt2.replace(old_item, new_item)
    print("[OK] 评审清单已勾选课 11")
elif new_item in txt2:
    print("[SKIP] 评审清单课 11 已勾选")
else:
    print("[WARN] 未找到课 11 待评审条目")

if '课 11《vmagent 与 vmalert》' in txt2.split('## 评审记录')[1] if '## 评审记录' in txt2 else False:
    print("[SKIP] 评审记录表已含课 11")
else:
    lines2 = txt2.rstrip('\n').split('\n')
    idx2 = None
    for i, l in enumerate(lines2):
        if l.startswith('### 评审报警真伪判定记录'):
            idx2 = i
            break
    if idx2 is None:
        print("[FAIL] 未找到评审记录表锚点")
        sys.exit(1)
    j2 = idx2 - 1
    while j2 >= 0 and not lines2[j2].strip().startswith('|'):
        j2 -= 1
    lines2.insert(j2 + 1, L11_CHECKLIST.rstrip('\n'))
    open(CHECKLIST, 'w', encoding='utf-8').write('\n'.join(lines2) + '\n')
    print("[OK] 评审清单已追加课 11 评审记录")
