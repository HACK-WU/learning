# ZooKeeper Docs（r3.9.5）网页索引

> 起始 URL：https://zookeeper.apache.org/doc/r3.9.5/
> 生成日期：2026-09-10 · 范围（scope）：/doc/r3.9.5（当前稳定版全量；javadoc/API 参考页未收录） · 条目数：35 · 一次性快照
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL（带锚点直达）

## 怎么用

1. 按「我要…」列定位条目（本站仅 35 页，四个分区即可覆盖）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建（脚本与中间地图见仓库 `temp/`：`build_zookeeper-apache_web_index.py` / `web-index-zookeeper-apache-map.md`）

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 理解 znode 树数据模型与节点类型 | [data-model](https://zookeeper.apache.org/doc/r3.9.5/developer/programmers-guide/data-model/) | developer |
| 理解 Watch 机制（一次性触发语义） | [watches](https://zookeeper.apache.org/doc/r3.9.5/developer/programmers-guide/watches/) | developer |
| 查一致性保证清单（线性读写等） | [consistency-guarantees](https://zookeeper.apache.org/doc/r3.9.5/developer/programmers-guide/consistency-guarantees/) | developer |
| 查官方 Recipes（锁/选主/栅栏的标准做法） | [recipes](https://zookeeper.apache.org/doc/r3.9.5/developer/recipes/) | developer |
| 查 zoo.cfg 全部配置参数 | [configuration-parameters](https://zookeeper.apache.org/doc/r3.9.5/admin-ops/administrators-guide/configuration-parameters/) | admin-ops |
| 理解 quorum 与仲裁规则（几台才够） | [quorums](https://zookeeper.apache.org/doc/r3.9.5/admin-ops/quorums/) | admin-ops |
| 在线动态重配置集群 | [dynamic-reconfiguration](https://zookeeper.apache.org/doc/r3.9.5/admin-ops/dynamic-reconfiguration/) | admin-ops |
| 理解内部实现（ZAB 协议/写路径） | [internals](https://zookeeper.apache.org/doc/r3.9.5/miscellaneous/internals/) | miscellaneous |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| overview | [topics/overview.md](./topics/overview.md) | 3 | 快速上手、文档目录、版本说明 |
| developer | [topics/developer.md](./topics/developer.md) | 14 | 数据模型/会话/Watch/一致性/recipes/ACL |
| admin-ops | [topics/admin-ops.md](./topics/admin-ops.md) | 17 | 部署/配置/仲裁/重配置/监控/快照恢复 |
| miscellaneous | [topics/miscellaneous.md](./topics/miscellaneous.md) | 1 | internals（ZAB） |
