# py-consul 网页索引

> 起始 URL：https://criteo.github.io/py-consul/
> 生成日期：2026-09-22 · 范围（scope）：`criteo.github.io/py-consul/` + `github.com/criteo/py-consul` · 条目数：40 · 一次性快照
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL（带锚点直达）

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建

## 关键事实（备课/使用时先读）

| 项 | 结论 | 出处 |
|---|---|---|
| 维护方 | Criteo，活跃维护（原 `python-consul` 自 2018 停更后 fork 而来） | [仓库首页](https://github.com/criteo/py-consul) |
| Python 要求 | 3.10+ | [仓库首页徽章](https://github.com/criteo/py-consul) |
| 支持 Consul 版本 | 官方声明 1.20 – 1.22（**本机环境为 2.0.2，超出声明范围，须实测**） | [仓库首页 Status 段](https://github.com/criteo/py-consul) |
| 文档主体 | **GitHub Pages Sphinx 站**（非 README；README 仅 64 行） | [文档站](https://criteo.github.io/py-consul/) |
| 仓库 `docs/` 目录 | 仅 `conf.py` / `index.rst` / `Makefile` 空壳，**无正文** | [docs 目录](https://github.com/criteo/py-consul/tree/master/docs) |
| 代理环境注意 | 需设 `http_proxy` / `https_proxy` / `no_proxy` | [仓库首页 Installation 段](https://github.com/criteo/py-consul) |

⚠️ 站点无 `llms.txt` / `sitemap.xml`（GitHub Pages 与 GitHub 仓库均不提供），本索引由文档站导航链接 + 仓库目录树人工提取生成。

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 查 KV 的 get/put/delete 参数与返回值 | [consul.api.kv](https://criteo.github.io/py-consul/consul.api.kv.html) | core-api |
| 写阻塞查询（index/wait）轮询 key | [consul.base.Consul](https://criteo.github.io/py-consul/consul.base.html#consul.base.Consul) | core-api |
| 注册服务、配健康检查、TTL 上报 | [consul.api.agent](https://criteo.github.io/py-consul/consul.api.agent.html) | core-api |
| 服务发现：查健康实例列表 | [consul.api.health](https://criteo.github.io/py-consul/consul.api.health.html) | core-api |
| 建 Session、实现分布式锁 | [consul.api.session](https://criteo.github.io/py-consul/consul.api.session.html) | core-api |
| 查所有异常类型（超时/权限/404） | [consul.exceptions](https://criteo.github.io/py-consul/consul.exceptions.html) | client-infra |
| 用异步客户端（asyncio） | [consul.aio](https://criteo.github.io/py-consul/consul.aio.html) | client-infra |
| 查 token / TLS 怎么传 | [consul.base.Consul](https://criteo.github.io/py-consul/consul.base.html#consul.base.Consul) | client-infra |
| 查版本兼容与最新 release | [Releases / Tags](https://github.com/criteo/py-consul/tags) | repo |
| 查哪些 Consul 端点已实现 | [ENDPOINT_STATUS.md](https://github.com/criteo/py-consul/blob/master/ENDPOINT_STATUS.md) | repo |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| core-api | [topics/core-api.md](./topics/core-api.md) | 13 | KV / Agent / Health / Catalog / Session / Txn —— 子教程课 2-6 主用 |
| api-ext | [topics/api-ext.md](./topics/api-ext.md) | 12 | ACL / Connect / Config / Query / Event / Operator / Snapshot 等扩展端点 |
| client-infra | [topics/client-infra.md](./topics/client-infra.md) | 8 | 客户端基类、异常、回调、Check 构造器、异步 |
| repo | [topics/repo.md](./topics/repo.md) | 7 | 仓库首页、README、CHANGELOG、Releases、ENDPOINT_STATUS、源码与测试 |

## 与既有索引的关系

Consul **服务端**文档（HTTP API 语义、配置、部署）查 [hashicorp-consul](../hashicorp-consul/index.md)。本索引只覆盖 **Python 客户端库**；两者配合：本索引查"怎么用 Python 调"，官方索引查"这个端点在服务端是什么意思"。
