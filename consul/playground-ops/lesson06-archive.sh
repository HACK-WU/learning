#!/usr/bin/env bash
python3 - <<'PYEOF'
import io,os,re

# 1) 00-学习档案.md 插入台账 #21
p="/mnt/d/projects/learning/consul/00-学习档案.md"
s=io.open(p,encoding='utf-8').read()
anchor="| 20 | **子教程课 3 性能容量调优"
assert anchor in s, "锚点20未找到"
row21 = (
"| 21 | **子教程课 6 监控指标与告警（双重命名 → 告警静默失效）** | deploy | "
"课 2 只发现\"指标恒 0\"未给根因；主线课 11 缺口 #4「谁核验过告警指标的语义」未兑现 | "
"✅ **2026-09-20 已交付**：[lesson-06-监控指标与告警](./子教程/运维专项/lessons/lesson-06-监控指标与告警.md)"
"（含一眼全局图 1 张）。**根因实测**：Consul 2.x 的 Prometheus 端点里**同时存在两套命名**——"
"无前缀的 `consul_autopilot_healthy` / `consul_server_isLeader` / `consul_raft_last_index` **恒为 0（空壳）**，"
"真实值在**带主机名前缀**的同名指标里（`consul_VWYPGWU_PC5_autopilot_healthy = 1`，前缀 = hostname 横杠换下划线）。"
"**实测规模**：两轮 528 条中 268 条恒 0（51%）、610 条中 281 条恒 0（46%）。"
"**核心教学点（修正了常见认知）**：恒 0 指标配告警**不是\"不工作\"，而是两种相反的错误**——"
"写 `== 0` / `< 1` 会**永久误报**（健康时也触发，导致告警疲劳后被静音），写 `> 0` / `== 1` 会**静默失效**"
"（真故障也不响，**最危险**）。故障注入实测：停掉 leader 后无前缀指标**从头到尾都是 0**，"
"带前缀的 `autopilot_healthy` 从 1 降到 0、`members_servers` 从 3 降到 2。"
"**三步核验在 Consul 上的适配**：HELP 行**仅重复指标名**（不像 JMX Exporter 带 attribute=Count/Value），"
"拿不到语义 → 第 1 步（值域）与第 3 步（连续采样）更关键，三步不能省成两步。"
"**可用指标实测**：`server_isLeader` 求和=1（可信）、`members_servers`=3、`runtime_num_goroutines` 116~197；"
"FSM 落后差值**本机恒为 0**（无压力），阈值 100 已标注为**占位值非实测结论**。"
"**终验 9 组断言全过**。评审修正 2 处：恒 0 占比由 51% 改为 46%~51% 区间；"
"第二幕\"JSON 落后于 CLI\"补注终验时两者完全一致（均为 26），明确**只有 Prometheus 无前缀名有问题** | ✅ |\n\n"
)
s=s.replace(anchor, row21+anchor, 1)
io.open(p,'w',encoding='utf-8').write(s)
print("1) 台账 #21 已插入")

# 2) 00-评审清单.md 追加
p2="/mnt/d/projects/learning/consul/00-评审清单.md"
s2=io.open(p2,encoding='utf-8').read()
row = "- [x] **子教程 · 课 6 监控指标与告警**（✅ 2026-09-20 交付。**双视角评审 P0=0，2 处数字修正**：①恒 0 占比原写 51%（单轮），终验复测得 46%，已改为**两轮区间 46%~51%**；②第二幕原表述\"JSON 落后于 CLI\"易误导为 JSON 也不可信，终验复测两者**完全一致（均为 26）**，已补注明确**只有 Prometheus 无前缀名有问题**。**实测发现（本课核心）**：Consul 2.x Prometheus 端点存在**双重命名**——无前缀指标恒 0 是空壳，真值在带 hostname 前缀的同名指标里；**恒 0 指标配告警有两种相反错法**（`==0` 永久误报 / `>0` 静默失效），后者最危险。**故障注入已验证**：停 leader 后无前缀指标纹丝不动，带前缀正确反映。**三步核验在 Consul 上需适配**：HELP 行仅重复指标名、无语义，故第 1、3 步更关键。**终验 9 组断言全过**：两端点 200 / 无前缀恒 0 / 带前缀非 0 / JSON=CLI / 空壳 vs 真值对照 / isLeader 求和=1 / 恒 0 占比区间 / API 兜底 Healthy / HELP 行数>100。⚠️ 主 agent 内联评审，独立性受限）\n"
note = "> **2026-09-20 课 6 附带记录（\"不工作\"与\"错工作\"是两回事）**：前几课固化的是\"先核验再下结论\"，本课遇到它的一个变体——**核验不能只验\"它有没有在动\"，还要验\"它动的方向对不对\"**。恒 0 指标同样\"没在动\"，`==0` 和 `>0` 两种写法都能配上去且都能跑，但一个天天误报、一个永不告警。**固化**：性能/监控类告警，**配完必须注入一次真实故障验证\"故障时会触发\"**，否则等同于没配。\n\n"
a2 = "> **2026-09-20 课 3 附带记录（把噪声当结论，第四次同类问题）**"
assert a2 in s2
s2 = s2.replace(a2, row + "\n" + note + a2, 1)
io.open(p2,'w',encoding='utf-8').write(s2)
print("2) 评审清单已追加")

# 3) 02-课程目录.md 加课6
p3="/mnt/d/projects/learning/consul/02-课程目录.md"
s3=io.open(p3,encoding='utf-8').read()
a3="  - [课 3 性能、容量与调优](./子教程/运维专项/lessons/lesson-03-性能、容量与调优.md)"
assert a3 in s3
s3=s3.replace(a3, a3+"\n  - [课 6 监控指标与告警](./子教程/运维专项/lessons/lesson-06-监控指标与告警.md)（✅ 2026-09-20｜实测：双重命名空壳恒 0 / 静默失效 vs 永久误报 / 三步核验 / 9 组断言）",1)
s3=s3.replace("课 3 ✅（2026-09-20 交付）｜课 4~8 待生成","课 3 ✅｜课 6 ✅（2026-09-20 交付）｜课 4、5、7、8 待生成",1)
io.open(p3,'w',encoding='utf-8').write(s3)
print("3) 课程目录已更新")

# 4) 01-学习路径总览.md
p4="/mnt/d/projects/learning/consul/01-学习路径总览.md"
s4=io.open(p4,encoding='utf-8').read()
s4=s4.replace("**进度：课 3 / 8 已交付**","**进度：课 4 / 8 已交付（课 1、2、3、6）**",1)
old3="[课 3 性能、容量与调优](子教程/运维专项/lessons/lesson-03-性能、容量与调优.md)）"
assert old3 in s4
s4=s4.replace(old3,"[课 3 性能、容量与调优](子教程/运维专项/lessons/lesson-03-性能、容量与调优.md)、[课 6 监控指标与告警](子教程/运维专项/lessons/lesson-06-监控指标与告警.md)）",1)
io.open(p4,'w',encoding='utf-8').write(s4)
print("4) 路径总览已更新")
PYEOF
