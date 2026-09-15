# 网页索引登记表（Kubernetes 教程）

> 本教程自建的官方文档索引。**涉及 k8s 的问题，先查对应条目所在的分区/路由表，再 web_fetch 取正文**——不要现场搜链接。
> 与仓库根 `.web-index/`（跨主题共享）**是两套**，本表只服务 Kubernetes 教程。
> 2026-09-15 由仓库根 `.web-index/k8s/` 归位至此（原位置属历史遗留：本索引只服务 k8s 教程，不应登记在跨主题共享表里）。

| 站点 | slug | 起始 URL | 范围 | 条数 | 生成日期 |
|------|------|----------|------|------|----------|
| Kubernetes Docs | k8s | https://kubernetes.io/zh-cn/docs/ | `/zh-cn/docs/`（排除 blog / case-studies / releases / contribute） | 329（分区表加总）／ **333（2026-09-15 复核实际条目行）** | 2026-09-10 |

> ⚠️ **条目数差异说明**（2026-09-15 复核发现，非本次搬迁引入）：
> 原登记 329 条，实际统计表格条目行为 **333** 条（concepts 178 / tasks 109 / setup 22 / reference 24，
> 分区表内声明为 177 / 108 / 21 / 23，**每个分区恰差 1**）。
> 差异来源未确认（可能是生成时计数口径不同，或后续补充过条目），**此处如实记录、不擅自改写原数字**。
> 条目总数不影响使用——按「我要…」列或关键词检索定位即可。

## 入口

- [k8s/index.md](./k8s/index.md) —— 元信息 + 高频直达 + 分区索引
- [k8s/topics/concepts.md](./k8s/topics/concepts.md) —— 概念（177 条）
- [k8s/topics/tasks.md](./k8s/topics/tasks.md) —— 任务（108 条）
- [k8s/topics/setup.md](./k8s/topics/setup.md) —— 部署（21 条）
- [k8s/topics/reference.md](./k8s/topics/reference.md) —— 参考（23 条）

## 使用约定

1. 先查「高频直达」→ 再查分区表 → 最后 web_fetch
2. **事实核查（版本号、新特性、API 变更）时以英文站为权威源**——把 URL 里的 `/zh-cn/` 换成 `/en/` 即可取英文版同名页。中文站更新滞后（sitemap：zh-cn 2026-09-02 / en 2026-09-09）
3. 命令类细节优先用 `kubectl explain` / `kubectl --help`，比 fetch 文档快
4. `reference` 分区已排除 100+ 条 `kubectl/generated/*` 子命令页——**查子命令用 `kubectl --help`，不查文档**
5. 索引是快照：链接大面积失效时整站重跑重建并更新生成日期

## 与本课程的配合

- 三件套中的 [排障速查手册](../09-排障速查手册.md) 解决「症状 → 命令」，本索引解决「概念/细节 → 去哪一页」，二者互补
- 讲义中标注 📄（文档结论，未实测）的内容，可凭本索引回查原文核验
