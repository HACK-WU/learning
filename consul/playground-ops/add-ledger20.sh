#!/usr/bin/env bash
python3 - <<'PYEOF'
import io
p="/mnt/d/projects/learning/consul/00-学习档案.md"
s=io.open(p,encoding='utf-8').read()
anchor="| 19 | **子教程课 2 集群健康 day-2"
assert anchor in s, "锚点未找到"
row20 = (
"| 20 | **子教程课 3 性能容量调优（两条 413 硬边界 + 42 倍吞吐差）** | deploy | "
"课 2 只解决\"看健不健康\"，性能容量未交付；业务反馈\"变慢\"时缺判断依据 | "
"✅ **2026-09-20 已交付**：[lesson-03-性能、容量与调优](./子教程/运维专项/lessons/lesson-03-性能、容量与调优.md)"
"（含一眼全局图 1 张）。**核心实测**：①**两条硬边界**——单条 value 512KB 过/513KB 拒，"
"事务总大小 320KB 过/384KB 拒（**按总字节非条数**，20×8KB 与 40×8KB 都过、60×8KB 拒），"
"超限回 **413 是主动拒绝，重试无效**；②**吞吐差 42~48 倍**——串行 94~111、并发 675~757、"
"批量事务 4559~4684 条/秒（两轮独立复现），根因是每条串行写都要等一次 fsync+复制确认；"
"③**stale 陈旧窗口约 0.07s**（follower stale index 比 leader 少 1），而**三种读模式延迟差在噪声内**"
"（多轮极差 0.34~1.03ms，复验轮次 stale 反而比 default 慢）；④fsync 单次约 0.11ms"
"（WSL 虚拟盘，不可外推生产）；⑤判瓶颈看 `raft.last_index` 与 `raft.applied_index` 差值。"
"**评审修正 3 处**：①讲义原断言\"stale 快 0.6ms\"，复验发现该差值**落在噪声内且顺序不稳定**，"
"已改为\"收益在噪声内\"并全文同步（含 SVG）；②脚本 `awk '$3'` 取 State 错误（**应为 `$4`**，课 2 是对的），"
"导致 follower 取空；③`pkill -f 'consul agent'` **会杀掉自身 shell**（命令行含该字符串），改用 `pgrep -x consul`。"
"**终验 6 组断言全过** | ✅ |\n\n"
)
s=s.replace(anchor, row20+anchor, 1)
io.open(p,'w',encoding='utf-8').write(s)
print("已插入台账 #20")
import re
for m in re.findall(r'\n\| (\d+) \| \*\*子教程课', s): print("  台账编号:", m)
PYEOF
