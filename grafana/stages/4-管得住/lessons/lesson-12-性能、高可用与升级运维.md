# 第 12 课：性能、高可用与升级运维

> 所属阶段：阶段 4《管得住》｜ 水平：入门 ｜ 本课知识点：性能瓶颈、数据库后端与 HA、升级与备份
> 故事情节：从"能跑"到"敢升级"——升级前要查什么？回滚靠什么？

## 🎯 本课目标

- 给出仪表盘性能问题的排查顺序与量化判据
- 说清单机 SQLite 在什么规模下必须换 Postgres/MySQL
- 列出升级前检查清单，并说明回滚依赖什么

## 知识点导航

| # | 知识点 | 关键点 | 状态 |
|---|--------|--------|------|
| 12.1 | 性能：面板数量、查询并发与渲染压力 | 瓶颈定位 / 并发与缓存 / 量化判据 | ✅ 已完成 |
| 12.2 | 数据库后端与高可用部署 | SQLite 的边界 / 换 Postgres 的时机 / HA 部署形态 | ✅ 已完成 |
| 12.3 | 升级与备份：升级前查什么、回滚靠什么 | 升级路径 / 备份内容 / 回滚依赖 | ✅ 已完成 |

---

## 第一幕：场景引入——周一早上，仪表盘打不开了

### 一个真实的场景

周一早上九点，你在会上投屏打开运维大盘。

转圈。转了 **二十秒** 才出来。

散会后你开始排查，脑子里冒出三个猜测：

1. "是不是面板太多了？"——这张盘有 40 个面板
2. "是不是 Prometheus 慢了？"——但你单独查同一个语句只要 0.01 秒
3. "是不是 Grafana 该加内存了？"——但监控显示内存才用了 30%

三个猜测听起来都合理，**但没有一个能告诉你该先动哪一个**。

这就是本课要解决的问题：把"感觉慢"变成"知道哪里慢、慢多少、该改哪个"。

### 本课要回答的三个问题

本课是阶段 4 的收官，也是整个 Grafana 课程的尾声。前 11 课让你的 Grafana **能跑起来**，本课要让它 **跑得稳、升得动**：

1. **慢在哪**：是面板数量、查询并发、还是渲染？（12.1）
2. **扛得住吗**：单机 SQLite 什么时候必须换 Postgres？HA 到底要解决什么？（12.2）
3. **敢升级吗**：升级前要备份什么？升挂了靠什么回滚？（12.3）

### 本课的验证方法

前 11 课的经验反复证明：**Grafana 的文档说法和实测行为经常不一致**（课 10 的 `allowUiUpdates`、课 11 的 `hasAcl` 都是教训）。所以本课所有结论都来自**控制变量实验**：

| 实验 | 变量 | 测什么 |
|---|---|---|
| A | 面板数 1→80 | 响应时间怎么涨 |
| B | 并发 1→32 | 会不会排队 |
| C | 时间窗 15m→7d | Grafana 自动调步长的影响 |
| D | `maxDataPoints` 100→2000 | 响应体膨胀倍数 |
| E | 低基数 vs 高基数 | 基数对耗时的放大 |
| F | API 查询 vs PNG 渲染 | 渲染的真实代价 |
| G | 10 个并发写 SQLite | 锁竞争是否真实存在 |
| H | 13.2.1 → 12.0.0 降级 | 跨版本到底会发生什么 |

### 实验环境

本课新建了几个专用容器，与前面的课程隔离：

| 容器 | 端口 | 用途 |
|---|---|---|
| `l12-pg` | 5433 | Postgres 16（Grafana 后端） |
| `gf-pg1` | 3004 | 连 Postgres 的 Grafana 13.2.1 |
| `gf-pg2` | 3005 | **共享同一 Postgres** 的第二个实例（HA 实验） |
| `l12-renderer` | 8082 | 官方 image renderer |
| `gf-render` | 3006 | 配了 renderer 的 Grafana（渲染实验） |
| `gf-old` | 3007 | **Grafana 12.0.0**（降级实验） |
| `gf-restore` | 3008 | 用备份恢复出来的实例（恢复验证） |

> 沿用 `grafana-lab`(3001) 做性能实验——它跑了 11 课，里面有真实的 dashboard 和数据。

---

## 第二幕：认知冲突——三个"想当然"的错误

### 冲突 1：面板多就一定慢

**直觉**：dashboard 有 40 个面板，加载慢肯定是因为面板太多。

**实测**：把面板数从 1 加到 80，测响应时间：

```
N=1   三次: 0.006948 / 0.007291 / 0.007381
N=5   三次: 0.008579 / 0.009749 / 0.011179
N=10  三次: 0.011317 / 0.010026 / 0.009520
N=20  三次: 0.014748 / 0.015924 / 0.014626
N=40  三次: 0.025354 / 0.019292 / 0.028767
N=80  三次: 0.031880 / 0.031464 / 0.034290
```

面板数涨了 **80 倍**，耗时只从 7ms 涨到 32ms——**涨了 4.5 倍**。

亚线性增长，而且**绝对值小到可以忽略**。

**真实规则**：面板数量**不是**主要瓶颈。因为 Grafana 会**并发**发这些查询，而不是排队一个个发。40 个面板不等于 40 倍时间。

那什么才是瓶颈？看冲突 2。

### 冲突 2：时间范围拉长，数据会变多

**直觉**：把时间窗从 1 小时拉到 7 天，查的数据量应该暴增，响应应该变慢变大。

**实测**（同一条 `up` 查询，只改时间窗）：

```
窗口      Grafana算出的步长   响应字节   耗时
15m       15000ms            5840      0.007455
1h        30000ms            9680      0.008129
6h        300000ms           6614      0.007560
12h       300000ms           11222     0.008645
24h       900000ms           8151      0.008048
3d        1800000ms          10524     0.008840
7d        7200000ms          4093      0.008433
```

**窗口从 1h 拉到 7d（168 倍），响应体反而从 9680 字节降到 4093 字节（变小了）。**

原因写在第二列：Grafana 会根据时间窗**自动放大查询步长**——1h 用 30s 步长，7d 用 **2 小时**步长。步长放大把数据点稀释掉了，数据总量反而没涨。

**真实规则**：**时间范围不是性能的主要驱动力**，`maxDataPoints` 才是。看冲突 3。

### 冲突 3：慢是因为 Grafana 查询慢

**直觉**：渲染一张 PNG，应该就是"查一次数据 + 画出来"，比纯 API 查询慢一点点。

**实测**（同一个面板，同一个实例）：

```
API查询 第1次: 0.014591s
API查询 第2次: 0.028600s
API查询 第3次: 0.009132s
渲染PNG 第1次: 5.919886s  (10063 字节)
渲染PNG 第2次: 4.907415s  (10063 字节)
渲染PNG 第3次: 4.920869s  (10063 字节)
```

**纯 API 查询 9 毫秒，渲染成 PNG 要 4.9 秒——慢了约 500 倍。**

渲染出来的确实是真的 PNG（文件头魔数 `89 50 4e 47`，即 `‰PNG`），不是报错页面。

**真实规则**：**渲染才是性能悬崖**。渲染要启动一个完整的无头浏览器、加载 Grafana 前端、跑一遍所有查询、再截图。告警截图、定时报表、PDF 导出都会踩这里。

### 三个冲突的共同点

| 冲突 | 想当然 | 实测 |
|---|---|---|
| 1 | 面板多就慢 | 80 倍面板 → 4.5 倍耗时，且绝对值仅 32ms |
| 2 | 时间窗长数据就多 | Grafana 自动放大步长，7d 反而比 1h **小** |
| 3 | 慢在查询 | 查询 9ms，**渲染 4.9 秒**，慢 500 倍 |

三个都指向同一件事：**性能问题不能靠直觉排序，必须量化。**

---

## 第三幕：层层揭示——性能、后端与升级

### 12.1 性能：面板数量、查询并发与渲染压力

#### 一句话定义

**Grafana 的性能瓶颈几乎从不在"查询"本身，而在"数据量"和"渲染"这两头。**

#### 直觉建立：餐厅出餐

把 Grafana 想象成一家餐厅：

| 环节 | 餐厅 | Grafana |
|---|---|---|
| 接单 | 服务员记下 40 道菜 | 浏览器发 40 个查询 |
| 备菜 | 厨房同时开火 | **并发**执行查询 |
| 装盘 | 摆盘、拍照 | 前端渲染 |
| 外卖打包 | 装盒、贴标签、叫骑手 | **PNG 渲染** |

直觉上"40 道菜 = 40 倍时间"，但厨房是**并发**的——四个灶同时开，40 道菜只是把灶占满的时间拉长，不是乘以 40。

而"外卖打包"是**串行的额外工序**：菜已经做好了，还要装盒、贴单、等骑手。这一步比做菜本身还慢。

**类比失效的边界**：餐厅的灶是固定的（CPU 核数），Grafana 的并发受连接池和后端数据源限制。如果 40 个查询**打到同一个慢数据源**，那就会真排队——这时候瓶颈在数据源，不在 Grafana。

#### 核心原理

##### （1）瓶颈在哪里：一张排查顺序表

根据实测数据，我给出**排查顺序**（按性价比从高到低）：

| 顺序 | 查什么 | 判据 | 实测刻度 |
|---|---|---|---|
| 1 | **是否在渲染** | 请求路径含 `/render/` | 渲染 4.9s vs 查询 9ms，**500 倍** |
| 2 | **响应体多大** | 看 `maxDataPoints` 与基数 | 100→2000 时 **983KB→14.3MB（14.5 倍）** |
| 3 | **基数多高** | 序列条数 | 高基数比低基数慢 **13.5 倍** |
| 4 | 面板数量 | 面板数 | 80 倍面板只慢 4.5 倍，**优先级最低** |
| 5 | 时间范围 | 窗口长度 | 影响最小（步长自动补偿） |

**先查渲染，最后查面板数**——这个顺序和大多数人的直觉正好相反。

##### （2）并发：Grafana 会并发，但会饱和

并发实验（同一查询，同时发 C 个请求）：

```
并发=1  全部完成总耗时=0.0158 秒
并发=4  全部完成总耗时=0.0164 秒
并发=8  全部完成总耗时=0.0292 秒
并发=16 全部完成总耗时=0.0464 秒
并发=32 全部完成总耗时=0.0963 秒
```

并发 1→4，总耗时几乎不变（0.0158→0.0164）——**说明前 4 个请求是真正并行的**。

并发 4→32（8 倍），耗时从 0.0164 涨到 0.0963（5.9 倍）——**开始排队了**，但还没有剧烈恶化。

⚠️ **单机边界标注**：这个数字来自一台资源充足的机器，查询的是**本机 Prometheus 且数据量很小**。真实生产环境数据源更慢、数据更多，饱和点会**显著提前**。**这个实验能告诉你"并发是并行而非串行"，但不能告诉你"你的环境能扛多少并发"**——那个必须自己压。

##### （3）`maxDataPoints`：真正的性能开关

这是本课最实用的一条：

```
maxDataPoints   响应字节
100             983508      (0.98 MB)
500             7292161     (7.29 MB)
1000            10797722    (10.8 MB)
2000            14302396    (14.3 MB)
```

**`maxDataPoints` 从 100 涨到 2000（20 倍），响应体从 0.98MB 涨到 14.3MB（14.5 倍）。**

而 `maxDataPoints` 是**由面板宽度决定的**——一个宽 2000px 的面板，Grafana 就会去要 2000 个数据点。哪怕屏幕上只有 200 个像素能画，也要传 2000 个点过来。

> **这就是"面板变大 → 变慢"的真实机制**：不是面板数量，是**每个面板要的数据点数量**。

##### （4）基数：比面板数更狠的放大器

```
up        (低基数): 0.007089s
node_cpu_seconds_total (高基数): 0.095895s   字节=983508
```

同一个时间窗，高基数指标比低基数慢 **13.5 倍**，响应体 983KB。

原因是 `node_cpu_seconds_total` 会展开成 `CPU核数 × 实例数 × mode数` 条序列。课 6 已经埋过伏笔：变量选 All 时响应体涨 21.8 倍。基数爆炸是同一个机制。

#### 示例演示：一次完整的性能排查

假设一张 dashboard 打开要 8 秒。按上面的顺序：

```bash
curl -s --noproxy '*' -u admin:admin -o /dev/null -w 'total=%{time_total}s size=%{size_download}\n' -X POST http://localhost:3001/api/ds/query -H 'Content-Type: application/json' -d '{"queries":[{"refId":"A","datasource":{"uid":"afx7x6dx803y8e"},"expr":"up","instant":false,"maxDataPoints":2000}],"from":"now-6h","to":"now"}'
```

拿到两个数：**耗时**和**响应体大小**。

- 如果耗时集中在 `/render/` → 渲染问题，考虑减少定时截图、或用 CSV 替代 PNG
- 如果响应体 > 5MB → 调小 `maxDataPoints` 或收窄面板宽度
- 如果响应体小但慢 → 查数据源本身
- 如果都正常 → 检查面板数（最不可能）

#### 常见误区

**误区 1：拆 dashboard 是首选优化**

拆盘能减少面板数，但实测面板数是**优先级最低**的瓶颈。分了盘，人要点两次，体验可能更差。**先查渲染和 `maxDataPoints`**。

**误区 2：把时间范围调小能加速**

实测 7d 反而比 1h 返回更少数据（步长自动放大）。调小时间范围**未必**有用，除非同时限制了 `maxDataPoints`。

**误区 3：加机器能解决渲染慢**

渲染慢是无头浏览器启动 + 前端加载的固定开销，与 Grafana 实例的 CPU 关系有限。**真正的解法是减少渲染次数**（降低截图频率、用共享渲染服务）。

#### 一句话记住

> **排查性能：先看是不是在渲染，再看响应体多大，最后才数面板。**

---

### 12.2 数据库后端与高可用部署

#### 一句话定义

**SQLite 存的是"一个 Grafana 的配置"，Postgres 存的是"一组 Grafana 的配置"——换后端的本质，是让多个实例共享同一份配置。**

#### 直觉建立：记事本 vs 共享文档

| | SQLite | Postgres/MySQL |
|---|---|---|
| 类比 | 一个**记事本文件** | 一个**在线共享文档** |
| 谁能改 | 只有拿着这个文件的人 | 所有有链接的人 |
| 两个人同时改 | 后写的覆盖先写的，或者**等锁** | 数据库处理并发 |
| 能不能多人协作 | 不能 | 能 |

**类比失效的边界**：SQLite 不是"不能用"，它在**单实例**下又快又省事。只是它天生假设"只有一个进程在用这个文件"。

#### 核心原理

##### （1）SQLite 的边界：锁竞争真实存在，但被重试掩盖了

我做了个实验：往 SQLite 后端的 `grafana-lab` **并发写 10 个 dashboard**。

表面上，全部成功：

```
200
200
... (10 个全 200)
10 个并发写总耗时=0.4836 秒
```

**但日志里露出了真相**：

```
level=info msg="Database locked, sleeping then retrying" error="database is locked (5) (SQLITE_BUSY)" retry=0 sleep=27.5ms
level=info msg="Database locked, sleeping then retrying" error="database is locked (5) (SQLITE_BUSY)" retry=0 sleep=72.2ms
level=info msg="Database locked, sleeping then retrying" error="database is locked (5) (SQLITE_BUSY)" retry=1 sleep=199.2ms
level=info msg="Database locked, sleeping then retrying" error="database is locked (5) (SQLITE_BUSY)" retry=2 sleep=178.2ms
```

**出现了 `SQLITE_BUSY`，重试到 retry=2，退避时间到 199ms。**

这是本课一个关键洞察：

> **SQLite 的锁竞争不会报错，只会"变慢"。** Grafana 内部有重试机制兜着，所以用户看到的是 200，感受不到锁。但这个重试是有上限的——压力再大就会真的失败。

所以「多大算大」不能只看"有没有报错"，要看**日志里有没有 `SQLITE_BUSY`**。

⚠️ **单机边界标注**：本实验是 10 个并发写。真实环境里告警状态、session、annotation 都在持续写库，实际压力更高。**这个实验证明了"锁竞争存在"，但没有测出"多少个并发会击穿"**——那个阈值我没有测，不做推断。

##### （2）更硬的边界：SQLite 根本没法共享

我查了 `grafana-lab` 的数据目录：

```
/var/lib/grafana/grafana.db     (2.0M)
```

以及它的挂载：

```
docker inspect grafana-lab --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'
(空)
```

**没有挂载到宿主机**——数据库文件在容器内部。这意味着：**你没法起第二个 Grafana 去读同一个 SQLite 文件**（除非做卷共享，但那样两个进程抢一个文件，锁竞争会失控）。

> **这就是 SQLite 不能做 HA 的根本原因**：不是性能不够，是**架构上就只能一个进程用**。

##### （3）换 Postgres：配置不变，只改环境变量

这是本课最实用的一条。起一个连 Postgres 的 Grafana：

```bash
docker run -d --name gf-pg1 --network l12net -p 3004:3000 -e GF_DATABASE_TYPE=postgres -e GF_DATABASE_HOST=l12-pg:5432 -e GF_DATABASE_NAME=grafana -e GF_DATABASE_USER=grafana -e GF_DATABASE_PASSWORD=grafana -e GF_DATABASE_SSL_MODE=disable -e GF_SECURITY_ADMIN_PASSWORD=admin grafana/grafana:13.2.1
```

启动日志确认生效：

```
msg="Config overridden from Environment variable" var="GF_DATABASE_TYPE=postgres"
msg="Connecting to DB" dbtype=postgres
```

**关键结论**：Grafana 的**应用层完全不用改**。Dashboard、数据源、告警、用户、权限——所有的 API 和文件配置都一模一样。变的只是"配置存在哪"。

生成的库：

```
表总数 = 91
最大表: permission(764行) / migration_log(719行) / role(130行)
```

对比 SQLite 后端的 92 张表（课 1 实测），结构基本一致。

##### （4）HA 实测：两个实例共享一个 Postgres

起第二个实例，指向**同一个数据库**：

```bash
docker run -d --name gf-pg2 --network l12net -p 3005:3000 -e GF_DATABASE_TYPE=postgres -e GF_DATABASE_HOST=l12-pg:5432 -e GF_DATABASE_NAME=grafana -e GF_DATABASE_USER=grafana -e GF_DATABASE_PASSWORD=grafana -e GF_DATABASE_SSL_MODE=disable -e GF_SECURITY_ADMIN_PASSWORD=admin grafana/grafana:13.2.1
```

**实验 1：配置一致性**（pg1 建的 dashboard，pg2 能读到吗）

```
在 pg1 建 ha-probe                    → create_http=200
从 pg2 读                              → read_http=200  ✅
在 pg2 建 ha-probe2                    → create_on_pg2=200
回 pg1 读                              → read_back_on_pg1=200  ✅
```

**双向可见，配置天然共享。**

**实验 2：会话共享**（pg1 登录的 cookie，能用来访问 pg2 吗）

```
pg1 登录                          → pg1_login=200
用 pg1 的 cookie 访问 pg2         → pg2_with_pg1_cookie=200  ✅
返回: {"id":1,"login":"admin","orgId":1,"isGrafanaAdmin":true,...}
```

**这个结果出乎意料**：pg1 发的 cookie，pg2 直接认了。

原因：Grafana 的会话存在**数据库**里（`user_auth_token` 表），不是存在实例内存里。所以只要共享数据库，会话就自动共享——**不需要额外配 Redis**。

> **这是个重要的实用结论**：很多教程会让你配 Redis 做 session 共享。实测表明，**默认配置下会话就已随数据库共享**。Redis 在 Grafana 里主要是给告警 HA（`ha_redis_address`）和缓存用的。

**实验 3：告警会不会重复发**

这是 HA 最容易踩的坑——两个实例都在跑告警规则，会不会各发一条？

我在 pg1 上配了一条必定触发的规则，等 90 秒：

```
pg1(3004) 告警状态: [{"annotations":{...},"fingerprint":"b318e8851e1745d6","receivers":[{"name":"empty"}],"startsAt":"2026-09-07T03:40:30.000Z",...}]
pg2(3005) 告警状态: []
```

**pg2 返回空数组。**

⚠️ **未实测声明**：pg2 刚启动不久（20 秒），而告警规则默认 60 秒一轮。**pg2 返回空，可能只是"还没到它的求值周期"，不等于"它永远不会触发"**。我没有做完整的双实例告警去重验证（需要两个实例稳定运行多个周期并观察通知是否重复）。

官方的做法是用 `ha_redis_address` 或依赖 Alertmanager 的 gossip 做去重，`grafana.ini` 里能看到默认值：

```
;high_availability = true
;ha_redis_address =
```

**结论**：告警去重**需要额外配置**，不能假设"共享数据库就自动去重"。这一点我没能在本机给出实测结论，标注 **⚠️ 未实测**。

**实验 4：迁移锁**

两个实例同时启动会不会抢着改表？看 pg2 的日志：

```
msg="Locking database"
msg="Starting DB migrations"
msg="migrations completed" performed=0 skipped=719 duration=685.41µs
msg="Unlocking database"
```

**`performed=0, skipped=719`** —— pg2 发现迁移都做完了，一条都没执行。

> **这说明 Grafana 的迁移是带锁且幂等的**：多个实例可以安全同时启动，不会互相踩踏。

##### （5）什么时候必须换后端

综合实测，给出判据：

| 场景 | 建议 | 依据 |
|---|---|---|
| 单人 / 小团队，1 个实例 | **SQLite 够用** | 简单、零运维 |
| 需要 **≥2 个实例**（HA） | **必须换** | SQLite 文件无法共享 |
| 日志出现 `SQLITE_BUSY` | **必须换** | 锁竞争已实际发生 |
| 需要做**在线备份** | 建议换 | Postgres 可 `pg_dump` 热备 |
| dashboard 数 > 几百、用户 > 几十 | 建议换 | 并发写压力上升 |

⚠️ **容量标定声明**：上表的"几百""几十"是**经验性建议，不是实测阈值**。我没有做规模压测到 SQLite 崩溃点。真正的判据是**日志里的 `SQLITE_BUSY`**——那个是可观测的硬信号。

#### 示例演示：把现有实例迁到 Postgres

⚠️ **注意**：Grafana **没有官方的 SQLite→Postgres 自动迁移工具**。实用做法是"导出 JSON + 重新导入"：

```bash
curl -s --noproxy '*' -u admin:admin http://localhost:3001/api/dashboards/uid/l03-var-dash -o /tmp/export.json -w 'export=%{http_code}\n'
```

然后在新实例上导入。数据源、告警、用户需要分别导出处理。

⚠️ **未实测声明**：我没有做完整的 SQLite→Postgres 迁移演练。上面只是单条 dashboard 的导出验证（返回 200），**完整迁移涉及数据源凭据、服务账号 token（不可迁移，见 12.3）、告警规则等，需要另行验证**。

#### 常见误区

**误区 1：换 Postgres 是为了"更快"**

换后端主要解决的是**共享**和**并发写**，不是查询速度。Grafana 的查询都打到数据源，数据库只存配置。**换个更快的数据库不会让你的面板加载变快。**

**误区 2：HA 就是多起几个实例**

多起实例只解决了"实例挂了还有别的"。还有三件事要单独解决：**会话共享**（实测已自动）、**告警去重**（需额外配）、**文件上传/插件目录**（需要共享存储）。

**误区 3：会话共享要配 Redis**

实测：默认配置下 cookie 就能跨实例用，因为会话在数据库里。

#### 一句话记住

> **SQLite 是"一个人的记事本"，Postgres 是"团队的共享文档"——换后端不是为了快，是为了能有多个人同时写。**

---

### 12.3 升级与备份：升级前查什么、回滚靠什么

#### 一句话定义

**升级改的是数据库的 schema，而 schema 的变更是单向的——所以回滚不靠"降版本"，靠"恢复备份"。**

#### 直觉建立：手机系统升级

类比手机系统升级：

| 手机 | Grafana |
|---|---|
| 升级包改动系统文件 | 新版本跑 migration 改表结构 |
| 升级后一般不能降级 | 降级会让旧版读不懂新表 |
| 靠"恢复出厂 + 云备份"回退 | 靠"恢复数据库备份"回退 |
| 升级前先备份 | 一样 |

**类比失效的边界**：手机升级失败还能进 recovery 模式。Grafana 升级跑到一半挂了，数据库可能处于**中间状态**——既不是旧版也不是新版。

#### 核心原理

##### （1）备份到底要备份什么

先看 Postgres 后端里都有什么：

```
表总数 = 91
主要数据表: dashboard / dashboard_acl / dashboard_provisioning / dashboard_version
           data_source / user / user_auth_token / org_user / user_role
           api_key / permission / role / migration_log
```

一次完整的逻辑备份：

```bash
docker exec l12-pg pg_dump -U grafana -d grafana > /tmp/gf_backup.sql
```

```
exit=0  大小=440434 字节
文件头: -- PostgreSQL database dump --
```

**备份清单**（实测确认的）：

| 内容 | 位置 | 漏了会怎样 |
|---|---|---|
| **数据库** | `pg_dump` / `grafana.db` | 全部配置丢失 |
| **`grafana.ini`** | `/etc/grafana/grafana.ini` | 配置回退（100KB，实测） |
| **provisioning 目录** | `/etc/grafana/provisioning/` | 6 个子目录配置丢失 |
| **插件** | `/var/lib/grafana/plugins/` | 面板渲染失败 |
| **secret_key** | 配置项 / 环境变量 | **加密数据解不开**（见下） |

`grafana.ini` 实测 100630 字节，provisioning 有 6 个子目录：

```
access-control  alerting  dashboards  datasources  notifiers  plugins
```

##### （2）最关键的一条：token 恢复不了

这是课 11 留下的线索，本课用实验坐实。

我建了一个服务账号 token：

```
创建返回: {"id":1,"name":"bk-token","key":"glsa_8eOYKQXiapFzbdoDiLOEGyq6gOaLHQLk_…（已脱敏，末 4 位 ebd3）"}
```

**明文 `glsa_...` 只在创建时返回这一次。**

落库后查：

```
select id, name, left(key,30), service_account_id, is_revoked from api_key;
1|bk-token|e34d89904e5fdabbd35b50e1dc222f|2|f
```

**明文 `glsa_8eOYKQXiapFzbdoDiLOEGyq6gOaLHQLk_…（已脱敏，末 4 位 ebd3）` → 落库变成 `e34d89904e5fdabbd35b50e1dc222f`（32 位哈希）。**

我再把备份恢复到新库，查同一条记录：

```
恢复后 api_key: 1|bk-token|e34d89904e5fdabbd35b
```

**哈希原样恢复了，但明文 token 永远拿不回来。**

> **结论**：**备份能恢复"这条 token 存在"，不能恢复"这条 token 的明文"。** 所有用这个 token 的 CI、脚本、监控系统，在恢复后**必须重新生成 token 并更新配置**。

这是升级/迁移前必须通知所有相关方的一件事。

##### （3）跨版本实验：13.2.1 的库，12.0.0 能开吗

这是我做的最冒险也最有价值的实验。

**步骤**：

1. 先备份：`pg_dump` → 441519 字节，此时 `migration_log` = **719**
2. 停掉 13.2.1 的两个实例
3. 用 **12.0.0** 起一个实例，指向同一个库

**结果**（出乎意料）：

```
容器状态: Up 25 seconds
{
  "database": "ok",
  "version": "12.0.0",
  "commit": "4c0e7045f97f356716755b47183b22e7f12bb4bf"
}
health_http=200
```

**12.0.0 成功启动了，而且 `database: ok`。**

——表面上看，"降级是可行的"。

##### （4）但是：库被改了，数据"消失"了

先看数据库：

```
降级后 migration_log 数: 731    (原来 719，多了 12 条)
```

**12.0.0 又跑了 12 条迁移！** 看看是什么：

```
create playlist table v2
create playlist item table v2
Drop old table playlist table
Drop old table playlist_item table
Add UID column to playlist
Update uid column values in playlist
Add index for uid in playlist
create entity_events table
...
```

它按 **12.x 的标准** 重建了 playlist 表。**库已经不是原来的库了。**

**然后是关键的一幕**——查降级前建的 dashboard：

```
curl http://localhost:3007/api/dashboards/uid/ha-probe
{"message":"Dashboard not found"}    → 404
```

**`ha-probe` 不见了！**

##### （5）根因：13.x 换了存储层

为什么？我查了表的实际内容：

```
13.x 的 dashboard 存在 resource 表：
  dashboard.grafana.app|dashboards|default|ha-probe
  dashboard.grafana.app|dashboards|default|ha-probe2

传统 dashboard 表：
  select count(*) from dashboard;  →  0
```

**13.x 把 dashboard 存进了 `resource` 表（k8s 风格，`group/resource/namespace/name`），传统的 `dashboard` 表是空的。**

而 12.0.0 只读传统的 `dashboard` 表——所以看不见。

**反向验证**（这部分最关键）：我让 12.0.0 建一个 dashboard：

```
create_on_12=200
dashboard 表: 1|old-created|Created By 12.0.0
```

12.0.0 建的东西写进了**老表**。然后回到 13.2.1 去读：

```
13.2.1 读 12.0.0 建的 old-created = 404
```

**13.2.1 也看不见！**

> **结论：13.x 与 12.x 的 dashboard 存储是双向不可见的。**

13.2.1 启动日志直接说明了这一点：

```
msg="Unified migration configs enforced" storage_type=unified target=[all]
msg="Enforcing mode 5 for resource in unified storage" resource=dashboards.dashboard.grafana.app
msg="Enforcing mode 5 for resource in unified storage" resource=folders.folder.grafana.app
```

**13.x 默认启用了 unified storage（`storage_type=unified target=[all]`）**，这是架构级变更，不是加几张表那么简单。

⚠️ **未实测声明**：我没有测 12.x → 13.x 的**正向升级**是否自动完成数据迁移动（理论上 13.x 会读老表并迁移到 `resource` 表）。本实验只证明了**反向（13→12）会导致数据不可见**。

##### （6）回滚到底靠什么

回到 13.2.1：

```
docker start gf-pg1
{
  "database": "ok",
  "version": "13.2.1",
  ...
}
health=200

ha-probe  = 200   ✅
ha-probe2 = 200   ✅
```

数据"回来"了——因为它们一直在 `resource` 表里，只是 12.0.0 不认识。

**但 `migration_log` 已经是 731，不是 719。库已经被 12.0.0 改动过。**

所以回滚的正确姿势是**用备份恢复，不是换镜像**：

```bash
docker exec l12-pg psql -U grafana -d postgres -c 'create database gf_restore;'
docker exec -i l12-pg psql -U grafana -d gf_restore < /tmp/gf_before_downgrade.sql
```

```
恢复 exit=0
恢复后表数          = 91
恢复后 migration_log = 719    ← 回到降级前
恢复后 api_key      = 1|bk-token|e34d89904e5fdabbd35b
```

用恢复的库起一个新实例：

```
{
  "database": "ok",
  "version": "13.2.1"
}
ha-probe_on_restored = 200   ✅
```

**备份恢复完整可用，`migration_log` 精确回到 719。**

##### （7）升级前检查清单

基于以上实测：

| # | 检查项 | 怎么查 | 为什么 |
|---|---|---|---|
| 1 | **完整备份数据库** | `pg_dump` 或复制 `grafana.db` | 唯一可靠的回滚手段 |
| 2 | **备份 `grafana.ini` 和 provisioning** | 打包 `/etc/grafana/` | 100KB 配置，丢了重配很痛 |
| 3 | **确认升级路径** | 查官方升级文档 | 不支持跨多版本跳跃（核查于 2026-09） |
| 4 | **清点服务账号 token** | 查 `api_key` 表 | **明文恢复不了，必须重建** |
| 5 | **记录当前版本与 migration_log 数** | `/api/health` + `select count(*)` | 回滚后核对用 |
| 6 | **在副本上先升一次** | 用备份起一个测试实例 | 本课的做法 |
| 7 | **确认存储层变更** | 看启动日志 `storage_type` | 13.x 的 unified storage 是架构变更 |
| 8 | **停掉所有实例再升** | `docker stop` | 避免并发迁移 |

> **第 4 项最容易被漏**。备份恢复后 token 的哈希在、明文没了，所有依赖它的程序会静默 401。

#### 示例演示：一次完整的"备份 → 验证"

```bash
docker exec l12-pg pg_dump -U grafana -d grafana > /tmp/gf_before.sql
```

```bash
docker exec l12-pg psql -U grafana -d postgres -c 'create database gf_verify;'
```

```bash
docker exec -i l12-pg psql -U grafana -d gf_verify < /tmp/gf_before.sql
```

然后起一个实例指向 `gf_verify`，确认能起来、dashboard 在、能登录。**验证过的备份才叫备份。**

#### 常见误区

**误区 1：升级失败就把镜像换回旧版本**

实测：13→12 会让旧版读不到 dashboard（404），而且**旧版会继续改库**（跑 12 条迁移）。换镜像不是回滚，是**制造一个更复杂的烂摊子**。

**误区 2：备份了数据库就够了**

`grafana.ini`（100KB）、provisioning（6 个子目录）、插件目录、secret_key 都要备份。少了 secret_key，恢复后加密的 datasource 密码解不开。

**误区 3：token 备份了就能用**

实测：落库是 32 位哈希，明文不可恢复。

**误区 4：看到 `database: ok` 就没事了**

12.0.0 打开 13.2.1 的库，健康检查也是 `database: ok`，但 dashboard 全是 404。**健康 ≠ 数据可见。**

#### 一句话记住

> **升级前备份，回滚靠恢复——降级不是回滚，token 恢复不了。**

---

## 第四幕：实操验证

> 本幕所有命令均按出现顺序真实执行过。环境：WSL Ubuntu + Docker，Grafana 13.2.1 / 12.0.0，Postgres 16-alpine。

### 实验 1：起一个 Postgres 后端的 Grafana

```bash
docker run -d --name gf-pg1 --network l12net -p 3004:3000 -e GF_DATABASE_TYPE=postgres -e GF_DATABASE_HOST=l12-pg:5432 -e GF_DATABASE_NAME=grafana -e GF_DATABASE_USER=grafana -e GF_DATABASE_PASSWORD=grafana -e GF_DATABASE_SSL_MODE=disable -e GF_SECURITY_ADMIN_PASSWORD=admin grafana/grafana:13.2.1
```

```bash
curl -s --noproxy '*' http://localhost:3004/api/health
```

预期输出：

```
{"database":"ok","version":"13.2.1","commit":"56cd3e9288..."}
```

```bash
docker exec l12-pg psql -U grafana -d grafana -tAc "select count(*) from information_schema.tables where table_schema='public';"
```

预期输出：`91`

### 实验 2：HA——两个实例共享一个库

```bash
docker run -d --name gf-pg2 --network l12net -p 3005:3000 -e GF_DATABASE_TYPE=postgres -e GF_DATABASE_HOST=l12-pg:5432 -e GF_DATABASE_NAME=grafana -e GF_DATABASE_USER=grafana -e GF_DATABASE_PASSWORD=grafana -e GF_DATABASE_SSL_MODE=disable -e GF_SECURITY_ADMIN_PASSWORD=admin grafana/grafana:13.2.1
```

```bash
curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3004/api/dashboards/db -H 'Content-Type: application/json' -d '{"dashboard":{"uid":"ha-probe","title":"HA Probe From PG1","panels":[{"type":"text","id":1,"title":"t","gridPos":{"x":0,"y":0,"w":12,"h":8}}],"schemaVersion":41},"overwrite":true}' -o /dev/null -w 'create=%{http_code}\n'
```

预期输出：`create=200`

```bash
curl -s --noproxy '*' -u admin:admin http://localhost:3005/api/dashboards/uid/ha-probe -o /dev/null -w 'read_from_pg2=%{http_code}\n'
```

预期输出：`read_from_pg2=200` —— **pg1 建的，pg2 能读**

### 实验 3：会话共享

```bash
curl -s --noproxy '*' -c /tmp/c1.txt -X POST http://localhost:3004/login -H 'Content-Type: application/json' -d '{"user":"admin","password":"admin"}' -o /dev/null -w 'pg1_login=%{http_code}\n'
```

预期输出：`pg1_login=200`

```bash
curl -s --noproxy '*' -b /tmp/c1.txt http://localhost:3005/api/user -o /tmp/u2.json -w 'pg2_with_pg1_cookie=%{http_code}\n'
```

预期输出：`pg2_with_pg1_cookie=200` —— **cookie 跨实例有效**

### 实验 4：渲染 vs 查询

先起 renderer（**注意：必须设 `AUTH_TOKEN`，否则 401**）：

```bash
docker run -d --name l12-renderer --network l12net -p 8082:8081 -e HTTP_PORT=8081 -e AUTH_TOKEN=l12secrettoken123 grafana/grafana-image-renderer:latest
```

```bash
docker run -d --name gf-render --network l12net -p 3006:3000 -e GF_RENDERING_SERVER_URL=http://l12-renderer:8081/render -e GF_RENDERING_CALLBACK_URL=http://gf-render:3000/ -e GF_RENDERING_RENDERER_TOKEN=l12secrettoken123 -e GF_SECURITY_ADMIN_PASSWORD=admin grafana/grafana:13.2.1
```

> ⚠️ **两个坑**：① `GF_RENDERING_RENDERER_TOKEN` 不能用默认值，否则 Grafana **拒绝启动**（`Using the default [rendering]renderer_token is not allowed for production settings`）；② renderer 侧也要设**同名**的 `AUTH_TOKEN`，否则渲染请求 401。

```bash
curl -s --noproxy '*' -u admin:admin -o /dev/null -w 'api=%{time_total}s\n' -X POST http://localhost:3006/api/ds/query -H 'Content-Type: application/json' -d '{"queries":[{"refId":"A","datasource":{"uid":"promlab"},"expr":"up","instant":true}],"from":"now-1h","to":"now"}'
```

预期输出：`api=0.009~0.029s`

```bash
curl -s --noproxy '*' -u admin:admin -o /tmp/rr.png -w 'render=%{time_total}s size=%{size_download}\n' -m 120 'http://localhost:3006/render/dashboard-solo/db/rnd1?panelId=1&width=1000&height=500'
```

预期输出：`render=4.9~5.9s size=10063`

**渲染比查询慢约 500 倍。**

### 实验 5：token 落库形态

```bash
curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3004/api/serviceaccounts -H 'Content-Type: application/json' -d '{"name":"bk-test-sa","role":"Viewer"}'
```

返回里的 `id` 用于下一步（实测 `id=2`）：

```bash
curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3004/api/serviceaccounts/2/tokens -H 'Content-Type: application/json' -d '{"name":"bk-token"}'
```

预期输出（**明文只出现这一次**）：

```
{"id":1,"name":"bk-token","key":"glsa_8eOYKQXiapFzbdoDiLOEGyq6gOaLHQLk_…（已脱敏，末 4 位 ebd3）"}
```

```bash
docker exec l12-pg psql -U grafana -d grafana -tAc "select id, name, left(key,30) from api_key;"
```

预期输出（**明文变哈希**）：

```
1|bk-token|e34d89904e5fdabbd35b50e1dc222f
```

### 实验 6：降级实验（危险，务必先备份）

```bash
docker exec l12-pg pg_dump -U grafana -d grafana > /tmp/gf_before_downgrade.sql
```

```bash
docker exec l12-pg psql -U grafana -d grafana -tAc "select count(*) from migration_log;"
```

预期输出：`719`

```bash
docker stop gf-pg1 gf-pg2
```

```bash
docker run -d --name gf-old --network l12net -p 3007:3000 -e GF_DATABASE_TYPE=postgres -e GF_DATABASE_HOST=l12-pg:5432 -e GF_DATABASE_NAME=grafana -e GF_DATABASE_USER=grafana -e GF_DATABASE_PASSWORD=grafana -e GF_DATABASE_SSL_MODE=disable -e GF_SECURITY_ADMIN_PASSWORD=admin grafana/grafana:12.0.0
```

```bash
curl -s --noproxy '*' http://localhost:3007/api/health
```

预期输出（**注意：是 "ok"，但这是假象**）：

```
{"database":"ok","version":"12.0.0","commit":"4c0e7045f97f356716755b47183b22e7f12bb4bf"}
```

```bash
curl -s --noproxy '*' -u admin:admin http://localhost:3007/api/dashboards/uid/ha-probe
```

预期输出（**数据"消失"**）：

```
{"message":"Dashboard not found"}
```

```bash
docker exec l12-pg psql -U grafana -d grafana -tAc "select count(*) from migration_log;"
```

预期输出：`731` —— **库已被旧版改动**

### 实验 7：用备份恢复

```bash
docker exec l12-pg psql -U grafana -d postgres -c 'create database gf_restore;'
```

```bash
docker exec -i l12-pg psql -U grafana -d gf_restore < /tmp/gf_before_downgrade.sql
```

```bash
docker exec l12-pg psql -U grafana -d gf_restore -tAc "select count(*) from migration_log;"
```

预期输出：`719` —— **回到降级前**

```bash
docker run -d --name gf-restore --network l12net -p 3008:3000 -e GF_DATABASE_TYPE=postgres -e GF_DATABASE_HOST=l12-pg:5432 -e GF_DATABASE_NAME=gf_restore -e GF_DATABASE_USER=grafana -e GF_DATABASE_PASSWORD=grafana -e GF_DATABASE_SSL_MODE=disable -e GF_SECURITY_ADMIN_PASSWORD=admin grafana/grafana:13.2.1
```

```bash
curl -s --noproxy '*' -u admin:admin http://localhost:3008/api/dashboards/uid/ha-probe -o /dev/null -w 'restored=%{http_code}\n'
```

预期输出：`restored=200`

---

## 第五幕：体系收束

### 三个知识点的内在联系

```
        性能（12.1）          后端与 HA（12.2）        升级与备份（12.3）
             │                      │                        │
        慢在哪？              扛得住吗？               敢升级吗？
             │                      │                        │
     渲染 > 数据量 > 面板数    SQLite=单人 / PG=团队    回滚=恢复备份，非降级
             │                      │                        │
             └──────────────────────┴────────────────────────┘
                                    │
                          共同前提：都要先【量化】
                                    │
                    日志里的 SQLITE_BUSY / 响应体字节数 / migration_log 数
```

三个知识点表面独立，实际共享一个方法论：**不看文档说什么，看实测数字是什么。**

- 12.1 拒绝"面板多就慢"的直觉，用 80 倍面板只慢 4.5 倍的数据说话
- 12.2 拒绝"换 PG 是为了快"，用"SQLite 文件无法共享"的架构事实说话
- 12.3 拒绝"降级即回滚"，用"降级后 404 + 库被改"的实测说话

### 与前面课程的联系

本课是阶段 4 的收官，把前三课的能力合起来：

| 前课 | 本课的依赖 |
|---|---|
| 课 1 | `grafana.db` 92 张表、0 张时序表 → 12.2 换后端时知道在迁什么 |
| 课 6 | 变量 All 导致基数爆炸（21.8 倍）→ 12.1 基数是核心瓶颈 |
| 课 9 | 日志与链路 → 排查性能时的第三只眼 |
| 课 10 | provisioning 是配置的真相来源 → 12.3 备份必须含 provisioning |
| 课 11 | 服务账号 token 明文只显示一次 → **12.3 坐实：落库是哈希，备份恢复不了明文** |

课 11 埋的伏笔在本课收口：**token 的哈希存储，让"备份恢复"不等于"业务恢复"。**

### 本课方法论沉淀

**① 量化优于直觉**：三个"想当然"全部被实测推翻。给判据时，宁可说"这个我没测出阈值"，也不要编一个数字。

**② 健康检查不等于业务正常**：12.0.0 打开 13.2.1 的库，`database: ok` 但 dashboard 全 404。判据要落到**业务对象**上。

**③ 破坏性实验前先备份**：降级实验前我先 `pg_dump`。正因为有这份备份，才能证明"恢复到 719 是可行的"。

**④ 会话共享这类"应该很复杂"的事，可能默认就解决了**：实测 cookie 跨实例有效。不要照抄教程配 Redis，先测一下。

⚠️ **本课未实测清单**（诚实标注）：

1. **告警 HA 去重**（12.2）：pg2 返回空数组，但可能是启动时间不足。未做完整多周期验证
2. **12.x → 13.x 正向升级的数据迁移**（12.3）：只测了反向
3. **SQLite 并发击穿阈值**（12.2）：证明锁存在，未测崩溃点
4. **完整 SQLite → Postgres 迁移演练**（12.2）：只验证了单条 dashboard 导出

---

## 📌 本课速览

**12.1 性能**
- 面板数 1→80，耗时 7ms→32ms（**80 倍面板只慢 4.5 倍**），面板数是最次要瓶颈
- 时间窗 1h→7d，响应体反而**变小**（Grafana 自动放大步长：30s→2h）
- `maxDataPoints` 100→2000，响应体 **0.98MB→14.3MB（14.5 倍）**，这才是主开关
- 高基数比低基数慢 **13.5 倍**
- **渲染 4.9s vs 查询 9ms = 500 倍差距**，渲染是性能悬崖
- 排查顺序：**渲染 → 响应体/基数 → 面板数 → 时间窗**

**12.2 数据库后端与 HA**
- SQLite 并发写 10 次全 200，但日志有 **`SQLITE_BUSY` 重试到 retry=2、退避 199ms**
- SQLite 根本边界：**文件无法共享**，不能多实例
- 换 Postgres 只需改环境变量，**应用层零改动**，生成 91 张表
- HA 实测：配置**双向可见**、会话**默认共享**（cookie 跨实例有效，无需 Redis）
- 迁移是带锁幂等的：第二实例启动时 `performed=0, skipped=719`
- 判据：日志出现 `SQLITE_BUSY`、或需要 ≥2 实例 → 必须换

**12.3 升级与备份**
- 备份清单：数据库 + `grafana.ini`(100KB) + provisioning(6 目录) + 插件 + secret_key
- **token 明文 `glsa_...` 落库变 32 位哈希，备份恢复不了明文** → 恢复后必须重建
- 降级实验：12.0.0 打开 13.2.1 的库，**`database: ok` 但 dashboard 404**
- 根因：13.x 用 `resource` 表（unified storage），12.x 读老表，**双向不可见**
- 旧版会**继续改库**（migration_log 719→731），换镜像不是回滚
- **回滚 = 恢复备份**（实测恢复到 719，dashboard 200）

---

## 🧭 课程导航

**上一课**：[第 11 课：权限与服务账号](./lesson-11-权限与服务账号：谁能看、谁能改、程序怎么访问.md)
**下一课**：结课实战项目（Phase 3）

- [返回课程目录](../../../02-课程目录.md)
- [返回阶段 4 概览](../overview.md)
- [返回学习路径总览](../../../01-学习路径总览.md)

---

## 🚀 下一批接力提示词

```
请进行 Grafana 课程的结课实战项目（Phase 3）。

要求：
1. 复杂度须同时满足四门槛（A1-A6）：跨阶段综合、多知识点串联、有可验证交付物、需要自主决策
2. 必须复用前 12 课的实测环境（grafana-lab 3001 / grafana-prov 3002 / gf-pg1 3004 / l12-pg 5433 等）
3. 所有结论必须本机实测，不得凭记忆或文档推断；未实测须显式标注 ⚠️
4. bash 命令必须单行（禁止反斜杠续行），在 WSL 内以脚本文件方式执行
5. 交付前完成 pedagogy + learner 双视角评审，P0 清零并写入评审结论块
6. 交付后回写四处档案：00-学习档案.md / 00-评审清单.md / 阶段 overview.md / 02-课程目录.md + 01-学习路径总览.md

课 12 已沉淀的关键约束（实战项目需遵守）：
- 性能排查顺序：渲染 → 响应体/基数 → 面板数 → 时间窗（面板数优先级最低）
- HA 会话默认随数据库共享，cookie 跨实例有效，无需配 Redis
- token 落库是哈希，备份恢复不了明文，恢复后必须重建
- 13.x 用 unified storage（resource 表），与 12.x 数据双向不可见
- 回滚 = 恢复备份，不是降级换镜像
```
