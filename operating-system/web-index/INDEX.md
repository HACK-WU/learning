# web-index · 站点登记表（operating-system / Linux 操作系统基础）

> 本课程的「📚 官方文档」链接与事实核查，取 URL 一律先查本登记表在册索引；索引没有的页面须现场核实后回补。

| 站点 | slug | 状态 | 范围 | 生成日期 |
|------|------|------|------|---------|
| man7.org Linux man-pages | man7.org | ✅ built（精简索引） | 本课程涉及的 syscall(2) / 约定(7) / proc(5) 类 man 页（44 条，全部已核实 200） | 2026-09-16 |
| kernel.org Documentation | — | ❌ not-built | 仅按需 fetch：vm/overcommit-accounting、sched-CFS 等个别文档页 | 2026-09-10 |
| procps-ng / util-linux / sysstat / lsof | — | ❌ not-built | 观测工具以容器内 `man` 页与各上游 repo 为准 | 2026-09-10 |

**使用规则**：

1. 写课时取官方文档 URL，先查 `web-index/man7.org/index.md` 的页面表
2. 索引里没有的页面 → 现场核实（能访问、内容对）后回补一行进索引
3. 索引只解决"去哪一页"，不解决"内容是否过时"——版本 / 行为差异仍由事实核查闸门把关（标 `核查于 YYYY-MM`）
