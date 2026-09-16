# Django 官方文档 网页索引

> 起始 URL：https://docs.djangoproject.com/en/6.1/
> 生成日期：2026-09-16 · 范围（scope）：`/en/6.1` 全站，排除 `/releases/` · 条目数：279 · 一次性快照
> 版本基线：本机课程环境实测 **Django 6.1**（与 URL 版本段 6.1 一致）
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL 取细节

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建

## 分区索引

> 分区为**人工归并**（按主题归并 ref/ 与 topics/ 的同名主题），非站点原结构。
> 站点原一级分区：ref 120 / topics 68 / howto 38 / internals 23 / intro 14 / faq 9 / misc 4 / contents 1 / index 1 / glossary 1 = 279

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| orm-models | [topics/orm-models.md](./topics/orm-models.md) | 18 | 模型类、字段、查询集、表达式、索引与约束、校验器、数据库后端、迁移操作、SchemaEditor |
| http-views | [topics/http-views.md](./topics/http-views.md) | 39 | 请求响应、URL 路由、视图、类视图、表单、模板、文件存储、分页、信号、CSRF/CSP |
| contrib | [topics/contrib.md](./topics/contrib.md) | 53 | admin、auth、postgres 专属、GIS、staticfiles、sitemaps、syndication 等 contrib 包 |
| settings-admin | [topics/settings-admin.md](./topics/settings-admin.md) | 10 | settings 全量清单、django-admin/manage.py、checks、日志、异常、utils、应用注册表 |
| topics-db | [topics/topics-db.md](./topics/topics-db.md) | 20 | 数据库主题讲解：查询、聚合、事务、多库、优化、管理器、全文搜索、迁移 |
| topics-http | [topics/topics-http.md](./topics/topics-http.md) | 22 | HTTP 层主题讲解：中间件、会话、URL、视图、上传、类视图、表单、模板 |
| topics-ops | [topics/topics-ops.md](./topics/topics-ops.md) | 26 | 缓存、性能、日志、邮件、安全、异步、i18n、认证、测试、信号处理、安装 |
| howto | [topics/howto.md](./topics/howto.md) | 38 | 部署（WSGI/ASGI/清单）、静态文件、自定义命令/字段/查找/模板标签、数据迁移 |
| intro | [topics/intro.md](./topics/intro.md) | 14 | 官方 polls 教程 8 篇、总览、安装、可复用应用 |
| faq-misc-internals | [topics/faq-misc-internals.md](./topics/faq-misc-internals.md) | 39 | FAQ、设计哲学、术语表、目录总表、贡献者手册、弃用说明、安全报告 |

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 查某个 settings 配置项的含义与默认值 | [Settings](https://docs.djangoproject.com/en/6.1/ref/settings/) | settings-admin |
| 写查询、搞懂 QuerySet 惰性求值 | [QuerySet API](https://docs.djangoproject.com/en/6.1/ref/models/querysets/) | orm-models |
| 搞懂 `select_related` 与 `prefetch_related` 区别 | [数据库访问优化](https://docs.djangoproject.com/en/6.1/topics/db/optimization/) | topics-db |
| 查事务与 `atomic` 用法 | [数据库事务](https://docs.djangoproject.com/en/6.1/topics/db/transactions/) | topics-db |
| 写 migrations、处理冲突 | [Migrations](https://docs.djangoproject.com/en/6.1/topics/migrations/) | topics-db |
| 查索引与约束怎么定义 | [Model 索引参考](https://docs.djangoproject.com/en/6.1/ref/models/indexes/) | orm-models |
| 查类视图该继承哪个基类 | [类视图扁平索引](https://docs.djangoproject.com/en/6.1/ref/class-based-views/flattened-index/) | http-views |
| 查 Cache 框架用法 | [Cache 框架](https://docs.djangoproject.com/en/6.1/topics/cache/) | topics-ops |
| 查 Django 6.1 有哪些弃用 | [Deprecation 时间线](https://docs.djangoproject.com/en/6.1/internals/deprecation/) | faq-misc-internals |
| 部署前要过哪些检查 | [部署检查清单](https://docs.djangoproject.com/en/6.1/howto/deployment/checklist/) | howto |
| 查某个术语的官方定义 | [Glossary](https://docs.djangoproject.com/en/6.1/glossary/) | faq-misc-internals |
| 查测试该用哪个工具 | [Testing tools](https://docs.djangoproject.com/en/6.1/topics/testing/tools/) | topics-ops |
| 查 admin 自定义配置 | [Admin](https://docs.djangoproject.com/en/6.1/ref/contrib/admin/) | contrib |
| 查 ASGI 部署怎么配 | [ASGI 部署](https://docs.djangoproject.com/en/6.1/howto/deployment/asgi/) | howto |

## 相关站点

- DRF 索引（同课程）：[../drf/index.md](../drf/index.md)

## 采集说明

- 来源：sitemap.xml（该站无 llms.txt），抓取脚本退出码 0
- 排除：`/releases/` 版本发布说明 395 条（全站 674 条中的多数，与学习无关）
- 保留 `internals/contributing/*`：整体保留以求完整，其中 `internals/deprecation/` 被课 1 引用
- 中间产物：`temp/web-index-django-full.md`（674 条）、`temp/web-index-django-core.md`（279 条）
- 锚点列已整体省略：本索引绝大多数条目为整页定位，逐条锚点无实际价值
