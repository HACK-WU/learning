# 课 14　迁移工程：不依赖 model 的迁移

> 📖 情节定位：**纵深（四）** —— 模型描述了"现在的样子"，迁移要处理的是"历史的样子"
> 🎯 本课目标：能手写数据迁移与 SQL 迁移，并让线上变更不掉数据

## 知识点清单

### 知识点 1：数据迁移与历史模型
- 关键点：`RunPython` + `apps.get_model` / **为什么必须用历史模型：直接 import 未来会崩** / 多库下用 `schema_editor.connection.alias` 指定库

### 知识点 2：SQL 迁移与状态解耦
- 关键点：`RunSQL` 建视图/触发器/扩展 / `SeparateDatabaseAndState` 让库改动与 Django 状态解耦 / 自定义 Operation / 可逆性与 `elidable`

### 知识点 3：零停机变更与迁移治理
- 关键点：**加唯一字段的三步走** / `atomic=False` 与 PostgreSQL DDL 事务 / `squashmigrations` 的时机与风险 / 迁移冲突处理

---

（正文待生成）
