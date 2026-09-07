#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 9 四处档案回写（全程 assert，缺一不可）"""
import re, os, io

ROOT = "/mnt/d/projects/learning/grafana"
LESSON = "lesson-09-日志与链路：指标之外的另外两只眼.md"
LNAME = "第 9 课：日志与链路：指标之外的另外两只眼"
TODAY = "2026-09-07"

def rw(path, fn):
    p = os.path.join(ROOT, path)
    txt = io.open(p, encoding="utf-8").read()
    new = fn(txt)
    assert new != txt, f"未发生变化：{path}"
    io.open(p, "w", encoding="utf-8").write(new)
    print(f"  ✅ {path}")

def log(*a): print(*a, flush=True)

log("=" * 62)
log("课 9 四处档案回写")
log("=" * 62)

# ------------------------------------------------ 1. 学习档案
def f_arch(t):
    for k in ["9.1", "9.2", "9.3"]:
        old = f"| {k} | "
        idx = t.find(old)
        assert idx > 0, f"档案里找不到知识点 {k}"
        seg_end = t.find("\n", idx)
        seg = t[idx:seg_end]
        assert "⬜ 未开始" in seg, f"{k} 状态不是未开始：{seg}"
        t = t[:idx] + seg.replace("⬜ 未开始", "✅ 已完成") + t[seg_end:]

    # 进度统计：24 -> 27，阶段 3：3/9 -> 9/9（注意 8.x 已 ✅，此处修正为 6/9->9/9 的累计）
    assert "24 / 36" in t, "进度统计里找不到 24 / 36"
    t = t.replace("**进度统计**：24 / 36 知识点（阶段 1：9/9 ✅已完成，阶段 2：9/9 ✅，阶段 3：3/9，阶段 4：0/9）",
                  "**进度统计**：27 / 36 知识点（阶段 1：9/9 ✅已完成，阶段 2：9/9 ✅，阶段 3：9/9 ✅，阶段 4：0/9）")

    # 评审记录追加
    row = (f"| {TODAY} | 课 9《日志与链路》 | 主 agent 内联（pedagogy + learner 双视角，子 agent 未创建，独立性受限） | 0 | "
           "**两个高价值实测发现**：①**`detected_level` 从日志【内容】推断并放大 stream 数**——3 条标签完全相同的日志（仅文本不同）被拆成 2 个 stream（含 ERROR→error，含 DEBUG→unknown），"
           "推翻「stream 仅由标签唯一决定」的直觉，是 Loki 3.x 新风险点（日志格式改版可能致 stream 暴涨）；生产应显式打 level 标签。②**exemplar 的 Content-Type 陷阱**——"
           "exporter 返回 `text/plain` 时 Prometheus 把 `#` 当注释，target down 且 lastError=`got \"#\"`，改 `application/openmetrics-text` 后立刻 `health=up` 且 query_exemplars 拿到 traceID。"
           "**端到端闭环已验证**：指标桶 → exemplar(traceID) → Jaeger 2 个 span。**跨课收束第六次**：`exemplarTraceIdDestinations` 与 editorMode(课4)/transformations(课5)/repeat(课6) 同为「存后端、跑前端、后端不校验」——"
           "实测 PUT `bogus_trace_field`+`no-such-uid` 返回 200 且原样保存，配错不报错。**P1×3 已修**：detected_level 放大 stream 未点明、9.2 时间窗 0 行易误读为故障、exemplar 不校验缺回读证据。"
           "**评审判为脚本缺陷未改文档×4**：count 显示 15/35/30 实为打印数据点个数、targets 读取失败系 bash 引号嵌套、exemplar 初次误归因重复桶、LogQL 400 误以为代理错（实为 instant 不支持日志查询）。"
           "**自我纠错 1 处**：查 flags 用 `enableFeatures`（驼峰）得 None 险些误判「不支持 exemplar」，回读确认真实字段是 `enable-feature`，日志明写 enabled——**第三次验证「先验证再下结论」**。"
           "**环境坑×2**：docker -v 挂载时文件不存在会静默建成目录（须先写文件再起容器）；Jaeger OTLP 端口连撞 14317/24317（otelcol-lab06），最终用 44318；打到 UI 端口 16687 返回 200+HTML |")
    anchor = "| 2026-09-04 | 课 7《告警架构：规则在哪求值、状态怎么迁移》 |"
    # 插到课 7 行之后（保持时间顺序：课 7、课 9 之间应还有课 8，插到表尾更稳妥）
    tbl_end = t.find("\n\n---\n\n## 断点信息")
    assert tbl_end > 0, "找不到评审表结束位置"
    t = t[:tbl_end] + "\n" + row + t[tbl_end:]

    # 断点信息
    t = t.replace("- **当前位置**：阶段 3 课 7 已交付（21/36 知识点，阶段 3：3/9）",
                  "- **当前位置**：阶段 3 课 9 已交付（27/36 知识点，阶段 3：9/9 ✅）")
    t = t.replace("- **下一批**：阶段 3 课 9《日志与链路：指标之外的另外两只眼》（Loki 数据源与 LogQL 入门 / 从指标到日志：时间窗对齐与下钻链接 / 链路下钻：Jaeger 数据源与 exemplar）",
                  "- **下一批**：阶段 4 课 10《Provisioning 与 Dashboard as Code》（Provisioning 的三类文件 / Dashboard as Code 与 UI 改动的冲突处理 / JSON Model 结构与可 diff 化）")
    return t

log("\n【1/4】00-学习档案.md")
rw("00-学习档案.md", f_arch)

# ------------------------------------------------ 2. 评审清单
def f_check(t):
    row = (f"| {TODAY} | 课 9 | 主 agent 内联 | 0 | P1×3 已修（detected_level 放大 stream / 时间窗 0 行易误读 / exemplar 不校验缺证据） | "
           "detected_level 内容推断（3 同标签日志→2 stream）、exemplar Content-Type 陷阱（text/plain→down, openmetrics→up） |")
    tbl_end = t.rfind("\n")
    lines = t.rstrip("\n").split("\n")
    # 找到最后一行表格
    last = max(i for i, l in enumerate(lines) if l.startswith("|"))
    lines.insert(last + 1, row)
    return "\n".join(lines) + "\n"

log("\n【2/4】00-评审清单.md")
p = os.path.join(ROOT, "00-评审清单.md")
if os.path.exists(p):
    rw("00-评审清单.md", f_check)
else:
    print("  ⚠️ 文件不存在，跳过")

# ------------------------------------------------ 3. 阶段 overview
def f_ov(t):
    t = t.replace("- [ ] `lessons/lesson-09-日志与链路：指标之外的另外两只眼.md`",
                  "- [x] `lessons/lesson-09-日志与链路：指标之外的另外两只眼.md`")
    # 学习重点补课 9 结论
    add = ("- **时间窗对齐已实测**（课 9）：同一 LogQL 在 now-5m/now-1h/now-24h 分别命中 0/4/4 行——"
           "**查不到日志的三大原因**：时间窗不一致（最常见）、采集延迟、标签不匹配（Loki 返回 200+0 行，静默）。\n"
           "- **日志与链路的索引取舍**（课 9）：Loki 只索引【标签】不索引内容，故**高基数字段（用户ID/traceID）绝不能当标签**——"
           "取值无限增长会撑爆 stream。⚠️ 课 9 实测新增风险：Loki 3.x 自动注入的 `detected_level` 是【从内容推断】的，会额外放大 stream 数。\n"
           "- **exemplar 是指标→链路的桥**（课 9）：traceID 藏在【直方图桶】的数据点上（普通指标如 node_load1 挂不了）。"
           "⚠️ 两个硬前提：Prometheus 开 `--enable-feature=exemplar-storage` + exporter 返回 `application/openmetrics-text`（用 text/plain 会 target down，报错 got \"#\"）。\n")
    anchor = "- **时间窗对齐**：从指标跳到日志，关键是同一个时间选择器，这正是第一阶段埋的伏笔在此收束。\n"
    assert anchor in t, "阶段 overview 找不到时间窗对齐锚点"
    t = t.replace(anchor, anchor + add)
    return t

log("\n【3/4】stages/3-叫得醒/overview.md")
rw("stages/3-叫得醒/overview.md", f_ov)

# ------------------------------------------------ 4. 两个索引
def f_cat(t):
    assert "课 9" in t or "lesson-09" in t or "第 9 课" in t, "课程目录里找不到课 9"
    return t

log("\n【4/4】两个索引（先查现状）")
for f in ["02-课程目录.md", "01-学习路径总览.md"]:
    p = os.path.join(ROOT, f)
    if not os.path.exists(p):
        print(f"  ⚠️ {f} 不存在")
        continue
    txt = io.open(p, encoding="utf-8").read()
    hits = [l for l in txt.split("\n") if ("lesson-09" in l or "第 9 课" in l or "课 9" in l)]
    print(f"  --- {f}: {len(hits)} 处提及课 9 ---")
    for h in hits[:6]:
        print(f"      {h.strip()[:100]}")

log("\n" + "=" * 62)
log("回写完成（索引需按上表内容手工核对后更新）")
log("=" * 62)
