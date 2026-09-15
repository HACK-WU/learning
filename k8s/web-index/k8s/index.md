# Kubernetes 文档 网页索引

> 起始 URL：https://kubernetes.io/zh-cn/docs/
> 生成日期：2026-09-10 · 范围（scope）：`/zh-cn/docs/`（排除 blog / case-studies / releases / contribute）· 条目数：329 · 一次性快照
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL（带锚点直达）
> 采集自 sitemap（`https://kubernetes.io/zh-cn/sitemap.xml`，站点无 llms.txt）；按用户确认口径裁剪：`concepts` + `tasks` + `setup` 全收，`reference` 只收总览/概念页（排除 100+ 条 `kubectl/generated/*` 子命令页——查子命令直接 `kubectl --help` 更快）

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建

## 时效提醒

中文站更新滞后于英文站（sitemap 最后更新：zh-cn 2026-09-02 / en 2026-09-09）。
**事实核查（版本号、新特性、API 变更）时以英文站为权威源**——把 URL 里的 `/zh-cn/` 换成 `/en/` 即可取英文版同名页。

## 关联索引

- 事实核查闸门：见 `topic-teach` SKILL.md「事实核查闸门」——索引只解决"去哪一页"，不解决"内容是否过时"
- 本地速查：命令类细节优先 `kubectl explain` / `kubectl --help`，比 fetch 文档快

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 讲清 k8s 是什么、解决什么问题 | [Kubernetes 是什么？](https://kubernetes.io/zh-cn/docs/concepts/overview/) | concepts |
| 找控制面与节点组件的组成与职责 | [Kubernetes 组件](https://kubernetes.io/zh-cn/docs/concepts/overview/components/) | concepts |
| 讲声明式 API 与调谐循环 | [控制器](https://kubernetes.io/zh-cn/docs/concepts/architecture/controller/) | concepts |
| 区分 spec 与 status | [理解 Kubernetes 对象](https://kubernetes.io/zh-cn/docs/concepts/overview/working-with-objects/kubernetes-objects/) | concepts |
| 查对象管理三种方式的区别 | [Kubernetes 对象管理](https://kubernetes.io/zh-cn/docs/concepts/overview/working-with-objects/object-management/) | concepts |
| 对比 apply 与 create（声明式 vs 命令式） | [使用配置文件对 Kubernetes 对象进行声明式管理](https://kubernetes.io/zh-cn/docs/tasks/manage-kubernetes-objects/declarative-config/) | tasks |
| 讲 Pod 的生命周期与阶段 | [Pod 的生命周期](https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/pod-lifecycle/) | concepts |
| 讲 Deployment 与副本管理 | [Deployment](https://kubernetes.io/zh-cn/docs/concepts/workloads/controllers/deployment/) | concepts |
| 查标签、选择器、注解怎么写 | [标签和选择算符](https://kubernetes.io/zh-cn/docs/concepts/overview/working-with-objects/labels/) | concepts |
| 查 kubectl 常用命令速记 | [kubectl 快速参考](https://kubernetes.io/zh-cn/docs/reference/kubectl/quick-reference/) | reference |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| concepts | [topics/concepts.md](./topics/concepts.md) | 177 | 架构、工作负载、网络、存储、调度、安全、配置、策略、扩展 |
| tasks | [topics/tasks.md](./topics/tasks.md) | 108 | 对象管理、配置注入、运行应用、集群管理、排障、TLS、网络、GPU |
| setup | [topics/setup.md](./topics/setup.md) | 21 | 学习环境、生产环境、kubeadm、最佳实践与入门教程 |
| reference | [topics/reference.md](./topics/reference.md) | 23 | kubectl 速查、API 概念、命令行工具参考、弃用策略 |
