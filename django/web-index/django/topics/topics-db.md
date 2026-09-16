# 数据库主题讲解（Django Docs · 共 20 条）

> 范围：/en/6.1（排除 /releases/）· 生成日期：2026-09-16
> 主题：与 orm-models 分区互补——这里讲"为什么这样用"与最佳实践，那边查 API 细节

| 我要… | 去哪一页 | 关键词 |
|-------|----------|--------|
| 查数据库层主题总入口 | [DB 总览](https://docs.djangoproject.com/en/6.1/topics/db/) | 数据库、ORM、总览 |
| 写聚合与 annotate 分组统计 | [Aggregation](https://docs.djangoproject.com/en/6.1/topics/db/aggregation/) | aggregate、annotate、Count、Sum |
| 看官方关系字段示例（多对一/多对多/一对一） | [DB examples](https://docs.djangoproject.com/en/6.1/topics/db/examples/) | 示例、关系、many_to_many |
| 看官方多对多示例模型 | [多对多示例](https://docs.djangoproject.com/en/6.1/topics/db/examples/many_to_many/) | m2m、示例、through |
| 看官方多对一示例模型 | [多对一示例](https://docs.djangoproject.com/en/6.1/topics/db/examples/many_to_one/) | 外键、示例 |
| 看官方一对一示例模型 | [一对一示例](https://docs.djangoproject.com/en/6.1/topics/db/examples/one_to_one/) | OneToOne、示例 |
| 搞懂查询集的获取模式与缓存 | [Fetch modes](https://docs.djangoproject.com/en/6.1/topics/db/fetch-modes/) | 惰性、缓存、迭代 |
| 用 fixture 导入导出测试数据 | [Fixtures](https://docs.djangoproject.com/en/6.1/topics/db/fixtures/) | loaddata、dumpdata、初始数据 |
| 给查询加监控/ instrumentation 钩子 | [Instrumentation](https://docs.djangoproject.com/en/6.1/topics/db/instrumentation/) | 监控、钩子、查询日志 |
| 自定义 Manager 与默认查询集 | [Managers](https://docs.djangoproject.com/en/6.1/topics/db/managers/) | Manager、get_queryset、自定义 |
| 定义模型与字段关系（主题讲解） | [Models](https://docs.djangoproject.com/en/6.1/topics/db/models/) | 模型、字段、关系、Meta |
| 配置多数据库与路由 | [Multi-database](https://docs.djangoproject.com/en/6.1/topics/db/multi-db/) | 多库、router、主从 |
| 定位并消除 N+1 查询 | [优化](https://docs.djangoproject.com/en/6.1/topics/db/optimization/) | N+1、select_related、性能优化 |
| 写查询、跨关系查询与 Q 对象 | [Queries](https://docs.djangoproject.com/en/6.1/topics/db/queries/) | 查询、Q、F、跨关系 |
| 做全文搜索 | [Search](https://docs.djangoproject.com/en/6.1/topics/db/search/) | 全文搜索、搜索 |
| 直接执行原生 SQL | [Raw SQL](https://docs.djangoproject.com/en/6.1/topics/db/sql/) | raw、cursor、原生 SQL |
| 配置表空间 | [Tablespaces](https://docs.djangoproject.com/en/6.1/topics/db/tablespaces/) | tablespace、表空间 |
| 用事务与 atomic 保证一致性 | [Transactions](https://docs.djangoproject.com/en/6.1/topics/db/transactions/) | atomic、事务、隔离级别 |
| 查复合主键支持（Django 新特性） | [Composite PK](https://docs.djangoproject.com/en/6.1/topics/composite-primary-key/) | 复合主键、CompositePrimaryKey |
| 写与回滚 migration | [Migrations](https://docs.djangoproject.com/en/6.1/topics/migrations/) | migration、makemigrations、冲突 |

