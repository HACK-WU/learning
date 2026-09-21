#!/usr/bin/env bash
python3 - <<'PYEOF'
import io
p="/mnt/d/projects/learning/consul/00-评审清单.md"
s=io.open(p,encoding='utf-8').read()

row = "- [x] **子教程 · 课 3 性能、容量与调优**（✅ 2026-09-20 交付。**双视角评审 P0=1 已修**：讲义原断言“stale 比 default 快约 0.6ms”，**复验发现该差值落在测量噪声内且顺序不稳定**（复验轮次 `default=6.16 / consistent=6.63 / stale=6.20`，stale 反而更慢），已改为“三种读模式延迟差在噪声内”并同步修正知识点正文、误区条目、一句话记住、自测题 3 与 SVG 图注——**避免学员把噪声当结论**。**额外修正 2 处**：①脚本 `awk '$3'` 取 `raft list-peers` 的 State 列错误（**应为 `$4`**，课 2 脚本是对的，本课误用），致 follower 提取为空；②`pkill -f 'consul agent'` **会杀掉自身 shell**（该命令行本身包含匹配字符串），改用 `pgrep -x consul`，已写入讲义本机适配备忘。**终验 6 组断言全过**：512/513KB 边界、320/384KB 事务边界、串行<并发<批量（7.2x/48.5x）、三读模式极差<3ms、consistent 返回新值、raft index 可解析且 last>=applied。⚠️ 主 agent 内联评审，独立性受限）\n"

note = "> **2026-09-20 课 3 附带记录（把噪声当结论，第四次同类问题）**：本课差点写下一个看似精确的错误结论——“stale 快 0.6ms”。两轮实测分别是 `5.44/6.04/6.41` 与 `6.20/6.16/6.63`，**stale 从最快变成最慢**。固化原则：**任何小于 1ms 的性能差异，必须多轮复测确认顺序稳定后才能写成结论**；不稳定就写“在噪声内”。这与课 2“复验失败先归类”是同一条铁律的两个面——**先核验，再下结论**。\n\n"

anchor = "> **2026-09-20 课 2 附带记录（区分脚本 bug 与真实缺陷，第三次遇到）**"
assert anchor in s, "锚点未找到"
s = s.replace(anchor, row + "\n" + note + anchor, 1)
io.open(p,'w',encoding='utf-8').write(s)
print("已追加课 3 评审记录")
PYEOF
