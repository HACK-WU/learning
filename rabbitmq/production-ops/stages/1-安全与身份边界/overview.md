# 阶段 1：安全与身份边界

> **故事章节：谁能进来，进来以后能做什么？**

主课把 RabbitMQ 跑起来了，但“能连上”不等于“安全”。本阶段从 guest、vhost、权限正则和 TLS 四条边界入手，建立最小权限连接。

| 课程 | 回答的问题 | 状态 |
|------|------------|------|
| 课 1 | 认证、授权和加密分别解决什么问题？ | ✅ |
| 课 2 | 账号、vhost 和权限如何随应用生命周期管理？ | ⬜ |

官方入口：[access-control](https://www.rabbitmq.com/docs/access-control) · [ssl](https://www.rabbitmq.com/docs/ssl) · [vhosts](https://www.rabbitmq.com/docs/vhosts)
