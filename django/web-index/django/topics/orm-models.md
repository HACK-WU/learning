# ORM 与模型层（Django Docs · 共 18 条）

> 范围：/en/6.1（排除 /releases/）· 生成日期：2026-09-16
> 主题：模型定义、字段、查询集、表达式、索引约束、数据库后端与迁移

| 我要… | 去哪一页 | 关键词 |
|-------|----------|--------|
| 查模型层参考的总入口与章节导航 | [Models 参考](https://docs.djangoproject.com/en/6.1/ref/models/) | model、模型、ORM 总览 |
| 查 Model 类本身有哪些方法与属性 | [Model class](https://docs.djangoproject.com/en/6.1/ref/models/class/) | Model 类、save、pk、实例方法 |
| 在查询里写 if/else 条件逻辑（Case/When） | [Conditional expressions](https://docs.djangoproject.com/en/6.1/ref/models/conditional-expressions/) | Case、When、条件表达式 |
| 定义唯一约束、检查约束、排他约束 | [Constraints](https://docs.djangoproject.com/en/6.1/ref/models/constraints/) | UniqueConstraint、CheckConstraint、约束 |
| 在查询里调用数据库内置函数 | [Database functions](https://docs.djangoproject.com/en/6.1/ref/models/database-functions/) | Coalesce、Greatest、Cast、函数 |
| 用 F() 表达式做原子更新、写子查询 | [Query expressions](https://docs.djangoproject.com/en/6.1/ref/models/expressions/) | F()、Func、Subquery、OuterRef |
| 查所有字段类型及其参数（null/blank/db_index 等） | [Model field reference](https://docs.djangoproject.com/en/6.1/ref/models/fields/) | 字段、Field、CharField、db_index |
| 定义单列/多列索引、表达式索引、GIN/GiST | [Model index reference](https://docs.djangoproject.com/en/6.1/ref/models/indexes/) | Index、Meta.indexes、GIN、GiST |
| 查模型实例的增删改方法与生命周期 | [Model instances](https://docs.djangoproject.com/en/6.1/ref/models/instances/) | 实例、save、delete、refresh_from_db |
| 查字段查找（lookup）清单并注册自定义查找 | [Lookups](https://docs.djangoproject.com/en/6.1/ref/models/lookups/) | lookup、__contains、自定义查找 |
| 用 `_meta` API 动态取模型字段与元信息 | [Model _meta API](https://docs.djangoproject.com/en/6.1/ref/models/meta/) | _meta、反射、元信息、get_field |
| 查 Meta 有哪些可配选项 | [Model Meta options](https://docs.djangoproject.com/en/6.1/ref/models/options/) | Meta、ordering、db_table、constraints |
| 查 QuerySet 全部方法与惰性求值规则 | [QuerySet API](https://docs.djangoproject.com/en/6.1/ref/models/querysets/) | QuerySet、filter、annotate、惰性 |
| 查外键/多对多反向关联怎么用 | [Related objects](https://docs.djangoproject.com/en/6.1/ref/models/relations/) | related_name、反向关联、_set |
| 写或查字段级/模型级校验器 | [Validators](https://docs.djangoproject.com/en/6.1/ref/validators/) | validator、校验、validate |
| 查各数据库后端的差异、限制与连接参数 | [Databases](https://docs.djangoproject.com/en/6.1/ref/databases/) | 后端、PostgreSQL、MySQL、SQLite、连接 |
| 写自定义 migration 操作（如建索引、跑数据） | [Migration operations](https://docs.djangoproject.com/en/6.1/ref/migration-operations/) | RunPython、RunSQL、迁移操作 |
| 绕过模型层直接改表结构 | [SchemaEditor](https://docs.djangoproject.com/en/6.1/ref/schema-editor/) | SchemaEditor、DDL、建表、加列 |
