# Kubernetes Python Client 网页索引

> 起始 URL：https://github.com/kubernetes-client/python
> 生成日期：2026-09-21 · 范围（scope）：GitHub 仓库（README / devel / examples）+ 官方 client-libraries 页 + PyPI · 条目数：78 · 一次性快照
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL（带锚点直达）

## 这个站的特殊性（先读）

**本库没有独立文档站**：`kubernetes-client.github.io/python/`、`kubernetes-python.readthedocs.io` 均已 404。
权威源是 **GitHub 仓库本身**——README（安装/兼容矩阵/最小示例）+ `devel/`（专题说明）+ `examples/`（可运行样例）+ `kubernetes/docs/`（自动生成的 API 参考，911 个 md）。
所以本索引不是传统 sitemap 产物，而是**按仓库实际文件树人工编制的路由表**（采集自浅克隆 `master` 分支，HEAD `aa8f73b`）。

**「仓库文档」与「已发布版本」的时差**：本索引抓的是 `master`（未发布）。本机集群是 **k8s v1.34**，按 README 兼容矩阵应装 **client 34.y.z**（对应 k8s 1.34 为 ✓）。
master 上的内容可能超前于 34.1.0 → **写讲义时涉及版本号、新 API、行为变更的，必须以 PyPI 上实际安装的版本为准，master 只作理解用**。

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建

## 版本对应速查（README 兼容矩阵，节选）

| client 版本 | 完全匹配（✓） | 本机 k8s 1.34 下的语义 |
|-------------|----------------|------------------------|
| 33.y.z | k8s 1.33 | `+-` 集群有客户端用不到的新 API |
| **34.y.z** | **k8s 1.34** | **✓ 本机应装此版本** |
| 35.y.z / 36.y.z | k8s 1.35 / 1.36 | `+-` 客户端有集群没有的新对象 |

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 装库、跑第一个 list pods、看 asyncio 与 watch 最小示例 | [README.md](https://github.com/kubernetes-client/python#readme) | start |
| 确认该装哪个 client 版本（兼容矩阵） | [README · Compatibility](https://github.com/kubernetes-client/python#compatibility) | start |
| 搞清四种 patch 的区别与 content_type 怎么写 | [devel/patch_types.md](https://github.com/kubernetes-client/python/blob/master/devel/patch_types.md) | devel |
| 搞清 watch 的 `timeout_seconds` 与 `_request_timeout` | [examples/watch/timeout-settings.md](https://github.com/kubernetes-client/python/blob/master/examples/watch/timeout-settings.md) | examples |
| 打开调试日志看客户端实际发了什么请求 | [devel/debug_logging.md](https://github.com/kubernetes-client/python/blob/master/devel/debug_logging.md) | devel |
| 在 Pod 内用 SA token 访问 API（in-cluster） | [examples/in_cluster_config.py](https://github.com/kubernetes-client/python/blob/master/examples/in_cluster_config.py) | examples |
| 用动态客户端操作 CRD / 未知类型 | [examples/dynamic-client/](https://github.com/kubernetes-client/python/tree/master/examples/dynamic-client) | examples |
| 查某个 API 类有哪些方法、参数怎么传 | [kubernetes/docs/](https://github.com/kubernetes-client/python/tree/master/kubernetes/docs) | reference |
| 官方对各语言客户端的定位与选型 | [Client Libraries](https://kubernetes.io/docs/reference/using-api/client-libraries/) | official |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| start | [topics/start.md](./topics/start.md) | 8 | README、安装、兼容矩阵、PyPI、贡献与变更 |
| examples | [topics/examples.md](./topics/examples.md) | 42 | 官方可运行示例：配置加载、CRUD、patch、watch、exec/port-forward、动态客户端、多集群 |
| devel | [topics/devel.md](./topics/devel.md) | 9 | 仓库内专题说明：patch 类型、调试日志、发布、统计 |
| reference | [topics/reference.md](./topics/reference.md) | 19 | 生成的 API 参考入口、常用 Api 类、官方 client-libraries 页 |

## 与其他索引的关系

- 本索引只管 **Python 客户端库**；k8s 概念/任务/运维文档查 [k8s 主索引](../INDEX.md)（slug `k8s`，333 条）
- 命令类细节优先 `kubectl explain` / `kubectl --help`，比 fetch 文档快
- **库行为以本机实测为准**：本索引解决"去哪一页"，不解决"这个版本实际行为如何"——讲义结论必须跑通再写
