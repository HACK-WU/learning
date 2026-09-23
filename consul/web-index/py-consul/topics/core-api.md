# core-api（py-consul · 共 13 条）

> 范围：criteo.github.io/py-consul/ · 生成日期：2026-09-22
> 覆盖：子教程课 2-6 直接依赖的端点（KV / Agent / Health / Catalog / Session / Txn）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 查 KV 的 `get` / `put` / `delete` 签名与返回结构 | [consul.api.kv](https://criteo.github.io/py-consul/consul.api.kv.html) | #consul.api.kv.KV.get | KV、读写、键值、Value | [KV 事务](https://criteo.github.io/py-consul/consul.api.txn.html) |
| 确认 `kv.get` 返回的 `Value` 是不是 bytes、`data` 为 None 的含义 | [consul.api.kv](https://criteo.github.io/py-consul/consul.api.kv.html) | #consul.api.kv.KV.get | 返回值、bytes、None、空值 | |
| 用 CAS（`cas=` 参数）做原子写 | [consul.api.kv](https://criteo.github.io/py-consul/consul.api.kv.html) | #consul.api.kv.KV.put | CAS、原子写、并发 | |
| 递归删除整个前缀（`recurse=True`） | [consul.api.kv](https://criteo.github.io/py-consul/consul.api.kv.html) | #consul.api.kv.KV.delete | 递归、前缀、批量删 | |
| 注册服务、配健康检查、优雅注销 | [consul.api.agent](https://criteo.github.io/py-consul/consul.api.agent.html) | #consul.api.agent.Agent.Service.register | 服务注册、反注册、deregister | [Service.deregister](#consul-api-agent) |
| 注册/注销一个健康检查 | [consul.api.agent](https://criteo.github.io/py-consul/consul.api.agent.html) | #consul.api.agent.Agent.Check.register | 检查、check、register | |
| TTL 检查上报存活（pass/warn/fail） | [consul.api.agent](https://criteo.github.io/py-consul/consul.api.agent.html) | #consul.api.agent.Agent.Check.ttl_pass | TTL、心跳、pass、warn、fail | [Check 构造器](https://criteo.github.io/py-consul/consul.check.html) |
| 查本 agent 上注册了哪些服务/检查 | [consul.api.agent](https://criteo.github.io/py-consul/consul.api.agent.html) | #consul.api.agent.Agent.services | 本地、agent、列表 | |
| 服务发现：拿健康实例列表 | [consul.api.health](https://criteo.github.io/py-consul/consul.api.health.html) | #consul.api.health.Health.service | 发现、健康、实例、passing | [catalog 版](#consul-api-catalog) |
| 按状态过滤检查（passing/warning/critical） | [consul.api.health](https://criteo.github.io/py-consul/consul.api.health.html) | #consul.api.health.Health.state | 状态过滤、告警、异常实例 | |
| 查节点级/服务级的检查项明细 | [consul.api.health](https://criteo.github.io/py-consul/consul.api.health.html) | #consul.api.health.Health.checks | 检查项、node、明细 | |
| 从 catalog 查服务（不过滤健康状态的注册视图） | [consul.api.catalog](https://criteo.github.io/py-consul/consul.api.catalog.html) | #consul.api.catalog.Catalog.service | catalog、注册视图、节点 | [health 版](#consul-api-health) |
| 建 Session、续约、销毁（分布式锁基础） | [consul.api.session](https://criteo.github.io/py-consul/consul.api.session.html) | #consul.api.session.Session.create | session、锁、renew、TTL | |
| 查 Session 信息 / 列出全部 session | [consul.api.session](https://criteo.github.io/py-consul/consul.api.session.html) | #consul.api.session.Session.info | session 查询、info、list、node | |
| 用事务一次性提交多个 KV 操作 | [consul.api.txn](https://criteo.github.io/py-consul/consul.api.txn.html) | #consul.api.txn.Txn.put | 事务、txn、批量、原子 | |
