# 课 4：服务发现与健康检查机制

> ⏳ 本课为骨架，正文将在 Phase 2 展开填充。

## 本课目标

从"用"深入到"懂"：掌握 Consul 服务目录的查询体系、六类健康检查的语义边界、阻塞查询与 watch 的推送机制——这是评估"它能不能接住我的生产场景"的第一层。

## 情节定位

小林开始拆引擎第一站：发现与检查。他要搞清楚" unhealthy 的实例到底多久会被剔除"这类评审会上必被追问的细节。

## 知识点清单

### 知识点 1：catalog 与查询接口

- 关键点：catalog API 与 health API 的分工（目录 vs 健康视图）
- 关键点：`?passing=true` 过滤与标签过滤
- 关键点：prepared query（预定义查询）：故障转移与最近实例路由

### 知识点 2：健康检查类型与语义

- 关键点：六类检查：TTL / HTTP / TCP / gRPC / script / Docker
- 关键点：`deregister_critical_service_after`：critical 多久自动注销
- 关键点：maintenance 模式与检查的粒度（服务级/节点级）

### 知识点 3：阻塞查询与 watch

- 关键点：blocking query 原理（index 参数 + 长轮询）
- 关键点：watch 的触发式订阅与典型用法
- 关键点：与纯轮询对比：延迟、服务器负载、实现复杂度
