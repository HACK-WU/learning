# 课 1 · 认识 PostgreSQL

> 📍 故事中的位置：主角一行订单——你得先把"家"（数据库）准备好，它才有机会出生

## 本课目标

学完本课后，你能：

1. 用一句话向同事解释「PG 是什么、跟 MySQL / Oracle 有什么本质区别」
2. 在 macOS 上用 Docker 起一个能 psql 连接的 PG 容器
3. 分清 cluster / database / schema / table 的层级关系

## 知识点清单

| 知识点 | 关键点 |
|---|---|
| **1.1 PostgreSQL 是什么** | · 起源（1986 加州伯克利 POSTGRES → 1996 SQL 化 → 现 PG 17） · 定位（开源对象关系型，与 MySQL 的"轻量开源"路线区别） · 特性全景（ACID / JSON / 全文检索 / 地理信息 / 扩展体系） · 与 MySQL / Oracle / SQLite 的对比取舍 |
| **1.2 安装与工具链** | · Docker 起容器方式（推荐；与 docker 课程风格统一） · 三大件：postgresql-server + psql 客户端 + pgcli（增强客户端） · 服务管理（启动 / 停止 / 进入容器执行命令） · 连接字符串格式（`postgres://user:pass@host:port/db`） |
| **1.3 数据库与模式层级** | · cluster（一个 postmaster 进程对应一个） · database（一个 cluster 下多个独立库） · schema（库内的命名空间，类似文件夹） · table（schema 下的实际表） · 公共的搜索路径（`search_path` 机制） |

## 故事主线中的情节定位

这是整个故事最平淡、但最重要的开端——主角一行订单还没有出生，**只有一张空白纸（一张未存在的表）** 和一个装着 PG 的容器。读者会在这一章学会"主角以后住在哪儿"。

## 正文

## 📌 知识点导航

本课覆盖全部三个知识点：

| 节 | 知识点 | 核心问题 |
|---|---|---|
| 第三幕（一） | 1.1 PostgreSQL 是什么 | PG 是什么、有什么、跟别的区别在哪 |
| 第三幕（二） | 1.2 安装与工具链 | Docker 怎么起库、psql / pgcli 怎么连 |
| 第三幕（三） | 1.3 数据库与模式层级 | cluster / database / schema / table 四层 + search_path |

---

## 第一幕 · 起源与场景引入

### 一个真实的工作场景

订单服务开发到一半：

```python
# app.py
from psycopg import connect

def get_connection():
    return connect("postgresql://orders_user:xxx@localhost:5432/orders")
```

业务方说："先连一下我们的 staging 数据库看一眼今天的订单。"你刚装完 macOS，本机空空的——

> "好。先装个 PostgreSQL 吧。"

装到这儿就发现两个现实问题：

1. 哪个版本？社区有 **18.x stable**（2025-09 GA，至 2026-09 已发布 18.6）、仓库稳定 **17.x（17.11）**、"刚出的 18 是不是更快？"
2. 装哪儿？本机、Docker、brew，还是哪家云？同事说"我 brew 装的"，PM 说"我们都用 Docker"。

这两个问题，所有 PG 新手都会撞一次。先别问答案——**把今天这课上完，装库这件事你就有自己的判断，不会再被任何选项带着跑**。

### 一个意外的起源故事

你大概不知道，PG 的故事要从 **1986 年** 讲起——**比 MySQL 还早**：

```mermaid
timeline
    title PostgreSQL 起源时间线（核查于 2026-09-06）
    1986 : 加州大学伯克利分校 Michael Stonebraker 教授启动 POSTGRES 项目（DARPA / ARO / NSF / ESL 资助）
    1989 : POSTGRES v1.0 发布给外部用户
    1994 : 研究生 Andrew Yu 与 Jolly Chen 给 POSTGRES 加 SQL 解释器，发布为开源的 Postgres95
    1996 : 社区嫌"95"年份味儿太重，改名 PostgreSQL，版本号重置为 6.0
    2010s : 9.x 引入流复制与热备，社区生态起飞
    2024-09-26 : PostgreSQL 17.0 发布
    2026-08-10 : 17.11（当前 latest minor，核查于 2026-09-06）
```

> 这一串时间没别的意思——只是为了说明：**PG 不是"另一个开源 MySQL"，它有自己的血脉。**

---

## 第二幕 · 认知冲突

装库这件事，**看起来一行 `docker run` 就完事**——但真做会发现两个挑战：

**挑战一：版本选错掉链子**

```bash
docker run -d postgres  # 直接用 latest tag = 当前是 18.6 stable
# 你的应用代码可能用了 PG 17 才支持的特性（如 SQL/JSON 标准函数 JSON_TABLE）
# 结果：开发连不上、报错 function json_table() does not exist
```

**挑战二：误区太多**

- ❌ "用 `postgres:latest`，最新版总是更好"
- ❌ "用 brew 装客户端，结果跟 Docker 服务端版本不一致，加密协议协商失败"
- ❌ "不设 POSTGRES_PASSWORD，容器启动失败"

这些都不是玄学——都是**真实生产事故的成因**。本课就是要让你**第一装就避开这些坑**。

---

## 第三幕 · 层层揭示

### 第三幕（一）· 知识点 1.1：PostgreSQL 是什么

#### 一句话定义

> **PostgreSQL（也称 Postgres）** 是**开源、对象关系型数据库管理系统（ORDBMS, Object-Relational Database Management System）**，以**严格的 SQL 标准兼容性、ACID 事务、MVCC 并发控制、与极强的扩展能力**著称。

#### 直觉建立

PG 的"是什么"一句话难讲清——**把它跟几个熟悉的东西比较会更直观**：

| 比喻 | 你熟悉的 | PG 是什么 |
|---|---|---|
| 跟 MySQL 比 | 轻、快、简单 | PG 是"功能更全、数据完整性更强"的开源派 |
| 跟 Oracle 比 | 贵、重、强 | PG 是"能力接近 Oracle"但完全免费的开源派 |
| 跟 SQLite 比 | 单文件、应用内嵌 | PG 是 C/S 架构（多客户端远程连接） |
| 跟 MongoDB 比 | 文档、灵活 | PG 是"也能存 JSONB"，但以结构化著称 |

> 一句话：**PostgreSQL ≈ "开源免费的 Oracle 级数据库"**。这个比喻不是 100% 准，但能让你一瞬间定位它。

#### 类比边界（哪里不灵）

- ❌ **别用 PG 当 "MySQL Plus"**：MySQL 的极简运维、更激进的内存缓冲策略是 PG 没有的
- ❌ **别用 PG 当 "开源 Oracle"**：Oracle 的物化视图重写、并行查询、内存列式引擎等是商业特性，PG 仍有差距
- ❌ **别用 PG 当 "文档数据库"**：JSONB 不是 MongoDB，复杂文档模型仍不是 PG 的优势区

#### 核心原理 · 6 大支柱

PG 不是单一特性立身的，下面 **6 大支柱**共同支撑它的"全能"——前 3 个是数据库的"自我修养"，后 3 个是 PG 的特长：

```mermaid
graph LR
    A[PostgreSQL 17] --> B[数据库自我修养]
    A --> C[PG 的特长]
    B --> B1[ACID 强事务]
    B --> B2[MVCC 多版本并发]
    B --> B3[SQL 标准兼容]
    C --> C1[JSONB 二进制 JSON]
    C --> C2[扩展体系 PostGIS / pgvector]
    C --> C3[内置流/逻辑复制]
```

**1. ACID 强事务**：默认 `READ COMMITTED`（与 MySQL 默认 `REPEATABLE READ` 不同），最高支持 `SERIALIZABLE`。本课稍后接入应用后体验默认行为。

**2. MVCC 多版本并发控制（Multi-Version Concurrency Control）**：每个事务有"快照"，写不阻塞读、读不阻塞写。**这条特性是 PG 与 MySQL InnoDB 的关键分歧点**，阶段 4 会专门讲。

**3. 严格的 SQL 标准兼容**：实现了 SQL:2011 的大部分。意味着从 Oracle / DB2 移植过来的 SQL 改动很小。

**4. JSONB**：JSON 的**二进制**编码（不只是文本存储），支持 GIN 索引 + JSONPath 查询。**实际生产里，PG 用 JSONB 替代文档数据库**是高频用法。

**5. 扩展体系**：`CREATE EXTENSION` 一行命令启用：

| 扩展 | 用途 |
|---|---|
| `PostGIS` | GIS（地理信息系统） |
| `pgvector` | 向量检索（AI 时代） |
| `pg_trgm` | 模糊搜索（`LIKE '%xxx%'` 用 GIN 索引） |
| `uuid-ossp` | UUID 生成 |
| `pg_cron` | 定时任务 |

**6. 内置复制**：流复制（PG 10+，物理复制）+ 逻辑复制（PG 10+，行级可定制），**无需额外付钱买 Oracle GoldenGate，PG 直接给**。

#### 示例演示 · 装个容器看一眼

```bash
# 拉镜像（postgres:17 = 17.11，核查于 2026-09-06）
docker pull postgres:17

# 起一个最简容器
docker run -d --name pg17 \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_USER=postgres \
  -p 5432:5432 \
  postgres:17

# 看版本
docker exec -it pg17 psql -U postgres -c "SELECT version();"
# PostgreSQL 17.11 (Debian 17.11-1.pgdg130+1) ...
```

> 输出可能因为 PG 17.x 的小修订而有略微差异。但**核心理念是**：一键 `docker run` 起一个 PG 容器，再 `SELECT version()` 看见自己连到了哪个版本。

#### 常见误区

| 误区 | 真相 |
|---|---|
| ❌ "PG 就是 MySQL 的开源替代" | PG 历史（1986→1994→1996）**比 MySQL 还早**，不可互相替代；功能取舍不同 |
| ❌ "PG 高大上，MySQL 够用就行" | 这种二分法太粗——PG 在**复杂查询、报表、GIS、AI 向量检索**全面胜出；MySQL 在**轻量 OLTP、读多写少**仍有优势 |
| ❌ "PG 17 比 16 慢" | 17 引入了 WAL 插入锁优化（详见 17.x 变更日志），**不少 OLTP 负载 17 更快** |
| ❌ "装 `postgres` 不带版本号 = 装最新版" | 不带版本号 = `latest` tag。`latest` 当前指向 PG **18.6 stable**（2025-09 GA，至 2026-09 已发布 18.6；与本课锁定 PG 17.x 的版本基线不符）。**生产一律钉版本号** |

#### 一句话记住

> PG = 1986 Berkeley 血统 + 1996 名字定型 + "开源免费的 Oracle 级数据库"。

📚 **官方文档**：

- PG 起源故事：[A Brief History of PostgreSQL](https://www.postgresql.org/docs/current/history.html)
- PostgreSQL 17 文档：[postgresql.org/docs/17](https://www.postgresql.org/docs/17/)

---

### 第三幕（二）· 知识点 1.2：安装与工具链

#### 一句话定义

> 本课程用 **Docker 起 PG 17 容器** + **pgcli 作为日常客户端**（psql 作为兜底），这是与你未来 16 课都要共用的开发环境。

#### 直觉建立

PG 的开发环境有三件套：

```
              ┌──────────────────────────────┐
              │  postgresql-server           │ ← PG 服务端进程（在容器里）
              │  （POSTGRES_PASSWORD = xxx）  │
              └─────────────┬────────────────┘
                            │ TCP :5432
                            ▼
              ┌───────────────────────────────┐
              │  psql  /  pgcli 客户端        │ ← 你在本机用
              │  -h host -p 5432 -U user      │
              └───────────────────────────────┘
                            │ SQL
                            ▼
                    你的数据库（order_service）
```

一句话：**服务端跑在容器里、客户端跑在本机**。

#### 核心原理 · 三大件 + 5 个 PG 环境变量

| 件 | 角色 | 用法 |
|---|---|---|
| **postgresql-server** | 服务端 | Docker `postgres:17` 镜像 |
| **psql** | 标准 CLI | PG 自带；`psql -h ... -U ... -d ...` |
| **pgcli** | 增强 CLI | `brew install pgcli`；自动补全 + 语法高亮 |

PG 客户端默认从 **5 个环境变量**读连接信息：

```bash
PGHOST=localhost
PGPORT=5432
PGUSER=postgres
PGPASSWORD=postgres
PGDATABASE=order_service
```

设好后直接 `pgcli` 一行连——日常开发效率明显更高。

#### 示例演示 · Docker 起 PG + pgcli 连接 4 步走

**Step 1：拉镜像（钉版本号，不写 `latest`）**

```bash
docker pull postgres:17
# 等价于 postgres:17.11（核查于 2026-09-06）
```

**Step 2：起容器**

```bash
docker run -d --name pg17 \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_DB=order_service \
  -p 5432:5432 \
  postgres:17
```

参数地图：

| 参数 | 作用 |
|---|---|
| `-d` | 后台运行 |
| `--name pg17` | 容器命名（之后可用 `docker exec` 引用） |
| `-e POSTGRES_PASSWORD=...` | **必须设置**密码 |
| `-e POSTGRES_USER=postgres` | 设用户名（默认是 `postgres`，可省） |
| `-e POSTGRES_DB=order_service` | 启动时创建数据库 `order_service` |
| `-p 5432:5432` | 把容器端口 5432 映射到本机 5432 |

**Step 3：装客户端**

```bash
# macOS arm64 推荐 brew（pgcli 4.5.0，核查于 2026-09-06）
brew install pgcli

# 备选：uv（隔离、不污染全局 Python）
uv tool install pgcli
```

**Step 4：连接（三种风格）**

```bash
# URL 风格（最推荐——一眼看清）
pgcli 'postgresql://postgres:postgres@localhost:5432/order_service'

# 标志位风格
pgcli -h localhost -p 5432 -U postgres -d order_service

# 用环境变量
export PGHOST=localhost PGPORT=5432 PGUSER=postgres PGPASSWORD=postgres PGDATABASE=order_service
pgcli
```

连上去跑：

```sql
SELECT 1;                  -- ?column? = 1，连接成功
SELECT current_database(), current_user, version();
\l                          -- 列出所有库
\dt                         -- 列出当前库所有表（此时应空）
\q                          -- 退出
```

#### 常见误区

| 误区 | 真相 |
|---|---|
| ❌ "不设 POSTGRES_PASSWORD 也能用" | **不设密码 = 容器启动失败**（entrypoint 检测到即报错退出） |
| ❌ "用 `postgres` 不带版本" | 那等于 `postgres:latest`，**当前指向 PG 18.6 stable**（PG 18 已于 2025-09 GA；与本课锁定的 PG 17.x 版本基线不一致）——**生产环境禁止用 latest** |
| ❌ "5432 端口被占用怎么办" | 改 host 端口 `-p 5433:5432`（容器内仍是 5432，只是本机暴露成 5433） |
| ❌ "brew install pgcli 自动装了 PG 服务端" | Homebrew 装 pgcli **只装客户端 libpq**，不会装 server |
| ❌ "用 psql 还是 pgcli？" | **本课推荐 pgcli**（自动补全 + 语法高亮极大降低拼错率）。psql 仍要知道（生产 / 自动化脚本常用） |

#### 一句话记住

> `docker run postgres:17` + `POSTGRES_PASSWORD` + `-p 5432:5432`，**一行起库**；`pgcli` 自动补全，`psql` 兜底。

📚 **官方文档**：

- Docker postgres 镜像文档：[hub.docker.com/_/postgres](https://hub.docker.com/_/postgres)
- pgcli 安装与连接：[pgcli.com](https://www.pgcli.com/)
- psql 手册：[PostgreSQL Documentation - psql](https://www.postgresql.org/docs/17/app-psql.html)

---

### 第三幕（三）· 知识点 1.3：数据库与模式层级

> 📍 故事中的位置：仓库管理员开始规划——`order_service` 库归你管，但要分清**库里的几层结构**，订单才不会乱

#### 一句话定义

> PG 用 **cluster → database → schema → table** 四层结构组织数据；不带 schema 限定时按 `search_path`（默认 `'"$user", public'`，核查于 2026-09-06）顺序查找。

#### 直觉建立：把 PG 比作"一栋办公楼"

| 层 | 比喻 | 数量级 |
|---|---|---|
| **cluster** | 一栋楼（一个 PG 服务进程） | 一台机器通常 1～2 个 |
| **database** | 一间公司（独立业务） | 一栋楼通常 1～10 个 |
| **schema** | 库内的部门 / 文件夹 | 一个库通常 1～20 个 |
| **table** | 部门的实际数据表 | 一个库几十～几千张 |

```mermaid
graph TD
    C[cluster<br/>一个 postmaster 进程] --> D1[database<br/>order_service]
    C --> D2[database<br/>postgres]
    C --> D3[database<br/>template1]
    D1 --> S1[schema public]
    D1 --> S2[schema finance]
    D1 --> S3[schema sales]
    S1 --> T1[orders]
    S2 --> T2[payments]
    S3 --> T3[customers]
```

四层结构在 PG 数据库的每条 SQL 都要用到：
- **没指定 schema**（`SELECT * FROM orders`）→ 按 `search_path` 找
- **指定 schema**（`SELECT * FROM finance.payments`）→ 直接定位

#### 类比边界（哪里不灵）

- ❌ **PG 的 cluster ≠ K8s cluster**。PG 里 cluster 仅指**一个 postmaster 进程**（单机单实例），与 K8s "机器集群"不是一个概念。PG 集群（指主备多实例）= 多个 cluster 协作
- ❌ **PG 的 schema ≠ MySQL 的 database**。PG 的 schema 是**库内的命名空间**，数据库的"账号和数据"看不到别库，schema 在库内互相引用；MySQL 的 schema ≈ database（SQL 标准的早期语义）
- ❌ **PG 的 database ≠ MySQL 的 database 完全等价**。PG 的 database 之间的对象几乎完全隔离（除 `postgres_fdw`）；MySQL 不同 database 可以直接 `db.table` 跨库查询（语义更轻）

#### 核心原理 · 4 层 + 1 个搜索路径

**1. cluster（集群 = 一个 postmaster 进程）**
- 一个 PG 服务进程（`postmaster`）对应一个 cluster
- 一个 cluster 监听一个端口（默认 5432）
- 一个 cluster 下可以有多个 database
- 一个 cluster 共享一份全局配置（`postgresql.conf` / `pg_hba.conf`）+ 一份全局用户 / 角色列表
- 一台机器可以跑多个 cluster（用不同端口 / 不同 `data directory` 区分）

> 你启动的那个 Docker 容器 `pg17`，就是一个 cluster。

**2. database（数据库 = 一个独立的数据世界）**
- 一个 cluster 下可以有多个 database
- database 之间互相隔离：**database A 看不到 database B 的表/视图/函数**
- 每个 database 有自己的系统表（`pg_*`）、自己的角色与权限、自己的 `search_path` 默认值
- 创建：`CREATE DATABASE order_service;`
- 删除：`DROP DATABASE order_service;`（注意：会删除所有表 / 函数 / 视图 / … 的数据，**生产慎用！**）

```sql
-- 列出当前 cluster 下所有 database
\l
-- 切到 order_service 库
\c order_service
```

**3. schema（模式 = 库内的命名空间）**
- 数据库内的逻辑分组（类似文件夹，但**不能嵌套**）
- 每个数据库**默认就有 `public` schema**
- 表必须属于某个 schema（默认 public）
- 创建：`CREATE SCHEMA finance;`
- 删除：`DROP SCHEMA finance CASCADE;`（CASCADE 会连同其中的表一起删）
- 引用方式：`finance.orders`（schema.table）

```sql
-- 列出当前数据库所有 schema
\dn
-- 注意：除了 user 创建的 schema，pg_catalog 与 pg_temp_* 也总在列表里
```

**4. table（表 = 实际数据存储）**
- schema 下的实际表
- 创建时若不指定 schema，默认放到 `search_path` 第一个存在的 schema（通常是 `public`）

```sql
-- 列出 finance schema 下所有表
\dt finance.*
-- 列出所有 schema 下所有表
\dt *.*
```

**5. search_path（搜索路径 = 未限定名称的查找顺序）**
- 当你写 `SELECT * FROM orders` **不带 schema** 时，PG 按 `search_path` 顺序找
- 默认值（PG 17 与历史一致，**核查于 2026-09-06**）：

```
search_path
------------
 "$user", public
```

- `$user` 是**与当前用户名同名**的 schema（如果有），没有就跳过
- `pg_catalog` / `pg_temp_*` **总是在 search_path 中被搜**（即使没列入）

```sql
-- 看当前 search_path
SHOW search_path;

-- 临时改 search_path（当前会话）
SET search_path TO finance, public;
SELECT * FROM orders;   -- 现在能直接命中 finance.orders

-- 永久改（角色级 / 数据库级 / 实例级）
ALTER ROLE postgres SET search_path TO finance, public;
ALTER DATABASE order_service SET search_path TO finance, public;
-- 或写在 postgresql.conf
```

#### 示例演示 · 在 order_service 库创建 2 个 schema 并装 2 张表

```bash
# 已有的 pg17 容器已经在跑，order_service 库已建（前面 1.2 装的）
# 不需要再起容器，直接连进去

pgcli 'postgresql://postgres:postgres@localhost:5432/order_service'
```

```sql
-- 1. 看当前所在层
SELECT current_database();                      -- order_service
SHOW search_path;                                -- "$user", public
\dn                                              -- 至少 public、pg_catalog、information_schema、pg_temp_*
\dt *.*                                          -- 表清单（应空）

-- 2. 建两个 schema
CREATE SCHEMA finance;
CREATE SCHEMA sales;
\dn                                              -- 多出 finance、sales

-- 3. 在 finance 建一张表（不带 schema. 前缀，默认会被建到 search_path 第一个 schema）
--    先看 search_path：默认是 "$user", public → 表会落到 public
CREATE TABLE payments (
    id SERIAL PRIMARY KEY,
    amount NUMERIC(10,2) NOT NULL,
    paid_at TIMESTAMPTZ DEFAULT now()
);
\dt public.*                                     -- payments 在这里！

-- 4. 在 sales 建一张表——用限定名（明确放 sales schema）
CREATE TABLE sales.customers (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL
);

-- 5. 改 search_path 让 sales 是第一个，再查不带前缀的"customers"能命中
SET search_path TO sales, public;
SHOW search_path;                                -- sales, public
SELECT * FROM customers LIMIT 1;                 -- 直接命中 sales.customers

-- 6. 重要练习：search_path 决定"未限定访问"
RESET search_path;                               -- 回到默认
SHOW search_path;                                -- "$user", public
SELECT * FROM customers;                         -- 报错：表不存在（不再找 sales）
SELECT * FROM sales.customers;                   -- OK
```

#### 常见误区

| 误区 | 真相 |
|---|---|
| ❌ "PG 的 schema = MySQL 的 database" | **错**。PG schema 仅是 database 内的命名空间，**不是独立库**；二者有从属关系 |
| ❌ "PG 的 cluster 是机器集群" | **错**。PG cluster 仅指**一个 postmaster 进程**（单实例）。PG 多机集群叫"replication cluster"或"PG cluster of instances" |
| ❌ "`SELECT * FROM a.b.c` 能跨库查" | PG 标准 SQL **不支持**跨 database 查询。需要扩展 `postgres_fdw` 才能跨库 |
| ❌ "public 是某个用户默认建的" | **错**。public 是 PG 自动创建的默认 schema，所有新表默认落这里 |
| ❌ "改 search_path 全局生效" | `SET search_path` 只对**当前会话**生效；`SET ROLE`/ `ALTER ROLE ... SET` 才能持久化到角色 |
| ❌ "找不到表就报 schema 不存在" | 报的通常是 `relation "x" does not exist`；schema 名称拼错则报 `schema "x" does not exist` |

#### 一句话记住

> cluster = 进程；database = 独立库；schema = 库内文件夹（不能嵌套）；table = 实际表；`search_path` 默认 `'"$user", public'`。

📚 **官方文档**：

- PG schema 文档：[Schemas](https://www.postgresql.org/docs/current/ddl-schemas.html)
- search_path 参数文档：[search_path](https://www.postgresql.org/docs/current/runtime-config-client.html#GUC-SEARCH-PATH)
- cluster 概念：[The SQL Language / Database Cluster / Schema](https://www.postgresql.org/docs/current/ddl-schemas.html)

---

## 第四幕 · 实操验证

### 综合演练（端到端）

**Part A · 1.1 + 1.2：装库 + 连库**

```bash
# 1. 拉镜像
docker pull postgres:17

# 2. 起容器（设密码 + 创建 order_service 库）
docker run -d --name pg17 \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=order_service \
  -p 5432:5432 \
  postgres:17

# 3. 看容器是否健康
docker ps --filter name=pg17
# 应看到 STATUS = "Up ... (healthy)"；第一次启动需 5~15 秒初始化

# 4. 用 psql 连进去（不装 pgcli 也能用）
docker exec -it pg17 psql -U postgres -d order_service -c "SELECT version();"
# 预期输出：PostgreSQL 17.x (Debian ...) on x86_64-pc-linux-gnu ... （一行）

# 5. 装 pgcli 并连
brew install pgcli
pgcli 'postgresql://postgres:postgres@localhost:5432/order_service'

# 6. 在交互模式里跑：
#    SELECT 1;                          -- 验证连通
#    SELECT current_database();         -- 当前库 = order_service
#    SELECT version();                  -- PostgreSQL 17.x
#    \l                                 -- 列出库（应看到 postgres / template0 / template1 / order_service）
```

**Part B · 1.3：四层结构 + search_path**

```sql
-- 7. 看当前所在层
SHOW search_path;                       -- 默认 "$user", public
\dn                                      -- 当前库的 schema（至少 4 个：public / pg_catalog / information_schema / pg_temp_NNN）

-- 8. 建两个 schema
CREATE SCHEMA finance;
CREATE SCHEMA sales;
\dn                                      -- finance、sales 已加上

-- 9. 在 sales 建表，schema 限定版
CREATE TABLE sales.customers (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL
);

-- 10. 在 public 建表（用 search_path 默认）
SET search_path TO public;              -- 显式把第一个设为 public
CREATE TABLE payments (
    id SERIAL PRIMARY KEY,
    amount NUMERIC(10,2) NOT NULL
);

-- 11. search_path 实验
SET search_path TO sales, public;       -- 改路径
SELECT * FROM customers LIMIT 0;        -- 能命中（sales.customers）
RESET search_path;                       -- 复位
SELECT * FROM customers LIMIT 0;        -- ❌ 报错 relation "customers" does not exist
SELECT * FROM sales.customers LIMIT 0;  -- ✅ 限定名总能找到

-- 12. 退出
\q
```

**预期结果**：到 Step 11 的 RESET + "关系不存在" 报错，是 1.3 的"耐受点"——你能解释为什么报这个错（因为 search_path 复位后不再包含 sales）。

> ⚠️ **macOS 注意**：Docker Desktop 24.x 之后默认 **不开机自启**。如果 `docker ps` 报 `Cannot connect to the Docker daemon`，请先 `open -a Docker`，等 Docker Desktop 跑起来再继续。

### 反例对照 · 3 个"看起来对但不对"的命令

| 你要跑 | ❌ 错误写法 | ✅ 正确写法 | 错在哪 |
|---|---|---|---|
| 拉镜像 | `docker pull postgres` | `docker pull postgres:17` | `postgres` = `postgres:latest`，未钉版本 |
| 起容器 | `docker run postgres:17` | `docker run -e POSTGRES_PASSWORD=xxx postgres:17` | 缺密码，容器会立刻退出 |
| 连客户端 | `pgcli -h localhost` | `pgcli postgres://postgres:postgres@localhost:5432/order_service` | 缺端口 / 用户 / 库 |

---

## 第五幕 · 体系收束

你今天得到的能力地图：

```
                     课 1 · 认识 PostgreSQL（全课 3 个知识点）
                                   │
        ┌──────────────┬───────────┴────────┬──────────────┐
        ▼              ▼                    ▼              ▼
    PG 是什么      起源故事         Docker 起容器     四层结构
   （ORDBMS）    （1986→1996）     （postgres:17）  （cluster→db
        │              │                    │           →schema→
        │              │                    │             table）
        │              │                    │              │
        └──────────────┴───────────┬────────┴──────────────┘
                                   │
                         现在你会做什么？
                                   │
   ┌─────────────────┬────────────┴──────────────┬──────────────────┐
   ▼                 ▼                           ▼                  ▼
 能向同事一句话      能在 macOS 用 Docker 起      能在库里建 schema    能解释 search_path
 解释 PG           一个可连的 PG 17 容器         / 看库 / 查表        默认行为与修改方法
   │                 │                           │                  │
   └────────┬───────┴───────────┬─────────────────┘                  │
            ▼                    ▼                                  │
     PG 整体定位            PG 的"住所"层级                         │
            └──────────┬─────────┘────────────────────────────────┘
                       ▼
                  下一课《表与数据类型》
                 （课 2：建表 / CRUD）
```

**本课在整体故事中的位置**：主角一行订单还没有出生——我们为它**准备了"家"**（PG 容器）并且搞清了"家"的层级（cluster → database → schema → table）。**下一步要把"表"建出来**。

**接下来**：

- **下一课《表与数据类型》**：用今天装的库在 `public` schema 下建一张 `orders` 表（知识点 2.1 数据类型 + 2.2 建表约束 + 2.3 CRUD 基础）
- **阶段 1 收尾**：课 3《查询基础》——把表里的数据查出来

---

## 🐞 误区清单

汇总本课典型错误（**用错** / **配错** / **认错**）：

| # | 误区 | 触发 | 修复 |
|---|---|---|---|
| 1 | 装 `postgres` 不带版本 | `docker run -d postgres` 启了 18.6 stable（与 PG 17 应用可能不兼容） | 钉 `postgres:17` |
| 2 | 忘了设密码 | 容器退 `ERROR: No POSTGRES_PASSWORD set!` | `-e POSTGRES_PASSWORD=xxx` |
| 3 | 端口冲突 | 容器退 `bind: address already in use` | 换本机端口 `-p 5433:5432` |
| 4 | brew 装 pgcli 顺带装 PG server | 想纯客户端，不该装 server | `brew install pgcli` 只装客户端 libpq |
| 5 | pgcli / psql 与服务端版本大差距 | SSL 协商失败 | 客户端钉与服务端同主版本 |
| 6 | **PG schema = MySQL database** | MySQL 来的同学会把 PG 的 schema 当 database 用 | **记住**：PG schema 仅是 library 内的文件夹；库之间用 database 隔离 |
| 7 | **PG cluster = K8s 集群** | PG cluster 仅是一个 postmaster 进程（**单实例**） | 真正的多机 PG 集群说"PG 主从集群 / replication cluster" |
| 8 | 跨 database 直接 `db1.t1 JOIN db2.t2` | PG 标准 SQL **不支持** | 安装扩展 `postgres_fdw` 才能跨库 |
| 9 | 设 `SET search_path` 后误以为是全局 | 只对当前会话 | 持久化：`ALTER ROLE / DATABASE ... SET search_path = ...` |
| 10 | `DROP DATABASE xxx` 用于清理 | 会**删除库中全部表 / 函数 / 视图 / 数据** | 生产禁止裸 `DROP DATABASE`；测试用 `DROP SCHEMA xxx CASCADE` |

---

## 一图总结

![课 1 一图总结](./assets/lesson-01-overview.svg)

---

## 📋 命令速查卡（课 1）

| 命令 | 作用 | 注意事项 |
|---|---|---|
| `docker pull postgres:17` | 拉 PG 17 镜像（= 17.11，核查于 2026-09-06） | 不写版本 = `latest`，生产禁 |
| `docker run -d --name pg17 -e POSTGRES_PASSWORD=xxx -p 5432:5432 postgres:17` | 起 PG 容器 | 密码必设 |
| `docker run -d ... -e POSTGRES_DB=order_service postgres:17` | 启动时建库 | 可省，自动用 `POSTGRES_USER` 同名库 |
| `docker ps --filter name=pg17` | 看容器状态 | `STATUS = healthy` 算起好 |
| `docker exec -it pg17 psql -U postgres -d order_service` | 进容器 psql | 不用装客户端也能用 |
| `brew install pgcli` | 装 pgcli（4.5.0，核查于 2026-09-06） | 仅装客户端 libpq |
| `pgcli postgres://postgres:postgres@localhost:5432/order_service` | URL 风格连接 | 特殊字符 URL encode |
| `psql -h localhost -p 5432 -U postgres -d order_service` | 标志位风格 | 生产 / 脚本常用 |
| `export PGHOST=...; pgcli` | 用环境变量 | CI 通用 |
| `SELECT version();` | 验证连接 | 输出含 `PostgreSQL 17.x` |
| `SELECT current_database(), current_user;` | 看当前库与用户 | 验证身份 |
| `\l` | 列出所有库 | psql / pgcli 元命令 |
| `\dn` | 列出当前库所有 schema | 含 public / pg_catalog / 自建 schema |
| `\dt` | 列出 search_path 中可见的表 | 不带前缀 |
| `\dt *.*` | 列出所有 schema 下所有表 | 包括 schema 限定 |
| `\dt finance.*` | 列出 finance schema 下的表 | schema 限定 |
| `SHOW search_path;` | 看当前搜索路径 | 默认 `'"$user", public'`（PG 17，核查于 2026-09-06） |
| `SET search_path TO finance, public;` | 改搜索路径 | 只对当前会话 |
| `RESET search_path;` | 复位 search_path | 回到默认 |
| `ALTER ROLE postgres SET search_path TO finance, public;` | 持久化到角色 | 重连后生效 |
| `CREATE SCHEMA finance;` | 建 schema | 仅 database 内可见 |
| `CREATE TABLE finance.payments (...);` | 用限定名建表 | 不受 search_path 影响 |
| `\q` | 退出 | — |

> 命令速查卡规则：本课程的每条命令都会在用到它的课里再出现一次（不重复发明）。

---

## 🌐 关键事实备注（核查于 2026-09-06）

| 事实 | 当前值 | 来源 |
|---|---|---|
| PG 17 最新 minor | **17.11**（2026-08-10） | endoflife.date / hub.docker.com |
| Docker 镜像 tag | `postgres:17` = `17.11`；`postgres:latest` = `18.6 stable`（PG 18 已 GA，2025-09-25） | hub.docker.com/_/postgres |
| pgcli 最新版 | **4.5.0**（Homebrew 2026-08-27）/ GitHub 4.6.0（2026-08-26） | pgcli.com / dbcli/pgcli |
| 装 pgcli 时一并装的内容 | 仅 `postgresql@xx` 客户端 libpq | Homebrew formula |
| PG 17 关键改进 | WAL 插入锁优化 / 增量备份 / 逻辑复制 failover control | 17.x release notes |
| search_path 默认值 | `'"$user", public'`（PG 17 与历史版本一致） | postgresql.org/docs/current/ddl-schemas |
| 跨 database 查询方式 | 标准 SQL **不支持**；扩展 `postgres_fdw` 可 | postgresql-fdw 文档 |

---

## 🧭 课程导航

> 本课是阶段 1 的**第一课**，也是阶段 1 的开场。**阶段 1 内三个课**：
>
> - 课 1 认识 PostgreSQL ← 你在这里
> - 课 2 表与数据类型（同阶段，下一课）
> - 课 3 查询基础（同阶段，收官课）
>
> **阶段 1 闭环预告**：学完课 3 后，你应能独立 **"用 Docker 起 PG / 建库 / 建 schema / 建表 / 写日常查询"** 的端到端能力。

- 下一课：课 2 表与数据类型（[同阶段 →](lesson-02-表与数据类型.md)）
- 返回目录：[`02-课程目录.md`](../../02-课程目录.md)
- 上一阶 / 下一阶：阶段 1 是首阶段，上无前置阶段

> **课程任务**（整课完成）：1.1 + 1.2 + 1.3 均已交付 ✅（P0=0，P1=1 项已修订）。
