#!/usr/bin/env python3
# 课 12 档案回写 3/4 与 4/4：
#   stages/5-生产落地/README.md  （课 12 标 ✅ + 阶段状态 + 核心结论 + 决策清单勾选 + 伏笔）
#   02-课程目录.md               （课 12 索引链接 + ✅）
#   01-学习路径总览.md           （进度条 + 阶段状态 + 更新时间）
import sys, os, re

ROOT = "/mnt/d/projects/learning/victoriametrics"
DATE = "2026-09-02"
LESSON = "12-备份恢复迁移与选型决策.md"
TITLE = "备份恢复、迁移与选型决策"

def edit(path, pairs, must_have=None):
    if not os.path.exists(path):
        print(f"  [FAIL] 文件不存在：{path}"); sys.exit(1)
    src = open(path, encoding="utf-8").read()
    orig = src
    for old, new in pairs:
        if new in src:
            print(f"  [SKIP] 已是目标态：{old[:40]}...")
            continue
        if old not in src:
            print(f"  [WARN] 未找到：{old[:70]}")
            continue
        src = src.replace(old, new, 1)
        print(f"  [OK] {old[:46]}...")
    if must_have:
        for m in must_have:
            if m not in src:
                print(f"  [FAIL] 缺少预期内容：{m}"); sys.exit(1)
    open(path, "w", encoding="utf-8").write(src)
    print(f"  -> {os.path.basename(path)}: {len(orig)} -> {len(src)} (+{len(src)-len(orig)})\n")
    return src

# ============ 3) 阶段 5 README ============
print("=" * 66)
print("[3] stages/5-生产落地/README.md")
print("=" * 66)
readme = f"{ROOT}/stages/5-生产落地/README.md"

pairs_readme = [
    # 课程清单表
    ("| **课 12** | 备份恢复与迁移 | ⬜ 未开始 |",
     f"| **课 12** | [{TITLE}]({LESSON}) | ✅ 已完成（{DATE}） |"),
    # 必须掌握的知识点：课 12
    ("### 课 12：备份恢复与迁移\n\n- 知识点 1：vmbackup / vmrestore\n- 知识点 2：跨集群数据迁移\n- 知识点 3：灾难恢复演练",
     "### 课 12：备份恢复、迁移与选型决策\n\n- 知识点 1：快照与备份恢复 ✅\n"
     "- 知识点 2：迁移路径 ✅\n"
     "- 知识点 3：选型决策：什么时候不该用 VM ✅\n\n"
     "**核心结论（2026-09-02 实测）**\n\n"
     "1. **快照是硬链接的冻结视图**——快照文件与原始数据同一 inode（`links=3`），建快照 `df` 仅增 **184 KB**；\n"
     "   判断磁盘占用必须用 `df`，`du` 会把硬链接重复计数（实测 `du` 增 54 KB 而 `df` 增 184 KB）。\n"
     "2. **vmbackup 拒绝无快照备份**（`-origin cannot be empty`），是设计而非缺陷。\n"
     "3. **增量备份**：首次 7,169,266 B，第二次仅 **136,362 B（1.9%）**；备份期间 20 次写入全成功，不阻塞服务。\n"
     "4. **迁移实测**：vmctl remote-read 迁 1058 万样本 / 195.4 MB 用时 **5.76 秒**，样本层面幂等可安全重跑。\n"
     "5. **删除是墓碑机制**：`delete_series` 返 204 且日志确认 `Deleted 20000 series`，但删 5 万条后磁盘\n"
     "   **反增 2,348 KB**、`/series/count` 不降——**不可逆、无回收站**，删除前必须确认备份时间点早于删除。\n"
     "6. **RTO / RPO 实测**：RTO = **2,548 ms**（纯 vmrestore 1,126 ms）；RPO 由备份频率决定，\n"
     "   实测灾后写入的 500 条数据全部丢失。"),
    # 决策清单勾选
    ("- [ ] 备份频率与保留策略怎么定",
     "- [x] 备份频率与保留策略怎么定：按可容忍 RPO 定；本环境 7 MB/2.76 秒可高频执行；快照不宜长期保留（阻止空间回收）"),
    ("- [ ] 迁移到新集群的步骤与回滚方案",
     "- [x] 迁移到新集群的步骤与回滚方案：Prometheus 存活用 `remote-read`，停机窗口用 `prometheus`，VM 间用 `vm-native`；迁移幂等，中断可重跑"),
    # 待解伏笔
    ("- **多集群之间怎么迁移数据？** → 课 12 vmbackup / vmrestore\n- **灾难恢复的 RTO / RPO 怎么定？** → 课 12 备份策略",
     "- ~~**多集群之间怎么迁移数据？**~~ → ✅ 课 12 已解答：vmctl 支持 8 种源，VM 间用 `vm-native`，实测 1058 万样本 5.76 秒\n"
     "- ~~**灾难恢复的 RTO / RPO 怎么定？**~~ → ✅ 课 12 已解答：RTO 实测 2,548 ms，RPO 由备份频率决定（实测灾后 500 条全丢）\n\n"
     "**本课新产生的未闭环项**\n\n"
     "- 快照长期保留对空间回收的定量影响（本课仅定性说明）\n"
     "- vm-native 跨租户迁移未跑通（`--vm-native-dst-account-id` 组合下无数据落地）\n"
     "- 删除后后台合并触发空间回收的确切时机（实测等 60 秒未见回收）"),
]
edit(readme, pairs_readme,
     must_have=["12-备份恢复迁移与选型决策.md", "RTO = **2,548 ms**"])

# ============ 4a) 课程目录 ============
print("=" * 66)
print("[4a] 02-课程目录.md")
print("=" * 66)
catalog = f"{ROOT}/02-课程目录.md"

pairs_cat = [
    ("- 课 12：备份恢复、迁移与选型决策\n  - 知识点 1：快照与备份恢复\n  - 知识点 2：迁移路径\n  - 知识点 3：选型决策：什么时候不该用 VM",
     f"- 课 12：[{TITLE}](stages/5-生产落地/{LESSON}) ✅\n"
     "  - 知识点 1：快照与备份恢复\n  - 知识点 2：迁移路径\n  - 知识点 3：选型决策：什么时候不该用 VM"),
]
edit(catalog, pairs_cat, must_have=[f"stages/5-生产落地/{LESSON}) ✅"])

# ============ 4b) 学习路径总览 ============
print("=" * 66)
print("[4b] 01-学习路径总览.md")
print("=" * 66)
overview = f"{ROOT}/01-学习路径总览.md"

pairs_ov = [
    ("> 更新时间：2026-09-02（课 11 交付后同步）",
     f"> 更新时间：{DATE}（课 12 交付后同步 · 全课程 12/12 完结）"),
    ("- [ ] 阶段 3：凭什么快、凭什么省（进行中，2026-09-02）— 课 5、课 6、课 7 ✅ 已完成（阶段 3 收官）",
     "- [x] 阶段 3：凭什么快、凭什么省（已完成，2026-09-02）— 课 5、课 6、课 7"),
    ("- [ ] 阶段 4：怎么横向扩展（未开始）\n- [ ] 阶段 5：生产落地（进行中，2026-09-02）— 课 11 已完成，剩课 12",
     "- [x] 阶段 4：怎么横向扩展（已完成，2026-09-02）— 课 8、课 9、课 10\n"
     f"- [x] 阶段 5：生产落地（已完成，{DATE}）— 课 11、课 12"),
    ("**总进度**：12 课中已完成 11 课（课 1–11），35 知识点中已完成 37 个。",
     f"**总进度**：12 课中已完成 **12 课（课 1–12，全部完结）**，35 知识点中已完成 40 个。\n\n"
     f"> 🎉 **全课程已于 {DATE} 完结**。收官课（课 12）交付快照与备份恢复、迁移路径、"
     "选型决策三个知识点，并给出 RTO 2,548 ms 的实测灾难恢复演练。"),
]
edit(overview, pairs_ov, must_have=["12 课中已完成 **12 课"])

print("=" * 66)
print("四处档案回写完成（阶段 README + 课程目录 + 学习路径总览）")
print("=" * 66)
