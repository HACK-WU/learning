# 阶段 2：控制面与数据保护

> **故事章节：不要把生产配置藏在每个服务的代码里。**

本阶段把声明参数、policy、运行时参数和配置文件分层，再把“备份”拆成 definitions 与消息数据两类可验证的恢复对象。

| 课程 | 回答的问题 | 状态 |
|------|------------|------|
| 课 3 | 参数应该写在代码、policy 还是配置文件里？ | ⬜ |
| 课 4 | broker 重建后，哪些东西能恢复，哪些不能？ | ⬜ |

官方入口：[parameters](https://www.rabbitmq.com/docs/parameters) · [policies](https://www.rabbitmq.com/docs/policies) · [definitions](https://www.rabbitmq.com/docs/definitions) · [backup](https://www.rabbitmq.com/docs/backup)
