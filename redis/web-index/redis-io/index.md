# Redis Docs 网页索引

> 起始 URL：https://redis.io/docs/latest/
> 生成日期：2026-09-10 · 范围（scope）：官方 llms.txt 精选面（57 条，覆盖核心/命令精选/开发/客户端/集成/运维/AI） · 条目数：57 · 一次性快照
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL（带锚点直达）
> 课程对齐：课程基线 Redis 7.4（自建 OSS）；缓存/数据类型/持久化/分布式锁为主干

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建（脚本与中间地图见仓库 `temp/`：`build_redis-io_web_index.py` / `web-index-redis-io-map.md`）
4. 查任意命令语法：先打开 [Commands index](https://redis.io/docs/latest/commands/)，再进具体命令页（200+ 命令未逐条入表）

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 理解 Redis 数据类型（String/Hash/List/Set/ZSet/Stream） | [data-types](https://redis.io/docs/latest/develop/data-types/index.html.md) | development |
| 查命令总目录（按类目分组） | [commands](https://redis.io/docs/latest/commands/) | commands |
| 理解持久化（RDB vs AOF 与取舍） | [persistence](https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/index.html.md) | operations |
| 查淘汰策略（内存满了删谁） | [eviction](https://redis.io/docs/latest/develop/reference/eviction/index.html.md) | development |
| 分布式锁怎么加才对 | [distributed-locks](https://redis.io/docs/latest/develop/use/patterns/distributed-locks/index.html.md) | development |
| 配 ACL 访问控制 | [acl](https://redis.io/docs/latest/operate/oss_and_stack/management/security/acl/index.html.md) | operations |
| 查 redis.conf 配置项 | [config](https://redis.io/docs/latest/operate/oss_and_stack/management/config/index.html.md) | operations |
| 用 Python（redis-py）客户端 | [redis-py](https://redis.io/docs/latest/develop/clients/redis-py/index.html.md) | clients |
| 用 Streams（消费者组） | [streams](https://redis.io/docs/latest/develop/data-types/streams/index.html.md) | development |
| 用 redis-cli 排障 | [cli](https://redis.io/docs/latest/develop/tools/cli/index.html.md) | development |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| core | [topics/core.md](./topics/core.md) | 3 | 文档首页/API 面/快速上手 |
| commands | [topics/commands.md](./topics/commands.md) | 8 | 命令总目录 + 8 个高频命令 |
| development | [topics/development.md](./topics/development.md) | 13 | 数据类型/搜索/PubSub/Streams/Lua/淘汰/锁 |
| clients | [topics/clients.md](./topics/clients.md) | 6 | Node/Java/Go/.NET/Python 客户端 |
| integrations | [topics/integrations.md](./topics/integrations.md) | 7 | 生态工具/RedisVL/RIOT/RDI/Vercel |
| operations | [topics/operations.md](./topics/operations.md) | 19 | 安装/配置/持久化/ACL/Cloud/RS 运维 |
| ai | [topics/ai.md](./topics/ai.md) | 1 | 向量检索与 RAG 入口 |
