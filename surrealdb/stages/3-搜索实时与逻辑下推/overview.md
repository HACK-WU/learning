# 阶段 3 · 搜索、实时与逻辑下推

> **故事章节**：「数据库不只是存」——主角获得"主动"能力。不只是被动存取，还能搜、能推、能算。

[← 返回课程目录](../../02-课程目录.md)

---

## 一、阶段目标

学完本阶段你应该能够：

1. 为不同查询模式**选对索引**，并能用 EXPLAIN 判断索引是否被真正用上
2. 配置和查询**全文检索**（FULLTEXT ANALYZER + BM25），理解它与 Elasticsearch 的能力边界
3. 建**向量索引**做 KNN 语义搜索，并能把向量、图、结构化过滤**融合进一条查询**（Graph RAG）
4. 用 **LIVE SELECT** 做实时订阅、用 **DEFINE EVENT** 做触发器，并说清二者分工与适用边界
5. 把业务逻辑**下推到数据库**：自定义函数、DEFINE API 端点、COMPUTED 字段与视图
6. 知道 **GraphQL 接口**什么时候该用、什么时候不该用

---

## 二、本阶段在故事主线中的位置

| 叙事要素 | 内容 |
|----------|------|
| **承接** | 阶段 2 已能把数据存进去、查出来、连成图 |
| **转折** | 但"存得下"不等于"用得好"——真正的考验是搜索、实时和逻辑 |
| **冲突升级** | 语义搜索要向量库、全文要搜索引擎、实时推送要消息队列……说好的"一个库"呢？ |
| **阶段出口** | 能构建一个带语义搜索 + 图推理 + 实时推送的最小 RAG 原型 |

---

## 三、必须掌握的知识点

### 课 6：索引与全文检索

| # | 知识点 | 关键点 | 状态 |
|---|--------|--------|------|
| 6.1 | 索引类型：普通 / UNIQUE / 复合 / COUNT | DEFINE INDEX（FIELDS≙COLUMNS）/ ⚠️ **UNIQUE 会挡 UPSERT（三条规则）** / 复合索引**左前缀原则** / ⚠️ **COUNT 索引不能带 FIELDS** | ✅ |
| 6.2 | 全文检索：FULLTEXT ANALYZER 与 BM25 | 三段拼装 / ⚠️ **ANALYZER 必须显式写**（不写默认 `like` 不存在，查询才报） / ⚠️ **`score(N)` 的 N 对应 `@N@` 编号** / ⚠️ **语料太少 score 恒 0** / 中文开箱不可用 | ✅ |
| 6.3 | 查询计划与 EXPLAIN | ⚠️ **3.x 语法已变**（前缀式 + `ANALYZE`，骨架的 `EXPLAIN FULL` 报错） / IndexScan vs TableScan / 四类失效原因 / WITH INDEX / NOINDEX | ✅ |

### 课 7：向量与混合检索

| # | 知识点 | 关键点 | 状态 |
|---|--------|--------|------|
| 7.1 | 向量字段与 HNSW 索引 | ⚠️ **3.0 移除 MTREE**（连解析都过不去）/ ⚠️ **不写 `DIST` 默认 `EUCLIDEAN` 不是 `COSINE`** / `DIMENSION` 必须匹配 / 3.1+ 新增 DISKANN | ✅ |
| 7.2 | KNN 与相似度函数 | ⚠️ **`<\|K,EF\|>` 的 K 是硬上限**（骨架写 `<\|DIM,EFC\|>` 两参名均错）/ ⚠️ **结构化过滤可下推**（与官方博客相反）/ ⚠️ **无索引写数字 EF → 静默降级、dist 全 null** | ✅ |
| 7.3 | 混合检索与 Graph RAG | ⚠️ **`search::rrf()` 是 `(lists, limit, k)`** / `search::linear()` 需 4 参且 norm 必需 / ⚠️ **KNN 与全文 `@N@` 不能同 WHERE（静默 `[]`）** | ✅ |

### 课 8：实时：LIVE 与 EVENT

| # | 知识点 | 关键点 | 状态 |
|---|--------|--------|------|
| 8.1 | LIVE SELECT 实时订阅 | ⚠️ **Python SDK `subscribe_live()` 丢 `action`**（三种通知长得一样）/ ⚠️ **WHERE 只过滤「变更后」状态**（80→85 照样推，不是阈值告警）/ HTTP 端点明确报 `LiveQueryNotSupported` / 断连即亡不补发 | ✅ |
| 8.2 | DEFINE EVENT 触发器 | ⚠️ **THEN 里 `UPDATE $this` 会递归 23 层且主写入整体回滚** / ⚠️ **把 `$this` 当值用（`SET x = $this` 或 `$this.id`）会静默丢字段**（2026-09-03 更正：两者都会丢，须写 `$after.id`；`$this` 作语句目标有效）/`$after` 在 DELETE 时为 NONE / **事件失败连带回滚主写入** / ASYNC 自动补 `RETRY 1 MAXDEPTH 3` | ✅ |
| 8.3 | 实时能力的边界 | ⚠️ **离线期间补发 0 条**（MQ 补发 5 条）/ **广播语义，两个订阅者各收一份** / 400 订阅无硬上限 / 扇出成本仅约 1.2x / 3.2 孤儿 LIVE 指标是**计数器**非自动回收 | ✅ |

### 课 9：逻辑下推：函数、API 与视图

| # | 知识点 | 关键点 | 状态 |
|---|--------|--------|------|
| 9.1 | DEFINE FUNCTION 自定义函数 | ⚠️ **以「调用者」权限运行**（骨架"受限于创建者权限"本机未复现）/ ⚠️ **动态作用域**（能读到调用者的 `LET`）/ `fn::` 前缀强制 / `PERMISSIONS` 在 `}` 之后 / 函数体可写 / 无限递归被拦 | ✅ |
| 9.2 | DEFINE API：用 SurrealQL 写 HTTP 端点 | ⚠️ **语法是 `FOR` 不是 `METHOD`** / 路径 `/api/:ns/:db/端点名` / ⚠️ **body 只允许 NONE/bytes/string**（对象走真实 HTTP 一律 500） / ⚠️ **`$request.body` 是字节数组** / 默认 `PERMISSIONS FULL`（匿名可调 + 系统权限） / CVE-2026-63735 在 3.2.4 已修复 | ✅ |
| 9.3 | COMPUTED 字段与 VIEW | `FUTURE` 语法 3.x 已移除 / COMPUTED **读时重算**且不能建索引 / ⚠️ **`@this` 被解析成 `@.this`** / ⚠️ **COMPUTED 不能做 `updated_at`**（课 8 遗留定论）/ VIEW 只读、随源表实时变、**可建索引且真被用上** | ✅ |
| 9.4 | GraphQL 与多接口并存 | ⚠️ **须 `DEFINE CONFIG GRAPHQL AUTO`**（漏 `AUTO` 等于 `TABLES NONE`，不报错但一张表都不暴露）/ 头名 `surreal-ns`/`surreal-db` / schema 由字段定义生成（**SCHEMALESS 表无字段可查**）/ 表名转驼峰 / **id 只给 ID 部分** / 错误也返回 200 | ✅ |

**合计**：13 个知识点（按四份课骨架实测统计：3+3+3+4）

---

## 四、认知阶梯

| 层 | 覆盖知识点 |
|----|-----------|
| **感知层** | 6.1 索引类型（先知道有哪几种） |
| **概念层** | 6.2 全文检索、7.1 向量与 HNSW |
| **机制层** | 6.3 EXPLAIN、7.2 KNN、8.1 LIVE、8.2 EVENT、9.3 COMPUTED 与 VIEW |
| **实操层** | 7.3 混合检索、9.1 自定义函数、9.2 DEFINE API |
| **定位层** | 8.3 实时边界、9.4 GraphQL 取舍 |

---

## 五、本阶段的高频困惑点（预判）

1. **"HNSW 参数怎么调？"** → DIMENSION 必须匹配嵌入维度，EFC/M 影响召回率与内存，课 7 会给调参直觉
2. **"全文检索能替代 Elasticsearch 吗？"** → 能覆盖中小规模，但分析器生态与聚合能力差距明显，课 6 会正面给边界
3. **"LIVE SELECT 能替代消息队列吗？"** → 不能。课 8 会与 RabbitMQ 对照，给出明确分工线
4. **"为什么我要把逻辑放进数据库？"** → 这是可争论的设计决策，课 9 会给出正反两面与判断标准

---

## 六、阶段状态

| 项 | 值 |
|---|---|
| 状态 | ✅ **已完成**（课 6、课 7、课 8、课 9 全部交付） |
| 已完成知识点 | 13 / 13 |
| 开始日期 | 2026-09-02 |
| 完成日期 | 2026-09-02 |

**课 9 已沉淀结论**：

1. **⚠️ 函数以「调用者」权限运行，不是创建者**：三组对照（直接读 / 通过函数读 / 通过函数写）低权限用户全部返回 `[]`，root 复查源表未被污染。骨架写的"受限于创建者权限"在 3.2.4 上**没有复现**。→ **函数不是提权后门。**
2. **⚠️ 函数体是动态作用域，不是词法作用域**：同一函数在不同调用环境下返回不同结果（`fn::who()` 依次返回 `null`/`ctx_A`/`ctx_B`）。嵌套调用时中间层的 `LET` 会遮蔽外层。**这是一把双刃剑——省了传参，但函数行为依赖调用现场。**
3. **函数名必须带 `fn::` 前缀**；`PERMISSIONS` 子句写在函数体 `}` **之后**（写在参数后报 `expected {`）；参数个数与类型都校验；`fn::fact(5)`=120 正常，无限递归被 `Reached excessive computation depth` 拦住。
4. **⚠️ `DEFINE API` 的语法在 3.x 是 `FOR GET` 不是 `METHOD GET`**：后者报 `Parse error: Unexpected token an identifier`。可用方法六个：DELETE/GET/PATCH/POST/PUT/TRACE。
5. **端点路径必须带 `/api/:ns/:db/`**：直接打 `/api/ping` 全部 404。
6. **⚠️ 响应 `body` 只允许 NONE / bytes / string**：给对象或数组走真实 HTTP 一律 500（`body must be None, bytes, or string`）。**最阴险的是 `api::invoke()` 内部调用完全正常**——只在真实 HTTP 路径上暴露。→ **端点必须走真实 HTTP 验证一遍。**
7. **⚠️ `$request.body` 是字节数组不是对象**（静默失败第八次）：实测为 `[123, 34, 110, ...]`。直接 `.name` 静默得到 `NONE`，字段写空且不报错。正确做法 `LET $b = encoding::json::decode(type::string($request.body))`，**且必须防空体**（`decode("")` 会 500）。
8. **端点默认 `PERMISSIONS FULL` = 匿名可调 + 以系统权限运行**：匿名 GET 能读到 `PERMISSIONS NONE` 的表。收紧后匿名 403 / root 200；`PERMISSIONS NONE` 连 root 也 403。→ **公网端点必须显式收紧。**
9. **CVE-2026-63735（8.1 HIGH，CWE-639）在 3.2.4 已修复**：隔离实例双租户复现，租户 A 用户打 `/api/tenantB/...` → 403。**但 `/sql` 端点仍按 token 会话走**，不跟随 URL 上的 ns/db——修复是端点层的，不要把 `/sql` 直接暴露给租户。
10. **`FUTURE` 语法在 3.x 已移除**，报 Parse error。3.0 起统一用 `COMPUTED`。
11. **COMPUTED 是「读时算」且不能建索引**：连读同一记录值每次都不同；外部写入被计算值覆盖；建索引报 `Computed fields cannot be indexed`。
12. **⚠️ `COMPUTED @this.price` 被解析成 `@.this.price`**（静默失败第九次）：`INFO FOR TABLE` 回显确证，求值报 `Cannot perform multiplication with 'none' and 'none'`。用裸名或 `$this`。
13. **⚠️ 课 8 遗留定论：COMPUTED 不能替代 EVENT 做 `updated_at`**：连读四次每次都变；`VALUE time::now()` 才是"写入时算一次"，适合 `created_at`。
14. **VIEW 只读、随源表实时变、可建索引且真被用上**：三种写操作全被拒；源表改 100→500 VIEW 跟着变；EXPLAIN 见 `IndexScan [index: ix_amount]` vs `TableScan`。→ **要按派生值查询就上 VIEW**（课 6「写完索引就 EXPLAIN」规矩的第三次应用）。
15. **⚠️ `DEFINE CONFIG GRAPHQL` 不带 `AUTO` 等于 `TABLES NONE FUNCTIONS NONE`**（静默失败第十一次，本课最隐蔽的坑）：不报错，但一张表都不暴露，且报错指向"数据库里没表"，导致排查方向完全错误。5 组交替实验可逆复现。→ **配置类语句生效后必须用回显确认真实状态（`INFO FOR DB` 看 `configs`），不能靠"没报错"推断。**
16. **GraphQL 请求头是 `surreal-ns` / `surreal-db`**（用 `NS`/`DB` 报 `No namespace specified`）；**schema 由字段定义生成**，SCHEMALESS 表查不出任何字段 → **想用 GraphQL 暴露的表就该定义为 SCHEMAFULL**（课 3 的同一决定的另一面）。
17. **GraphQL 命名约定**：表名转驼峰（`gq_book`→`gqBook`/`gqBooks`）；复数=列表、单数=单条；**`id` 只给 ID 部分，给全限定 ID 静默返回 null**（静默失败第十次）；`order: {desc: year}`；错误也返回 HTTP 200（须解析 `errors`）。
18. **VIEW 在 GraphQL 层连 mutation 都不生成**：比 SQL 层的拒绝更彻底，前端连写入入口都没有。SCHEMAFULL + VIEW 组合是给前端开 GraphQL 的推荐姿势（已实测跑通）。
19. **静默失败链更新至第十一次**：本课贡献四次，共同点是**都发生在跨层边界上**（HTTP↔SurrealQL 类型、解析器↔语义、GraphQL ID↔Record ID、配置语法↔生效范围）。新增对策：**数据跨越表示形式边界时必须额外验证**。
20. **工程改进**：本课建了块级运行器 `playground/l09-run.py`（按 `-- ##` 切块逐条 POST），是课 4「整批一次 POST 被一条坏语句炸掉」教训的工程化落地。

**课 8 已沉淀结论**：

1. **LIVE 是「在线者广播」，不是「持久化队列」**：依赖 WebSocket（HTTP `/sql` 明确报 `LiveQueryNotSupported`），返回的是订阅 UUID 而非结果集。
2. **⚠️ Python SDK 的 `subscribe_live()` 只透传 `result`，把 `action` 丢了**（静默失败第六次）：CREATE/UPDATE/DELETE 三条通知结构完全相同。需要区分动作时必须用原始 WebSocket JSON-RPC。
3. **推送格式 5 字段**：`action` / `id`（订阅 UUID）/ `record`（记录 ID）/ `result`（内容或 DIFF 补丁）/ `session`（来源会话，可用于排除自己的变更——**LIVE 不自动排除发起者**）。
4. **⚠️ WHERE 只过滤「变更后」的状态，不是「跨越阈值才推」**：`temp > 50` 下，20→90 推、90→10 不推、但 **80→85 也推**（仍在窗口内）。**LIVE 不能直接当阈值告警用**，那要用 EVENT。
5. **生命周期三坑**（全部实测）：① 断连期间写 3 条 → 重连后收 0 条，且服务端随连接清理订阅（KILL 旧 uid 报 `Cannot execute KILL statement`）② 重连后无初值（存量 5 条一条不推）③ 会收到自己的变更。→ **正确姿势：先 SELECT 拉全量，再 LIVE 订阅增量，断连重来。**
6. **DIFF 模式**：`LIVE SELECT DIFF` 把 `result` 从完整记录换成 JSON Patch（UPDATE 为 `[{"op":"replace","path":"/age","value":41}]`）。非 DIFF 模式下 **DELETE 推的是被删记录的内容，不是 null**。
7. **⚠️ THEN 里 `UPDATE $this` = 递归爆炸**：嵌套 23 层后报 `Reached excessive computation depth`，**且原始 UPDATE 被整体回滚**（`v` 仍为 1）。解法是加守卫条件让第二次不满足 WHEN（如 `AND $before.touches IS NONE`）。
8. **⚠️ 把 `$this` 当值用会静默丢字段**（静默失败第七次）：`SET x = $this` **和** `SET x = $this.id` 都会让字段静默消失。根因是 EVENT 的 THEN 里 `$this` 作「值」时**恒为 NONE**（`type::of($this)` 在 CREATE/UPDATE/DELETE 三事件下均返回 `"none"`），`$this.id` 是对 NONE 取属性。**永远写 `$after.id`**（DELETE 事件用 `$before.id`）。注意 `$this` 作**语句目标**（`UPDATE $this SET ...`）是有效的，只有当值用才失效。
   > **2026-09-03 更正**：此处原写「`$this.id` 正常，永远写 `$this.id`」是**误判**——原对照探针 `l08-probe-82h.py` 在 5 个变体间未清空结果表，导致全变体误判成功。逐变体清表重测（`l08-probe-82h-fixed.py`）后仅 `$after.id` / `$before.id` / 字面量有效，`type::string($this)` 虽出字段但值为 `"NONE"`。详见课 8 正文。
9. **`$after` 在 DELETE 事件里是 NONE**，要取被删内容用 `$before`；`$value` 在 3.2.4 实测也是 NONE。
10. **事件失败会连带回滚主写入**：`THROW` 让 CREATE 报 Internal 错且记录未写入；事务内则 `Cannot COMMIT: the transaction was aborted`。**EVENT 是强一致的一部分，不是事后补偿。**
11. **`1/0` 在 SurrealQL 返回 `null` 不报错**——制造确定性失败要用 `THROW`（这条救了我一次，否则会误判"事件失败不回滚"）。
12. **ASYNC 事件的隐藏默认值**：`INFO FOR TABLE` 回显服务端自动补 **`RETRY 1 MAXDEPTH 3`**（`MAXDEPTH` 就是防递归闸门）。骨架未提。
13. **同表多事件按定义顺序执行**；THEN 可跨表写入；`DELETE $this` 可删自己且不递归。
14. **⚠️ LIVE 与 MQ 的分水岭（两条决定性证据）**：消费者离线期间写 5 条 → LIVE 补发 **0 条**（MQ 补发 5 条）；两个订阅者 → **各收一份**（广播，非竞争消费）。→ **要「在线的人看到最新状态」用 LIVE；要「这活儿一定有人干完」用 MQ。**
15. **扇出成本存在但很弱**：固定表大小、0→120 订阅，中位数 1178µs → 1402µs（约 1.2x）。400 个订阅全部建立成功，未见硬上限。**真正的成本是连接数与内存，不是单次写入延迟。**
16. **⚠️ 性能测量方法论（本课最重要的过程教训）**：第一轮朴素递增给出 861→2186µs（2.5x）的**错误结论**；反向回测发现「回到 0 订阅反而最慢（2730µs）」；交替 A/B 显示基线自身从 1325 漂到 2406µs；分离变量才确认表大小效应可忽略、订阅数效应约 1.2x。**性能测量必须有反向回测或同时刻基线，否则测到的是漂移而不是效应。**（课 6「规模相关机制」规矩的第三次验证）
17. **3.2 的孤儿 LIVE 指标是「计数器」不是自动回收**：官方原文为 counter，用于观察失去所属会话的 LIVE 注册。实测断连后服务端会随连接清理，正常断开不留孤儿。
18. **安全边界**：KILL 越权（GHSA-gcwr-5mrf-fvch）在 3.2.4 **已修复**（实测低权限用户 KILL root 订阅被拒）；LIVE 订阅存活绕过权限（GHSA-4m82-p8cx-f94j）3.2.0 修复。另：**`DEFINE USER ... ON DATABASE` 在 3.x 已废弃**，能执行但 signin 失败，应改用 `DEFINE ACCESS ... TYPE RECORD`。

**课 7 已沉淀结论**：

1. **向量检索两条路**：HNSW（`<|K,EF|>`，近似、快，图常驻内存）vs 暴力（`<|K,DIST|>` 或 `vector::similarity::*`，精确、慢）。**查询写法必须与索引严格配对**，配错不报错。
2. **⚠️ 无索引却写数字 EF → KNN 静默降级**：`dist` 全 `null`，EXPLAIN 里连 `KnnTopK` 都没有。**排查手段唯一：写完 KNN 就 EXPLAIN 找 `KnnScan`/`KnnTopK` 算子。**
3. **⚠️ 不写 `DIST` 默认是 `EUCLIDEAN` 不是 `COSINE`**——文本嵌入场景省写这一个词，结果全偏且不报错。
4. **`MTREE` 在 3.0 语法已移除**（不是废弃），报 `Parse error`；`DIST MINKOWSKI` 必须带阶数。
5. **`DIMENSION` 必须等于嵌入维度**，不符报 `Incorrect vector dimension (3). Expected a vector of 4 dimension.`（这条报错很友好）。
6. **`<|K,EF|>`：K 是返回条数（硬上限，`LIMIT` 突破不了），EF 是搜索力度**。EXPLAIN 直接打印 `k: 5, ef: 40`。
7. **EF 太小会真的漏结果**：300 条数据上 EF=1 只召回 3 条且全错，EF=40 起与暴力搜索一致。8 条数据时 EF 差异完全看不出来——**规模相关机制验证前先问数据量够不够**（课 6 教训的第二次验证）。
8. **结构化过滤会下推到 HNSW 遍历**（与官方博客"KNN 必须独占 WHERE"相反）：10 条交替类别数据上 `<|5,40|> AND cat="tech"` 返回满 5 条，EXPLAIN 显示谓词进了 `KnnScan`。
9. **⚠️ KNN 与全文 `@N@` 不能写在同一 WHERE**：静默返回 `[]`，换顺序也一样。混合检索必须两路各查各的再融合——**这本来也符合 RRF 的设计前提**。
10. **⚠️ `search::rrf()` 签名是 `(lists, limit, k)`**：官方两处文档矛盾；我初稿还判反了。**决定性实验**（候选 6 条 > limit，两参互换）给出条数与分数量级双重证据。教训：验证"某参数是不是 limit"时候选数必须明显多于 limit，否则"没截断"是伪信号。
11. **`search::linear()` 需 4 个参且 `norm` 必需**（`minmax`/`zscore`），两种归一化**不等价**（zscore 可出负值且改变排序）。默认用 rrf（零调参），确信某路更重要时才用 linear。
12. **Graph RAG 一条查询跑通**：向量召回 → `search::rrf()` 融合 → `->belongs_to->doc` 一跳 → `->cites->doc` 两跳扩展上下文。
13. **`OMIT embedding` 对 KNN 查询无效**，需显式投影；`search::highlight()` 需索引带 `HIGHLIGHTS` + 查询用带编号 `@N@`。
14. **静默失败链第五次出现**，本课新增对策：**写完 KNN 就 EXPLAIN 找算子**；**混合检索一定分两路查**；**融合分数只排序不过滤**；**验证 limit 时候选数要多于 limit**。

**课 6 已沉淀结论**：

1. **索引是"目录"不是"数据"**：普通管定位、UNIQUE 管唯一、复合按**左前缀**命中、COUNT 给 `count()` 开常数时间通道（300 行实测 124µs vs 431µs，仅示趋势）
2. **UNIQUE 会挡住 UPSERT**：拦的是"最终撞车"（改到别人的值 / 新记录撞已存在值），**不拦"原地更新"**（同 id 同值）
3. **COUNT 索引不能带 `FIELDS`**，带则报 `Cannot create a count index with fields`
4. **全文检索三段拼装**：ANALYZER 切词 → INDEX 挂字段+BM25 → `@N@` 查询加权；**任一段缺失只在查询时暴露**
5. **`ANALYZER` 必须显式写**：不写会默认用不存在的 `like`，定义与插入都不报错，只有查询时报 `The analyzer 'like' does not exist`
6. **`search::score(N)` 的 N 对应 `@N@` 编号**，必须传 0..255 整数；这是多字段加权排序的核心机制
7. **文档太少时 score 恒为 0**（BM25 的 IDF 依赖语料量）：实测 2 条为 0、**3 条起出分**。验证打分前务必灌足语料
8. **`@@` 等价于 `@AND@`**（全词都要有），`@OR@` 才任一命中；**默认无前缀匹配、无词干还原**
9. **中文开箱不可用**：`class` tokenizer 把整串中文当一个 token（"分词" 查 "中文分词测试" 为空）
10. **3.x 的 EXPLAIN 已改为前缀式**，`FULL` → `ANALYZE`；判读看 `IndexScan`（好）vs `TableScan`（查）
11. **类型不匹配时仍走 IndexScan**——计划好看但结果可能不对，EXPLAIN 只告诉你效率，不告诉你正确性

---

## 七、与其他阶段的关联

- **前置依赖**：阶段 2 全部（尤其课 3 字段定义、课 5 图遍历）
- **后续依赖**：阶段 4 课 12 选型决策的核心论据大部分来自本阶段的能力边界
- **交叉引用**：课 6 全文检索与 `elasticsearch/` 课程对照；课 8 实时与 `rabbitmq/` 课程对照

---

## 课程导航

- 上一阶段：[阶段 2 · 核心数据模型与 SurrealQL](../2-核心数据模型与SurrealQL/overview.md)
- 阶段概览：[阶段 3](./overview.md)
- 下一阶段：[阶段 4 · 权限、部署与生产决策](../4-权限部署与生产决策/overview.md)
- [← 返回课程目录](../../02-课程目录.md)
