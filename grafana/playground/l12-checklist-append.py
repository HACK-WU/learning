#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import io, sys

p = "/mnt/d/projects/learning/grafana/00-评审清单.md"
txt = io.open(p, encoding="utf-8").read()

row = (
"| 2026-09-07 | 课 12《性能、高可用与升级运维》 | 主 agent 内联（pedagogy + learner 双视角，子 agent 未创建，独立性受限） | 0 | "
"**三个反转直觉（全有实测支撑）**：①**面板数不是瓶颈**——N=1→80（80 倍）耗时 7ms→32ms（仅 4.5 倍），亚线性且绝对值可忽略，面板数是**优先级最低**的排查项；"
"②**时间窗拉长数据反而变少**——1h→7d（168 倍）响应体 9680→4093 字节，因 Grafana 自动放大步长（30s→2h）；"
"③**慢在渲染不在查询**——API 9ms vs PNG 4.9s，**500 倍**。**真开关是 `maxDataPoints`**（面板宽度决定）：100→2000 时响应体 0.98MB→14.3MB（14.5 倍）。"
"**12.2**：SQLite 并发写 10 次全 200，但日志实锤 **`SQLITE_BUSY` 重试至 retry=2、退避 199ms**（锁被重试掩盖，用户无感）；"
"SQLite 硬边界＝**文件无法共享**（`grafana-lab` 无挂载）；换 Postgres 仅改环境变量、应用层零改动（91 表）；"
"**HA 三结论**：配置双向可见、会话默认共享（pg1 cookie 访问 pg2 返 200，**无需配 Redis**）、迁移带锁幂等（`performed=0, skipped=719`）。"
"**12.3（本课最大价值）**：token 明文 `glsa_...` 落库为 32 位哈希 `e34d8990...`，**备份恢复不了明文**（坐实课 11 伏笔）；"
"**降级实验**——12.0.0 开 13.2.1 的库返回 `database: ok` 但 dashboard **404**，且**旧版继续改库**（719→731）；"
"根因 13.x 用 **`resource` 表（unified storage）**，12.x 读老表，**双向不可见**（12.0.0 建的 `old-created`，13.2.1 读也 404）；**回滚＝恢复备份**（实测恢复到 719、dashboard 200）。"
"**P1 已修**：死链 2 条（`../../`→`../../../`，课 2/3 同坑）。"
"**评审判为脚本缺陷未改文档×1**：A3 报「12.2/12.3 缺六要素」，回读 grep 确认**误报**（18 处齐全，awk 区间正则缺陷，课 4/10 同款）。"
"**未实测已标注×4**：告警 HA 去重、12→13 正向迁移、SQLite 并发击穿阈值、完整 SQLite→PG 迁移演练。"
"**课 4 P0 未复发**：代码块外 0 续行。**环境坑×3**：5432 被 `xpert-db-1` 占（改用 5433）；8081 被占（改 8082）；"
"`GF_RENDERING_RENDERER_TOKEN` 用默认值 Grafana **拒绝启动**，renderer 侧须设同名 `AUTH_TOKEN` 否则 401；`gf-render` 须同时接 `l12net`+`grafana-net` 否则查询 8 秒超时 |\n"
)

anchor = "| 2026-09-04 | 大纲评审 |"
idx = txt.find(anchor)
if idx == -1:
    print("ANCHOR NOT FOUND")
    sys.exit(1)
txt = txt[:idx] + row + txt[idx:]
io.open(p, "w", encoding="utf-8").write(txt)
print("OK: 课 12 评审记录已插入评审清单")
