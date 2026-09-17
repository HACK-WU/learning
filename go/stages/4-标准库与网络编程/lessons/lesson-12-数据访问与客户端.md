# 课 12：数据访问与客户端

> 所属阶段：标准库与网络编程 ｜ 故事章节：让它对外提供服务 ｜ 状态：✅ 已完成 2026-09-13 ｜ 本机实测：go1.27.1 darwin/arm64

---

## 🎯 本课目标

学完这一课，你应该能：

- 把 `sql.DB` 当**进程级连接池**用而不是"一条连接"：说清 `Open` 为什么"可能一条连接都不建"、四个连接池参数的零值各是什么意思、`Query` 与 `Exec` 的分工、`rows.Scan` 与 `defer rows.Close()` 的纪律，并用**参数化查询**把 SQL 注入挡在外面。
- 配出一个"不会把连接池跑死"的 `http.Client`：知道**默认 Client 没有超时**、`Client.Timeout` 连"读 body"也一起管、`resp.Body` 必读必关（并说清 **Go 1.27 起"关"本身就会异步帮你读一部分**）、`Transport` 的几个连接池参数各挡什么，以及**重试只在幂等请求上做、必须有上限和退避**。
- 看懂 `time.Time` 里那个**单调时钟**读，用 `time.Since` 而不是 `time.Now().Sub(t)` 算间隔，正确使用与清理 `Ticker` / `Timer`（含 `Reset` 的坑与"到底要不要 `Stop`"的版本变化），并能用 `2006-01-02 15:04:05` 这个魔数布局串做格式化和解析。

---

## 📍 本课在故事主线中的情节定位

> **故事章节：让它对外提供服务。** 上一课（课 11）小谷把重写后的下单服务挂到了网上——路由、请求、响应、超时、优雅关闭全都打通了。但那只服务是个"孤岛"：它能收请求，却还不能**落库**，也不能**调别人**。这一课，他要把"服务"真正接到数据上。

### 先合拢课 11 埋下的伏笔

课 11 埋了六处线头，这一课全部要收掉。注意第一行——**课 11 只打通了取消链路的前半段，后半段就在这里**：

| 课 11 学的 | 课 12 里它落在哪 |
|---|---|
| 知识点 2：**`r.Context()` 就是课 10 那棵取消树的落点** | **这是本课知识点 1 的最后一环。** 课 11 只证明了"客户端断开 → `r.Context()` 被取消"；本课把它接进数据库：`db.QueryRowContext(r.Context(), …)`。**实测：客户端 400 ms 放弃的同一瞬间，服务端那条慢查询被掐断**（`查询返回：err=context canceled 耗时=400ms`）；对照版用裸 `QueryRow` → 查询**完整跑完**（`查询返回：err=<nil> 耗时=1.425s`）。**"客户端一断，数据库查询就被取消"这条链路，到这里才闭环。** |
| 知识点 2：*"The Server will close the request body. The ServeHTTP Handler does not need to."* | 课 11 用一句话带过了**服务端**侧；本课把**客户端**侧完整拆开——`resp.Body` 必须自己关，而且"读完"这件事的作用在 Go 1.27 变了。**6 种关闭/读取写法 × 连接是否复用**，本课逐条实测。 |
| 知识点 3：`Shutdown` 的轮询上限 `500 ms` | 那个 500 ms 轮询**就是一个定时器**。本课知识点 3 讲 `Ticker` / `Timer` 在服务端到底该怎么用、怎么收。 |
| 知识点 3：超时三件套（**服务端**侧：`ReadTimeout` / `WriteTimeout` / `IdleTimeout`） | 本课知识点 2 是**客户端**侧的超时：`Client.Timeout` 覆盖"连接 + 重定向 + 读完 body"，与课 11 那三个各管一段。**同一个服务，做服务端和做客户端的超时是两套东西**，别混。 |
| 知识点 1：中间件是 `func(http.Handler) http.Handler` | 本课所有 `http.Client` 探针都复用课 11 那套写法：`mux.HandleFunc` + `net.Listen("127.0.0.1:0")` + `http.Server` 起真服务，不打桩。 |
| 实操 3.5 的教训：本地 `curl` 要加 `--noproxy '*'` | 本课继续用；**并且多测了一件事**：Go 自己的 `http.Client` **不需要**这个——`httpproxy` 源码里硬编码排除了 `localhost` 与回环 IP 地址（`if ip.IsLoopback() { return false }`）。**"代理坑"是 `curl` 的坑，不是 Go 的坑。** |

### 本课在阶段 4 里的位置

```
课 10  io 与 context      ——  数据怎么流、怎么停（能流动）
课 11  net/http 服务端     ——  怎么把它挂到网上（能对外）
课 12  数据访问与客户端     ——  ★ 本课：怎么存下来 + 怎么访问别人（能存取）
```

一句话概括本课的转折：**课 11 服务是"被动"的——等着别人来连；课 12 让它"主动"起来——自己出去连数据库、连下游服务，而"主动"这件事的全部难度都在"连出去的东西是有成本、有寿命、会失效的"。**

课 10 → 课 11 → 课 12 三课共用**同一条主线**：

| 课 | 一句话 | 它管的资源 |
|---|---|---|
| 课 10 | 数据是流，取消是树 | `io.Reader` / `context`（**抽象的流与信号**） |
| 课 11 | 流从哪来、到哪去、何时掐断 | `net.Conn` / `http.Server`（**进来的连接**） |
| 课 12 | 流怎么存下去、怎么取回来 | `sql.DB` 连接池 / `http.Transport` 连接池 / 定时器（**出去的资源与时间**） |

**三课合起来是一个统一的法则**：*任何有寿命的资源，都必须有"上限、超时、关闭"三件套。* 课 11 把它用在 `http.Server` 上，课 12 把它用在数据库连接池、客户端连接池和定时器上。

### 三个真实需求（第一幕的场景来源）

小谷这次要交的不是"能跑"，而是"能上线并且不会被下游拖死"：

1. **下单要真正落库，而且不能把数据库连接打爆。** 他的第一版是"每次请求都 `sql.Open` 一次"——本地单机测试看不出问题，一上压测数据库侧连接数就炸。
2. **下单要调下游（库存、风控），客户端必须"能等、会放弃、失败能安全重试"。** 他第二版的问题是压测到一半，客户端这边报"连不上"——查了半天发现是**请求发出去了，但响应体没读也没关**，连接池被自己占满了。
3. **"订单 15 分钟未支付自动取消"要跑在服务端，跑一个月不能越跑越占内存。** 他在热路径循环里用 `time.After` 做超时检测，又有一个 `Ticker` 忘了 `Stop`——线上跑久了 RSS 一路涨。

---

## 📌 知识点导航

| # | 知识点 | 关键点 | 状态 |
|---|--------|--------|------|
| 1 | database/sql | ①`sql.DB` 是**连接池**不是单个连接，应全局复用，不要每次请求 Open ②`Query` vs `Exec` 的分工 ③`rows.Scan` + **`defer rows.Close()`** ④参数化查询防 SQL 注入 | ✅ 已完成 2026-09-13 |
| 2 | http.Client | ①**默认 Client 没有超时**，生产必须显式设 `Timeout` ②`resp.Body` **必须读完并关闭**，否则连接无法复用、会耗尽连接池（⚠️ **Go 1.27 起"读完"的门槛变了**）③`Transport` 与连接池参数（`MaxIdleConns` 等）④重试的边界：只对幂等请求重试，且要有退避与上限 | ✅ 已完成 2026-09-13 |
| 3 | 时间与定时器 | ①`time.Time` 含**单调时钟**，算时间间隔用 `time.Since(t)` 而不是 `time.Now().Sub(t)` ②`time.Ticker` 必须 `Stop`（⚠️ **但"不 Stop 会泄漏"这话在 Go 1.23 起已经不成立，且有一种构造例外**）③`Timer` 复用要 `Stop` + 排空 channel（⚠️ **Go 1.23 起不再需要排空**）④时区与格式化：`2006-01-02 15:04:05` 这个魔数布局串 | ✅ 已完成 2026-09-13 |

> ⚠️ 上表第 2、3 项里带 ⚠️ 的两处，是本课**推翻老教材**的地方——都不是"版本差异的小注脚"，而是会让你照抄老代码就踩坑的地方。第三幕会逐条给实测证据。

---

## 第一幕：起源与场景引入

### 1.1 origin：这三样东西都不是"一开始就长这样"

本课三个知识点各有一段"后加的成熟史"，而且**都是围绕同一件事长出来的：给资源加上限、加寿命、加取消**。

**① `database/sql`：一个"薄"接口 + 一堆后来补上的池子旋钮。**

`database/sql` 从 Go 1.0 就在，但它的**可调项几乎全是后来加的**（下表全部查 `$GOROOT/api/*.txt`，不凭记忆）：

| 能力 | 引入版本 | 为什么需要它 |
|---|---|---|
| `(*DB).SetMaxIdleConns` | **Go 1.1** | 空闲连接不设上限，长时间空跑的进程会攥着一堆连接不放 |
| `(*DB).SetMaxOpenConns` | **Go 1.2** | 不设上限时，并发一高就是"你有多少并发我就开多少连接"，直接打爆数据库 |
| `(*DB).Stats` | **Go 1.5** | 池子是个黑盒——**没有一个能观测它的入口**，出问题只能猜 |
| `(*DB).SetConnMaxLifetime` | **Go 1.6** | 连接活太久（中间隔了 LB / 防火墙 / 数据库重启）会变成"看起来还在、实际已死"的僵尸连接 |
| `QueryContext` / `ExecContext` / `QueryRowContext` / `PingContext` / `BeginTx` | **Go 1.8** | 前面所有代码都**没法被取消**——请求都断了，数据库还在跑 |
| `(*DB).SetConnMaxIdleTime` | **Go 1.15** | 区分"活太久"和"闲太久"，前者管僵尸，后者管不必要地占着连接 |

这张表本身就是本课知识点 1 的骨架：**从 1.1 到 1.15，七年时间，所有人都在往同一个方向加东西——上限、寿命、观测、取消。**

**② `http.Client`：客户端这半边比服务端晚成熟很多。**

| 能力 | 引入版本 | 备注 |
|---|---|---|
| `Client` / `Transport` / `Transport.MaxIdleConnsPerHost` / `DefaultMaxIdleConnsPerHost` | **Go 1.0** | **"每主机空闲连接上限 2"从 Go 1.0（2012-03 发布）起就是 2，到今天还是 2** |
| `Client.Timeout` / `Transport.TLSHandshakeTimeout` | **Go 1.3** | `Client` 本身 Go 1.0 就有，但它**没有超时字段**；在 Go 1.3 之前，**`http.Get` 没有超时这个概念** |
| `MaxIdleConns` / `IdleConnTimeout` | **Go 1.7** | "每主机 2 条"之外，再给一个跨主机的总量上限 |
| `(*Client).CloseIdleConnections` | **Go 1.12** | 主动把池子清空（发布、切流量时用） |
| `ForceAttemptHTTP2` | **Go 1.13** | **注意这个字段在 `DefaultTransport` 里是被显式打开的** |
| `NewRequestWithContext` | **Go 1.13** | 请求的取消终于成了标准姿势 |

**③ `time`：单调时钟的语义、定时器的回收规则，都改过。**

| 能力 | 引入版本 |
|---|---|
| `time.AfterFunc` / `time.RFC3339` | **Go 1.0** |
| `Round` / `Truncate` / `ParseInLocation` / `Timer.Reset` | **Go 1.1** |
| `Until` | **Go 1.8** |
| `Ticker.Reset` | **Go 1.15** |
| `DateTime` / `DateOnly` / `TimeOnly` / `Time.Compare` | **Go 1.20** |
| `context.AfterFunc`（**是 `context` 包的，不是 `time` 包的**） | **Go 1.21** |

> ⚠️ **查 `api/*.txt` 时踩过的两个坑（写在这里，省得下次再踩）**：
> **① 方法写成 `method (*DB) Foo(...)`，不是 `func (*DB) Foo(...)`。** 第一次用 `func (DB)` 搜 `SetMaxOpenConns`，什么都没搜到，差点误判"没这个 API"。
> **② `api/go1.1.txt` 里出现 ≠ Go 1.1 新增。** Go 1.1 起 api 文件才开始记录**常量的值**（`const Foo = 2`，而 Go 1.0 记的是 `const Foo ideal-int`），所以**所有老常量都被重录了一遍** —— `go1.1.txt` 因此有 50454 行，比 `go1.2.txt`（32484 行）还长。判断"某 API 哪个版本引入"，要看它**最早**出现在哪个文件里，而 `go1.txt` 就是 **Go 1.0**。
>
> **本课就是被坑 ② 绊了一下**：`DefaultMaxIdleConnsPerHost`、`Transport.MaxIdleConnsPerHost`、`time.RFC3339`、`time.AfterFunc` 这四项，初稿都写成了"Go 1.1"或"Go 1.21"，**回查 `go1.txt` 才发现它们从 Go 1.0 就在**（Go 1.21 新增的其实是 `context.AfterFunc`）。

> 📌 **一个值得记住的版本事实**：查完 `api/go1.27.txt` 可以确认，**Go 1.27 没有给 `net/http` 客户端和 `time` 包增加任何新 API**。但 `net/http` 客户端在 1.27 里**改了一处行为**——就是本课要推翻老教材的那条"drain-on-close"（见知识点 2 ③）。
>
> **这给我们一个很实用的判断口径**：*API 没变 ≠ 行为没变*。升级 Go 版本时，只读 API diff 是不够的。

### 1.2 场景：小谷的下单服务要真正读写下游

课 11 结束时，小谷的服务长这样：

```
客户端 ──HTTP──> 小谷的服务 ──> ??? 
```

后面那个 `???` 就是本课要填的东西。他要接两条线：

```
                        ┌──────────────────┐
                        │   订单表（数据库） │  ← 知识点 1：写进去
                        └────────▲─────────┘
                                 │ database/sql
   客户端 ──HTTP──> 小谷的服务 ───┤
                                 │ http.Client
                        ┌────────▼─────────┐
                        │ 库存 / 风控服务   │  ← 知识点 2：连出去
                        └──────────────────┘
                                 
                        ┌──────────────────┐
                        │ 15 分钟未支付取消 │  ← 知识点 3：跑在时间上
                        └──────────────────┘
```

三条线**各有各的坑**，而且坑的形状惊人地一致——都是"**资源有寿命，而你没管它的寿命**"：

| 线 | 资源 | 不管寿命的后果 |
|---|---|---|
| 落库 | 数据库连接 | 连接数暴涨 / 池被抽干 |
| 调下游 | TCP 连接 | 连接不复用、建连成本吃掉全部性能 |
| 定时 | 定时器对象 | 内存一路涨 |

小谷踩了三个坑，我们一个一个看。

### 1.3 撞墙 A：每次请求都 `sql.Open`，压测时数据库连接数炸了

小谷的第一版代码（**很多人第一版都这么写**）：

```go
func createOrder(w http.ResponseWriter, r *http.Request) {
	db, err := sql.Open("sqlite", dsn)   // ← 每次请求都 "打开数据库"
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	defer db.Close()                     // ← 每次请求都 "关闭数据库"

	_, err = db.Exec("INSERT INTO orders ...")
	...
}
```

他心里的模型是："`sql.Open` = 连上数据库，`db.Close` = 断开数据库"——像 `os.Open` / `f.Close` 那样，**"借一次、还一次"**。

这个模型错得很彻底。他把探针跑了一遍，第一件事就反直觉：

```console
A) 刚 sql.Open 完：Open 次数 = 0（池是空的，一条连接都没建）
   第一次真正查询之后：Open 次数 = 1
```

**`sql.Open` 一条连接都没建。** 官方文档原话是：

> *"Open may just validate its arguments without creating a connection to the database."*
> （`Open` 可能只是校验一下参数，并不建立到数据库的连接。——`$GOROOT/src/database/sql/sql.go`）

也就是说 —— **"每次请求 `sql.Open` + `defer db.Close()`" 这件事，真正的代价不是"每次连一次数据库"，而是"每次请求新建一个连接池，用完把整个池子扔掉"。** 这是两个错误叠在一起：

1. **池子本该是进程级的，被他做成了请求级的**。`sql.Open` 的文档紧接着写着：*"the Open function should be called just once. It is rarely necessary to close a DB."* ——**只应调用一次**、**极少需要 `Close`**。
2. **"不用了就关"在这个场景下反而是最大的浪费**——数据库连接是**建一次能用很多次**的东西，他每请求建一次。

那么"不保留空闲连接"到底长什么样？探针里有一例专门跑这个形状：

```console
---- C) 不保留空闲连接 = 每次重开 ----
    conn#1  OPEN   （存活 1） dsn=tcp(fake:1)/c
    conn#1  QUERY  "SELECT v"
    conn#1  CLOSE  （存活 0）
    conn#2  OPEN   （存活 1） dsn=tcp(fake:1)/c
    conn#2  QUERY  "SELECT v"
    conn#2  CLOSE  （存活 0）
    conn#3  OPEN   （存活 1） dsn=tcp(fake:1)/c
    conn#3  QUERY  "SELECT v"
    conn#3  CLOSE  （存活 0）
    conn#4  OPEN   （存活 1） dsn=tcp(fake:1)/c
    conn#4  QUERY  "SELECT v"
    conn#4  CLOSE  （存活 0）
    conn#5  OPEN   （存活 1） dsn=tcp(fake:1)/c
    conn#5  QUERY  "SELECT v"
    conn#5  CLOSE  （存活 0）

C) MaxIdleConns=0，串行 5 次查询 → Open 次数 = 5，Close 次数 = 5
```

**5 次查询 = 5 次 OPEN + 5 次 CLOSE。** 对比同一份探针里的 B 例（默认配置、串行 5 次）：

```console
---- B) 串行复用同一条连接 ----
    conn#1  QUERY  "SELECT v"
    conn#1  QUERY  "SELECT v"
    conn#1  QUERY  "SELECT v"
    conn#1  QUERY  "SELECT v"
    conn#1  QUERY  "SELECT v"

B) 串行 5 次查询 → Open 次数 = 0，Close 次数 = 0
```

**0 次 OPEN、0 次 CLOSE，全部落在 `conn#1` 上。** 这才是连接池该有的样子。

> 🐞 第一个教训：**`sql.DB` 不是"一条数据库连接"，它是"一个连接池"。** 名字叫 `DB`，实际是个池子管理器。**一个进程一个，全局复用，不要 `Close`。**

还有第二种"抽干池子"的方式，比 `Close` 更常见 —— **`rows` 只借不还**：

```console
1) 忘了 rows.Close()：把连接池抽干
   第 1 次 Query 之后（没 Close）：Open=1 InUse=1 Idle=0
   第 2 次 Query 之后（没 Close）：Open=2 InUse=2 Idle=0
   池里两条连接都被占住后再查 → err = context deadline exceeded
   Stats(): Open=2 InUse=2 WaitCount=1
```

只借两条就把默认池子借空了（`MaxOpenConns` 零值 = 不限，但**每条 `Query` 都攥着一条连接不放**），第三次查询直接等到 `context deadline exceeded`。**症状是"服务卡住"，根因是两行忘了写的 `defer rows.Close()`。**

> 🐞 第一个教训的第二半：**`rows` 是借出去的一条连接，必须还。** `defer rows.Close()` 不是"礼貌"，是"归还"。

### 1.4 撞墙 B：`resp.Body` 没读也没关，压测时新连接一路涨

第二版代码，他调下游库存服务：

```go
func checkStock(sku string) (bool, error) {
	resp, err := http.Get("http://inventory/api/stock?sku=" + sku)
	if err != nil {
		return false, err
	}
	// 只看状态码，body 用不上，不管了
	return resp.StatusCode == 200, nil
}
```

功能上完全正确 —— `http.Get` 返回了，`StatusCode` 也读对了。**问题是这条 TCP 连接再也不会被复用了。**

压测现象：QPS 上不去，`netstat` 看**新连接数一路涨**。他把 6 种"读 / 不读 / 关 / 不关"的写法并排跑了一遍，用 `httptrace` 判定第二条请求有没有复用第一条的连接：

```console
A 读到 EOF 再 Close      /small  (4 KiB)                → ✅ 复用了同一条连接
B 不读直接 Close         /small  (4 KiB)                 → ✅ 复用了同一条连接
C 不读直接 Close         /big    (1 MiB)                 → ❌ 没复用（新连接）
D 不读直接 Close         /dribble(128 KiB / 400ms)       → ❌ 没复用（新连接）
E 先 Copy 到 EOF 再 Close /big    (1 MiB)               → ✅ 复用了同一条连接
F 读完再 Close，服务端 Connection: close                    → ❌ 没复用（新连接）
```

⚠️ **先别急着记结论——这 6 行里有本课最大的一处"老教材已经不对了"。** A 和 B 都是 ✅，C 和 D 都是 ❌，中间的差别不是"读没读"，而是**响应体有多大**。这个我们放到知识点 2 里逐条拆。

现在先看"为什么这件事这么值钱"。他做了一组对照：**共用同一个 `Client`** vs **每次请求新建 `Client` + `Transport`**，各发 100 次请求，数服务端新建了几条 TCP 连接：

```console
5) 复用 Client vs 每次都新建 Transport（各 100 次请求）
   共用同一个 Client：服务端新建 TCP 连接 1 条
   每次新建 Client+Transport：服务端新建 TCP 连接 100 条
```

**1 条 vs 100 条。** 100 倍的差别，就在"这个 `Client` 你复不复用"这一件事上。

> 🐞 第二个教训：**`http.Client` 和 `sql.DB` 是同一类东西——它们都是"连接池的句柄"，都该复用，都不该每次新建。** 官方文档对它们用了几乎一样的话：`sql.Open` 说 *"should be called just once"*，`Client` 说 *"Clients should be reused instead of created as needed."* ——**这不是巧合，是同一个设计。**

### 1.5 撞墙 C：定时逻辑越跑越占内存

第三版，他要做"订单 15 分钟未支付自动取消"。第一版写成这样（读起来很自然）：

```go
for {
	select {
	case order := <-pending:
		// 等 15 分钟，没支付就取消
		select {
		case <-order.paid:
		case <-time.After(15 * time.Minute):   // ← 每次循环都新建一个定时器
			cancelOrder(order)
		}
	}
}
```

以及一个"每 30 秒扫一遍超时订单"的兜底：

```go
go func() {
	t := time.NewTicker(30 * time.Second)
	for range t.C {   // ← 忘了 Stop
		sweepExpired()
	}
}()
```

跑一天没事，跑一周 RSS 一直涨。他做了两组测量，结果完全不同：

**第一组：热路径里 `time.After` 贵不贵？** 基准测试（`-count=2` 两轮）：

```console
BenchmarkAfterInLoop-11      	 2556428	       154.9 ns/op	     248 B/op	       3 allocs/op
BenchmarkAfterInLoop-11      	 2590509	       138.5 ns/op	     248 B/op	       3 allocs/op
BenchmarkNewTimerReuse-11    	 3853380	        93.67 ns/op	       0 B/op	       0 allocs/op
BenchmarkNewTimerReuse-11    	 3900733	        90.36 ns/op	       0 B/op	       0 allocs/op
```

**`time.After` 每次 248 B、3 次分配；复用一个 `Timer` 是 0 B、0 次分配。** 在每请求的热路径上，这就是"每来一个请求泄漏一个小对象等 GC"。

**第二组：不 `Stop` 的定时器到底会不会泄漏？** 每次新建 30 万个、前后各强制 GC 三次：

```console
   NewTimer(1h) 未 Stop、不引用                  堆   0.25 →   0.25 MB（Δ  +0.00）  对象 Δ +15
   NewTicker(1h) 未 Stop、不引用                 堆   0.25 →   0.25 MB（Δ  +0.00）  对象 Δ +6
   After(1h) 未接收                            堆   0.25 →   0.25 MB（Δ  +0.00）  对象 Δ +5
   AfterFunc(1h, f) 未 Stop、不引用              堆   0.25 →  37.56 MB（Δ +37.31）  对象 Δ +300020
   AfterFunc(1h, f) 立刻 Stop                 堆  37.56 →  37.56 MB（Δ  +0.00）  对象 Δ +2
```

**注意第三行和第四行的对比** —— 前三种（`NewTimer` / `NewTicker` / `After`）**不 Stop 也几乎是 0 增长**（Go 1.23 起 GC 能回收未 Stop 的定时器，这是官方承诺的）；但第四种 **`AfterFunc` 30 万个未 Stop 就是实打实 37.56 MB**。

> 🐞 第三个教训：**"Go 1.23 起不 Stop 定时器也不会泄漏"这句话，对 `NewTimer` / `NewTicker` / `After` 成立，对 `AfterFunc` 不成立。** 这一条是本课**没能在源码里找到机制解释**的一处实测结论，第三幕会如实标注。

### 1.6 三道墙连起来看

| 撞墙 | 表面症状 | 一句话根因 | 本课对应知识点 |
|---|---|---|---|
| A | 压测时数据库连接数爆 / 服务卡住 | `sql.DB` 是**连接池**不是连接，且 `rows` 会借走连接 | 知识点 1 ①③ |
| B | 新连接一路涨、QPS 上不去 | `Client` 是连接池句柄，必须复用；`resp.Body` 不关则不归还 | 知识点 2 ②③ |
| C | RSS 一路涨、热路径分配高 | 定时器/`Timer` 是**有寿命的对象**，热路径上要复用 | 知识点 3 ②③ |

小谷的结论：**"连数据库"和"调接口"在语法上都是一个函数调用，但在工程上是"管理一批有寿命的资源"。** 这一课就是来拆这三个坑的。

---

## 第二幕：认知冲突

小谷在查这三堵墙的过程中，有三个"我以为"被推翻 —— 而且这三个"我以为"**在老教材和老博客里都还能查到，都还写着"对"**。这一课之所以值得跑一遍实测，就是因为其中有两个已经过期了。

### 我以为 1：「`sql.Open` 就是连上数据库」

他已经知道"不要每次请求都 `Open`"了，但他以为这么说的理由是"`Open` 太贵，连一次要几百毫秒"。所以他一度觉得 —— 那我加个连接池包装不就行了？

探针的第一个输出就把这个前提推翻了：

```console
A) 刚 sql.Open 完：Open 次数 = 0（池是空的，一条连接都没建）
   第一次真正查询之后：Open 次数 = 1
---- A) Open 不连接，首次查询才连接 ----
    conn#1  OPEN   （存活 1） dsn=tcp(fake:1)/a
    conn#1  QUERY  "SELECT v"
```

**`sql.Open` 返回时，"Open 次数"是 0。** 连上数据库的动作，发生在**第一次真正需要连接的时候**（第一次 `Query` / `Exec` / `Ping`）。官方文档把这件事写得很清楚：

> *"Open may just validate its arguments without creating a connection to the database. To verify that the data source name is valid, call `DB.Ping`."*
> （`Open` 可能只是校验一下参数，并不建立连接。要验证数据源名有效，请调用 `DB.Ping`。——`$GOROOT/src/database/sql/sql.go`，核查于 2026-09）

> 💡 **为什么这条这么重要**：因为它说明 `sql.Open` 的成本**接近于零**。所以"每次请求都 `Open`"的代价**从来不在于 `Open` 本身**，而在于 —— **你每请求造了一个新的空池子，而空池子的第一条连接用完就没地方还了。** 这是一个"对象生命周期"问题，不是"性能开销"问题。**把它当性能问题去优化，方向就错了。**

而"该调用几次"的答案，文档也直接给了：*"the `Open` function should be called just once. It is rarely necessary to close a `DB`."*

### 我以为 2：「只要把 `resp.Body` 关掉就能复用连接」——这句话在 Go 1.27 只对了一半

关于"连接复用"，小谷记得两条老规矩，都是他从教材和博客里学来的：

1. **"必须 `Close()`，否则连接泄漏"** —— 这条他记得很牢，所以他的代码里是有 `Close()` 的。
2. **"必须把 body 读到 EOF，只 `Close` 不读的话连接会被丢弃"** —— 这条是被**反复强调**的"最佳实践"，几乎每篇 Go HTTP 教程都会写。

撞墙 B 里那 6 行输出，第 2 条**当场就碎了**：写法 B（不读、直接 `Close`、响应体 4 KiB）结果是 ✅ 复用。而写法 C（不读、直接 `Close`、响应体 1 MiB）结果是 ❌。

**同样是"不读直接 Close"，4 KiB 能复用、1 MiB 不能。** 这说明开关不是"读没读"，而是**别的某个量**。他去翻 Go 1.27 的 `transport.go`，找到了这段**在 Go 1.27 才加进去的**代码：

```go
// maxPostCloseReadBytes is the max number of bytes that a client is willing to
// read when draining the response body of any unread bytes after it has been
// closed. This number is chosen for consistency with maxPostHandlerReadBytes.
const maxPostCloseReadBytes = 256 << 10

// maxPostCloseReadTime defines the maximum amount of time that a client is
// willing to spend on draining a response body of any unread bytes after it
// has been closed.
const maxPostCloseReadTime = 50 * time.Millisecond

func maybeDrainBody(body io.Reader) bool {
	drainedCh := make(chan bool, 1)
	go func() {
		if _, err := io.CopyN(io.Discard, body, maxPostCloseReadBytes+1); err == io.EOF {
			drainedCh <- true
		} else {
			drainedCh <- false
		}
	}()
	select {
	case drained := <-drainedCh:
		return drained
	case <-time.After(maxPostCloseReadTime):
		return false
	}
}
```

> 源码原文，核查于 2026-09（`$GOROOT/src/net/http/transport.go`）

**`256 << 10` = 262144 字节 = 256 KiB；`50 * time.Millisecond` = 50 毫秒。** 现在回头看那 6 行输出就全部对上了：

| 写法 | 响应体 | 阈值 vs 实际 | 结果 |
|---|---|---|---|
| B | 4 KiB | 远小于 256 KiB | 后台排空成功 → ✅ 复用 |
| C | 1 MiB | 大于 256 KiB | `CopyN` 拿不到 `io.EOF` → ❌ 不复用 |
| D | 128 KiB / 400 ms | 字节数在校内，但**时间超过 50 ms** | 超时判失败 → ❌ 不复用 |

而官方文档的措辞也在 Go 1.27 同步更新了 —— `Response.Body` 的注释里现在多出一段：

> *"…however, manually reading the body to completion should not be needed in most cases, as closing the body will also cause the body to be read to completion asynchronously, up to a conservative limit."*
> （……不过在大多数情况下不需要手工把 body 读完——关闭 body 也会让 body 被**异步**读到结束，**上限是保守的**。——核查于 2026-09）

`Client.Do` 的注释也加了对应的一句：*"Note, however, that `Transport` will automatically try to read a `Response` Body to EOF asynchronously up to a conservative limit when a Body is closed."*

**"异步"这三个字还有一个可观测的后果** —— `Close()` 本身会不会被阻塞？小谷量了一下：

```console
H) 时序：不读直接 Close，调用本身多久返回
   Close() 调用耗时 26µs（同步返回很快，排空在后台 goroutine 里做）
   120ms 后服务端 idle 连接 0 条（dribble 要 400ms 才发完，排空在 50ms 就被判失败）
```

**`Close()` 只花了 26 微秒就返回了**（排空在后台 goroutine 里），但 120 ms 后服务端的 idle 连接数是 **0** —— 因为那个 400 ms 还没发完的响应体，在 50 ms 的排空窗口里被判了失败。

> 💡 **所以正确的现代说法是**：**`resp.Body` 必须 `Close()`（这条永远对）；"必须读完"则只对"响应体超过 256 KiB、或需要 50 ms 以上才能读完"的情况才有必要。** 小响应体（API 里最常见的那种）**直接 `Close()` 就够**。
>
> ⚠️ **但"够"不等于"应该"**：这份"自动排空"是**保守兜底**，它只保证了"能复用"这个结果，**没保证你能拿到 body 内容**。你要用响应体的数据，还是得自己读。**别把"我可以不读"理解成"我不该读"。**

### 我以为 3：「Go 1.23 起，定时器不 `Stop` 也不会泄漏，所以不用管了」

这条"我以为"很有底气，因为它是**官方文档原话**。`NewTimer` 的注释里写着：

> *"Before Go 1.23, the garbage collector did not recover timers that had not yet expired or been stopped, so code often immediately deferred `t.Stop` after calling `NewTimer`… **As of Go 1.23, the garbage collector can recover unreferenced timers, even if they haven't expired or been stopped. The `Stop` method is no longer necessary to help the garbage collector.**"*
> （Go 1.23 起，GC 能回收未被引用的定时器，即使它们还没到期也没被 Stop。**`Stop` 方法不再是为了帮 GC 回收而需要。**——核查于 2026-09）

`Ticker` 和 `Tick` 的注释里也各有一份同样的话。**这句话在 2026 年被无数博客转述成"Go 里的定时器不用管了"。**

探针按构造方式分别测了一遍（每次新建 30 万个、前后各强制 GC 三次）：

```console
   NewTimer(1h) 未 Stop、不引用                  堆   0.25 →   0.25 MB（Δ  +0.00）  对象 Δ +15
   NewTicker(1h) 未 Stop、不引用                 堆   0.25 →   0.25 MB（Δ  +0.00）  对象 Δ +6
   After(1h) 未接收                            堆   0.25 →   0.25 MB（Δ  +0.00）  对象 Δ +5
   AfterFunc(1h, f) 未 Stop、不引用              堆   0.25 →  37.56 MB（Δ +37.31）  对象 Δ +300020
   AfterFunc(1h, f) 立刻 Stop                 堆  37.56 →  37.56 MB（Δ  +0.00）  对象 Δ +2
```

前三种确实遵循环文档承诺（Δ ≈ 0）；**`AfterFunc` 不遵守 —— 30 万个未 Stop 的 `AfterFunc` 是实打实的 37.56 MB、30 万个存活对象，GC 三次不回收**。

小谷的第一反应是"我量错了"：可能是对象还被引用着、可能是测量方法有问题。他换了三种写法（匿名函数 / 具名的空函数 / `nil` 函数）、跑了多轮、分别在独立进程里跑，**结论稳定复现**。最后他翻 `runtime/time.go` 想找机制，**没找到**：

> ⏳ **机制未查清（本课如实标注，不推测）**：`runtime.timer` 的 `isChan` 分支只对"带 channel 的定时器"做校验；`timers.heap` 本身是强引用，理论上会阻止回收 —— 但**为什么 `NewTimer` / `NewTicker` 能回收而 `AfterFunc` 不能，我没有在源码里找到确切的那一行**。
>
> **本课的处理方式**：把实测结果写出来（可复现、稳定），**把机制留白并标注 ⏳**，而不是编一个听起来合理的解释。这是本仓库的既定纪律 —— 课 11 那条 `jsonv2` 的翻车就是因为"用推理代替了核查"。

> 💡 三个"我以为"合起来，指向同一个主题：**这三个包（`database/sql` / `net/http` / `time`）的文档都写得很详细，但"文档正确"不等于"你记住的那句转述正确"。** 撞墙 B 和撞墙 C 里被推翻的，都不是官方文档，而是**教材和博客对官方文档的转述**——一次是把"保守兜底"讲成了"硬性要求"，一次是把"三种构造都适用"讲成了"全都适用"。

---

## 第三幕：层层揭示

### 知识点 1：database/sql

#### ① 一句话定义

**`sql.DB` 不是"一条数据库连接"，而是"一个连接池的管理句柄"——你只管要连接、用完还回去，池子自己负责按上限开关连接、按寿命回收连接、按需等待和重试；而 `database/sql` 本身不含任何数据库驱动，它只是一层把具体驱动隔离在后面的通用接口。**

#### ② 直觉建立（类比 + 失效边界）

**类比：酒店的房卡中心（不是你的房间）。**

`sql.DB` 这个东西，手感上像"一条连接"，实际上更像**酒店前台的房卡管理系统**：

- 你（一次 `Query`）到前台说"我要用一间房" → 前台给你一张卡（**一条连接**）。
- 你用完把卡还回去（**`rows.Close()` / `Exec` 返回**）→ 卡回池子，下一个人接着用。
- 前台**手里常备几张卡**（**空闲连接**，默认 **2** 张）——备太多占着资源，备太少每次都要现做一张。
- 前台**最多允许发出去几张卡**（**`MaxOpenConns`**）——超了就让你在大堂等（**不是报错，是排队**）。
- 卡**用久了要强制换新**（**`ConnMaxLifetime`**）——因为房间可能已经被别人远程锁了（数据库重启、LB 掐了连接），卡看着有效其实开不了门。
- 卡**闲太久也要收回**（**`ConnMaxIdleTime`**）。

**这个类比在哪里失效（三条）：**

1. **"还卡"这件事不会自动发生。** 酒店里你退房是主动行为；Go 里 `rows` 用完不 `Close`**没有任何机制会替你收**，那条连接就一直在你手上，直到 GC 顺手关掉 `rows`（这是**不确定什么时候**发生的）。**池子被抽干的最常见原因就是这一条。**
2. **"排队"是静默的，而且排的是看不见的队。** `MaxOpenConns` 满了之后，`Query` 会**阻塞等待**，而不是立刻返回错误 —— 你会看到"接口变慢"，而不是"接口报错"。想让它别等，**必须自己传一个带超时的 `context`**（见 §1.8）。
3. **池子是"每进程"的，不是"每请求"的。** 多开一个 `sql.DB` 就是多开一个池子，**两个池子之间不共享连接**。所以"我给它加个池"这种想法在本包里是多余的 —— **它本来就是池**。

**还有一条最要紧的失效边界**：`database/sql` **自己没有能力"取消"一个已经在数据库上跑着的查询**。它只能"不再等"——**真正让数据库停下那条查询，要求驱动实现 `driver.QueryerContext` / `driver.ExecerContext`**。官方包文档给了这句话：

> *"Drivers that do not support context cancellation will not return until after the query is completed."*
> （**不支持 context 取消的驱动，会一直等到查询完成才返回。**——`$GOROOT/src/database/sql/sql.go` 包文档，核查于 2026-09）

**这一条决定了本课 §1.8 那次全链路演示能不能成立**：能不能"客户端一断、数据库就不跑了"，取决于**驱动**，不取决于你写没写 `Context`。

#### ③ 核心原理

##### §1.1 池子替你做的五件事，和它不管的五件事

官方对 `DB` 的定义只有一句话，但信息量极大：

> ```go
> // DB is a database handle representing a pool of zero or more
> // underlying connections. It's safe for concurrent use by multiple
> // goroutines.
> //
> // The sql package creates and frees connections automatically; it
> // also maintains a free pool of idle connections. If the database has
> // a concept of per-connection state, such state can be reliably observed
> // within a transaction ([Tx]) or connection ([Conn]). Once [DB.Begin] is called, the
> // returned [Tx] is bound to a single connection. Once [Tx.Commit] or
> // [Tx.Rollback] is called on the transaction, that transaction's
> // connection is returned to [DB]'s idle connection pool. The pool size
> // can be controlled with [DB.SetMaxIdleConns].
> ```
>
> 源码原文，核查于 2026-09（`$GOROOT/src/database/sql/sql.go`）

拆出五条事实：

| # | 事实 | 你因此不用做的事 |
|---|---|---|
| 1 | **`pool of zero or more`** —— 池里可以有 **0** 条连接 | 不用在启动时"预热连接"（真需要再说） |
| 2 | **`safe for concurrent use by multiple goroutines`** | 不用自己给 `sql.DB` 加锁 |
| 3 | **`creates and frees connections automatically`** | 不用手写连接池 |
| 4 | **`maintains a free pool of idle connections`** | 不用手写空闲回收 |
| 5 | **`Once Begin is called, the returned Tx is bound to a single connection`** | 事务里不会在连接之间跳（这是个关键保证，见 §1.7） |

**它不管的五件事**（这五件全得你自己来）：

| # | 它不管的 | 你得自己做 |
|---|---|---|
| 1 | 归还连接 | `defer rows.Close()` |
| 2 | 排队超时 | 传带 deadline 的 ctx |
| 3 | 池子大小 | `SetMaxOpenConns` / `SetMaxIdleConns` |
| 4 | 连接寿命 | `SetConnMaxLifetime` / `SetConnMaxIdleTime` |
| 5 | 观测 | 定期读 `db.Stats()` |

**注意第 1 条和第 5 条**：一个"必须你手动做"，一个"必须你主动看"。**这两条就是所有 `database/sql` 生产事故的两个源头。**

##### §1.2 四个旋钮，和它们的零值语义

四个 setter 的默认值**全都不在文档的显眼处**，必须逐个查源码注释。以下是逐字摘录（核查于 2026-09）：

```go
// SetMaxIdleConns sets the maximum number of connections in the idle
// connection pool.
//
// If MaxOpenConns is greater than 0 but less than the new MaxIdleConns,
// then the new MaxIdleConns will be reduced to match the MaxOpenConns limit.
//
// If n <= 0, no idle connections are retained.
//
// The default max idle connections is currently 2. This may change in
// a future release.
func (db *DB) SetMaxIdleConns(n int)
```

```go
// SetMaxOpenConns sets the maximum number of open connections to the database.
//
// If MaxIdleConns is greater than 0 and the new MaxOpenConns is less than
// MaxIdleConns, then MaxIdleConns will be reduced to match the new
// MaxOpenConns limit.
//
// If n <= 0, then there is no limit on the number of open connections.
// The default is 0 (unlimited).
func (db *DB) SetMaxOpenConns(n int)
```

```go
// SetConnMaxLifetime sets the maximum amount of time a connection may be reused.
//
// Expired connections may be closed lazily before reuse.
//
// If d <= 0, connections are not closed due to a connection's age.
func (db *DB) SetConnMaxLifetime(d time.Duration)

// SetConnMaxIdleTime sets the maximum amount of time a connection may be idle.
//
// Expired connections may be closed lazily before reuse.
//
// If d <= 0, connections are not closed due to a connection's idle time.
func (db *DB) SetConnMaxIdleTime(d time.Duration)
```

**总结成一张表**（这是本节最该背下来的一张）：

| 旋钮 | 零值（= 默认）意味着 | 该设成什么 |
|---|---|---|
| `MaxOpenConns` | **0 = 不限** | **必须设**。设成"数据库能承受的连接数 ÷ 你的服务实例数"，留 20% 余量给别的应用 |
| `MaxIdleConns` | **2**（源码常量 `defaultMaxIdleConns = 2`） | 一般设成 **= `MaxOpenConns`**，避免"用完就关、下次再开" |
| `ConnMaxLifetime` | 0 = 永不过期 | 设成**比后端 LB / 防火墙的空闲超时短一点**（常见 30 分钟 / 5 分钟） |
| `ConnMaxIdleTime` | 0 = 永不过期 | 比 `ConnMaxLifetime` 更短，比如几分钟；用来省掉"闲占连接" |

> ⚠️ **`MaxIdleConns` 默认是 2，而且源码里明确写着 `This may change in a future release.`** —— 也就是说**今天写 2 是 2，将来不保证**。**别依赖这个默认值，显式设。**
>
> 📌 **`SetMaxIdleConns` 的注释里还藏着一个顺序陷阱**：*"If `MaxOpenConns` is greater than 0 but less than the new `MaxIdleConns`, then the new `MaxIdleConns` will be reduced to match the `MaxOpenConns` limit."* —— **空闲上限会被自动压到不超过打开上限**。所以设的时候**先设 `MaxOpenConns` 再设 `MaxIdleConns`**，否则顺序反过来你的 `MaxIdleConns` 会被悄悄改小。源码里的实现也确认了这一点：

```go
func (db *DB) SetMaxIdleConns(n int) {
	db.mu.Lock()
	if n > 0 {
		db.maxIdleCount = n
	} else {
		// No idle connections.
		db.maxIdleCount = -1
	}
	// Make sure maxIdle doesn't exceed maxOpen
	if db.maxOpen > 0 && db.maxIdleConnsLocked() > db.maxOpen {
		db.maxIdleCount = db.maxOpen
	}
	...
```

**还有一条更隐蔽的**：空闲连接的清理是**后台协程**做的，而那个协程有一轮询下限：

```go
func (db *DB) connectionCleaner(d time.Duration) {
	const minInterval = time.Second
```

> 源码原文，核查于 2026-09

**`minInterval = time.Second`** —— 意味着**无论你把 `ConnMaxIdleTime` 设得多小（比如 60 毫秒），清理最快也是每秒一轮**。这不是 bug，是"够用就好"的设计。

##### §1.3 池子的真实行为：把七个场景跑一遍

光看注释理解不了"池子怎么动"。探针里写了一个**假的驱动**（`driver.Driver` / `Conn` / `Stmt` / `Rows` 全自己实现），每次 OPEN / CLOSE / QUERY 都打日志，于是池子的行为变成**可读的轨迹**。

**场景 A：`Open` 不连接（撞墙 A 已看过）**

```console
A) 刚 sql.Open 完：Open 次数 = 0（池是空的，一条连接都没建）
   第一次真正查询之后：Open 次数 = 1
---- A) Open 不连接，首次查询才连接 ----
    conn#1  OPEN   （存活 1） dsn=tcp(fake:1)/a
    conn#1  QUERY  "SELECT v"
```

**场景 B / C：串行复用的两种极端（撞墙 A 已看过）**

```console
B) 串行 5 次查询 → Open 次数 = 0，Close 次数 = 0
C) MaxIdleConns=0，串行 5 次查询 → Open 次数 = 5，Close 次数 = 5
```

**场景 D：默认配置下并发 6 次慢查询 —— "峰值 6，收工只剩 2"**

```console
---- D) 默认 MaxIdleConns=2 只留两条空闲 ----
    conn#1  OPEN   （存活 1） dsn=tcp(fake:1)/d
    conn#4  OPEN   （存活 4） dsn=tcp(fake:1)/d
    conn#2  OPEN   （存活 2） dsn=tcp(fake:1)/d
    conn#5  OPEN   （存活 5） dsn=tcp(fake:1)/d
    conn#1  QUERY  "SELECT slow"
    conn#3  OPEN   （存活 3） dsn=tcp(fake:1)/d
    conn#3  QUERY  "SELECT slow"
    conn#4  QUERY  "SELECT slow"
    conn#2  QUERY  "SELECT slow"
    conn#5  QUERY  "SELECT slow"
    conn#6  OPEN   （存活 6） dsn=tcp(fake:1)/d
    conn#6  QUERY  "SELECT slow"
    conn#4  CLOSE  （存活 5）
    conn#5  CLOSE  （存活 4）
    conn#1  CLOSE  （存活 3）
    conn#2  CLOSE  （存活 2）

D) 默认配置，并发 6 次慢查询 → 峰值连接 6，Open 合计 6
   Stats(): Open=2 Idle=2 InUse=0   ← 6 条用完后只留 2 条
```

**这就是"默认值会坑人"最直观的一幕**：6 个并发请求打进来，池子乖乖开了 6 条连接（**因为 `MaxOpenConns` 零值是"不限"**）—— 如果这是 600 个并发呢？**600 条连接，直接打爆数据库。** 然后请求做完，**4 条被关掉、只留 2 条**（`MaxIdleConns = 2`）—— 下一次再来同样的并发，**这 4 条又得重建**。

> 📌 **一句话总结 D 场景**：默认配置下，**高峰不设防、低谷留太少**。两个旋钮都要显式设。

**场景 E：`MaxOpenConns = 3` + 10 个并发 —— 排队是可观测的**

```console
---- E) 上限 3 把并发压成串行排队 ----
    conn#1  OPEN   （存活 1） dsn=tcp(fake:1)/e
    conn#2  OPEN   （存活 2） dsn=tcp(fake:1)/e
    conn#1  QUERY  "SELECT slow"
    conn#3  OPEN   （存活 3） dsn=tcp(fake:1)/e
    conn#2  QUERY  "SELECT slow"
    conn#3  QUERY  "SELECT slow"
    conn#2  QUERY  "SELECT slow"
    conn#1  QUERY  "SELECT slow"
    conn#3  QUERY  "SELECT slow"
    conn#1  QUERY  "SELECT slow"
    conn#3  QUERY  "SELECT slow"
    conn#2  QUERY  "SELECT slow"
    conn#3  QUERY  "SELECT slow"

E) MaxOpenConns=3，并发 10 次慢查询 → 存活峰值 = 3
   Stats(): Open=3 InUse=0 Idle=3 WaitCount=7 WaitDuration=1.453062293s
```

**存活峰值锁死在 3**（不管来多少并发），另外 7 次**排队等待**，累计等了 **≈1.45 秒**。

**`Stats()` 里那两个字段是本课最该记住的观测入口**：

| 字段 | 含义 | 什么时候该盯它 |
|---|---|---|
| `WaitCount` | **累计等待次数**（有几次拿不到连接，只好排队） | **> 0 就说明池子小了** |
| `WaitDuration` | **累计等待时长** | 除以 `WaitCount` 就是平均排队时间；**接近你的接口超时 → 立刻加池子或查慢查询** |

**场景 F：池满 + ctx 超时 —— 排队是"可以被叫停"的**

```console
---- F) 池满时 QueryContext 会等，ctx 超时就返回 ----
    conn#1  OPEN   （存活 1） dsn=tcp(fake:1)/f
    conn#1  QUERY  "SELECT slow"

F) MaxOpenConns=1，第二条等不到连接 → err = context deadline exceeded
   Stats(): WaitCount=1 WaitDuration=31.0585ms
```

**上限 1 + 第二条请求 → 排队一直到 ctx 到点，返回 `context deadline exceeded`。** 这一例说明两件事：**①排队可以用 ctx 控制**；**②必须有 ctx，否则它会一直等下去**（默认 `Query` / `Exec` **没有超时**）。

**场景 G：空闲超时会回收连接**

```console
G) MaxIdleTime=60ms，刚查完：Idle=1
   睡 1.5s 后：Idle=0（清理协程把它关了）
   注意：源码里 connectionCleaner 有 const minInterval = time.Second，
   所以即使设 60ms，清理也最快 1 秒一轮。
---- G) 空闲超时会回收连接（清理协程，最快每秒一轮） ----
    conn#1  OPEN   （存活 1） dsn=tcp(fake:1)/g
    conn#1  QUERY  "SELECT v"
    conn#1  CLOSE  （存活 0）
```

**设 60 ms、实际要等 1.5 秒才看到 `Idle=0`** —— 因为清理协程最快每秒一轮。**这一条解释了"为什么我设了很短的 `ConnMaxIdleTime`，连接数却没立刻降下来"** —— 不是没生效，是**轮询周期**在那里。

##### §1.4 `Query` / `Exec` / `QueryRow`：三个入口的分工

| 方法 | 返回 | 用来做什么 | 关键差异 |
|---|---|---|---|
| `Query` / `QueryContext` | `*Rows` | **有结果集**（`SELECT`） | 必须 `Close`，必须遍历 |
| `Exec` / `ExecContext` | `Result` | **不关心结果集**（`INSERT` / `UPDATE` / `DELETE` / DDL） | 返回 `LastInsertId()` / `RowsAffected()` |
| `QueryRow` / `QueryRowContext` | `*Row` | **只取一行** | **不会返回 error，错误被推迟到 `Scan` 里** |

最后一行是本课最容易被忽略的机制：**`QueryRow` 的错误不在 `QueryRow` 返回时给你，而是被"储蓄"起来，等你 `Scan` 的时候才吐出来。** 实测：

```console
3) QueryRow：
   命中 → id=2 sku=B-200 err=<nil>
   未命中 → err=sql: no rows in result set（是 sql.ErrNoRows）
   errors.Is(err, sql.ErrNoRows) = true
```

"未命中"这个**不是错误的状态**，也只能通过 `Scan` 的 error 拿到，值是哨兵错误 `sql.ErrNoRows`：

```go
var ErrNoRows = errors.New("sql: no rows in result set")
```

> 源码原文，核查于 2026-09

**所以"用 `QueryRow` 查一条记录，发现没查到"的标准写法是**：

```go
err := db.QueryRowContext(ctx, `SELECT id FROM orders WHERE id = ?`, id).Scan(&gotID)
switch {
case errors.Is(err, sql.ErrNoRows):
	// 正常业务分支：没有这条记录
case err != nil:
	// 真错误
default:
	// 查到了
}
```

⚠️ **这里有一个流传极广的坑**：`err != nil` 里**包含**了 `ErrNoRows`，所以**必须先判 `ErrNoRows`**，否则"记录不存在"会被当成"数据库出错"报 500。

**`Exec` 的 `Result` 有个"NULL 语义"要注意** —— 不是所有语句都能给出这两个值：

```console
1) CREATE TABLE → LastInsertId=0 RowsAffected=0
   INSERT A-100  → id=1 RowsAffected=1
   INSERT B-200  → id=2 RowsAffected=1
   INSERT A-100  → id=3 RowsAffected=1
```

**`CREATE TABLE` 的 `LastInsertId=0`、`RowsAffected=0`** 都是"没有意义"的零值，不是"插了 0 行"。**这两个值是否可靠由驱动决定**（标准库只是把它转发出去），所以**不要用它来判断"数据库是否发生了变更"**。

##### §1.5 `rows` 的生命周期：三个必须知道的时刻

`rows` 是**一条从池里借出来的连接**的"持有者"。它的生命周期有三个关键点：

**① `Scan` 会做类型转换，而类型不匹配的错误信息很好用**

```console
5) 参数类型不匹配 → err = sql: no rows in result set
6) Scan 目标少一个 → err = sql: expected 3 destination arguments in Scan, not 1
7) NULL 扫进 *float64 → err = sql: Scan error on column index 0, name "amount": converting NULL to float64 is unsupported
   用 sql.NullFloat64 → err=<nil> valid=false
```

第 5 条是**很值得注意的一条**：参数类型不匹配时 `QueryRow` 报的**不是类型错误，而是 `ErrNoRows`** —— 因为 `WHERE id = 'abc'` 在 SQLite 里是"合法的、只是匹配不到任何行"。**这提醒我们：不要指望 `ErrNoRows` 一定意味着"没数据"，它也可能意味着"你的条件写错了"。**

第 7 条是 **NULL → Go 类型**的经典冲突。SQL 的 `NULL` 不是 Go 的任何零值，所以标准库给了 `sql.Null*` 家族来接：

```go
var amount sql.NullFloat64
if err := rows.Scan(&id, &sku, &amount); err != nil { ... }
if amount.Valid {
	// 用 amount.Float64
} else {
	// 这一列是 NULL
}
```

**② `Close` 是幂等的，而且"遍历到结束"会自动归还**

```go
// Close closes the [Rows], preventing further enumeration. If [Rows.Next] is called
// and returns false and there are no further result sets,
// the [Rows] are closed automatically and it will suffice to check the
// result of [Rows.Err]. Close is idempotent and does not affect the result of [Rows.Err].
```

> 源码原文，核查于 2026-09

实测确认：

```console
   用 for rows.Next() 遍历到结束（未显式 Close）：InUse=0（已自动归还）
```

**"自动归还"是真的，但别依赖它** —— 因为"遍历到结束"要求你必须**循环到 `Next()` 返回 `false`**；一旦你在循环体里 `break` / `return` / `panic`，那个"到结束"就不发生了。**`defer rows.Close()` 的价值在于：它覆盖所有提前退出的分支。** 这也是为什么它和课 4 讲的 `defer` 纪律是同一件事。

**③ 忘记 `Close` 会抽干池子（撞墙 A 已看过）**

```console
1) 忘了 rows.Close()：把连接池抽干
   第 1 次 Query 之后（没 Close）：Open=1 InUse=1 Idle=0
   第 2 次 Query 之后（没 Close）：Open=2 InUse=2 Idle=0
   池里两条连接都被占住后再查 → err = context deadline exceeded
```

顺带一个**只影响测试环境但极容易让人迷惑**的坑 —— `:memory:` 数据库：

```console
2) ":memory:" 是「每条连接一个独立的库」
   在唯一那条连接上查：COUNT(*) = 1，err=<nil>
   放开上限到 4 后并发 4 次：成功 1 次，失败 3 次
   失败的原文 = SQL logic error: no such table: users (1)
   ↑ 同一个 sql.DB、同一份 SQL，落在不同连接上就是不同的库

3) 想让内存库跨连接共享：改成 file::memory:?cache=shared
   并发 4 次：成功 4 次，失败 0 次（共享缓存后新连接也能看到同一份数据）
```

**同一个 `sql.DB`、同一份 SQL，4 个并发里 1 个成功 3 个报 `no such table`** —— 因为 `:memory:` 是**每条连接一个独立的库**，而池子给了 4 条不同的连接。**这不是 `database/sql` 的 bug，是"池子里的连接不是同一个连接"这个事实的一次极端展示。** 写测试要用内存库，就换成 `file::memory:?cache=shared`。

##### §1.6 参数化查询：为什么它能防注入（以及怎么用）

先看**注入是怎么发生的**。探针把用户输入拼进 SQL，和用占位符传进去，做了并排对照：

```console
=== 参数化：db.QueryRow(`... WHERE name = ?`, input) ===
  输入 "小谷"                     → 命中 1 行，err=<nil>
  输入 "不存在的用户"                 → 命中 0 行，err=<nil>
  输入 "' OR '1'='1"            → 命中 0 行，err=<nil>
  输入 "' OR 1=1 --"            → 命中 0 行，err=<nil>
  输入 "'; DROP TABLE users; --" → 命中 0 行，err=<nil>
```

**五种输入，包括三种攻击载荷，全部命中 0 行、全部 `err=<nil>`。** 注意最后一行那个 `err=<nil>` —— **它没有报错，它就是"查不到叫这个名字的用户"**。这正是参数化的效果：**攻击载荷变成了一个普通的字符串值。**

再看拼接：

```console
=== 拼接：db.QueryRow("... WHERE name = '" + input + "'") ===
  输入 "小谷"                     → 命中 1 行，err=<nil>
     实际 SQL: SELECT COUNT(*) FROM users WHERE name = '小谷'
  输入 "不存在的用户"                 → 命中 0 行，err=<nil>
     实际 SQL: SELECT COUNT(*) FROM users WHERE name = '不存在的用户'
  输入 "' OR '1'='1"            → 命中 2 行，err=<nil>
     实际 SQL: SELECT COUNT(*) FROM users WHERE name = '' OR '1'='1'
  输入 "' OR 1=1 --"            → 命中 2 行，err=<nil>
     实际 SQL: SELECT COUNT(*) FROM users WHERE name = '' OR 1=1 --'
  输入 "'; DROP TABLE users; --" → 命中 0 行，err=database table is locked (6)
     实际 SQL: SELECT COUNT(*) FROM users WHERE name = ''; DROP TABLE users; --'
  users 表还在吗：1（1=在）
```

**看那三行"实际 SQL"** —— 用户输入变成了 SQL 语法的一部分：`' OR '1'='1'` 让 `WHERE` 恒真（**命中 2 行 = 全表**），`' OR 1=1 --` 用 `--` 注释掉了后面那个引号。

`DROP TABLE` 那一行**报了错、表没被删**（`database table is locked (6)`）—— 是因为驱动的多语句防护恰好挡住了。**这是运气，不是安全**。换一个 `DELETE` 就立刻见血：

```console
=== 破坏性注入：删除指定用户 ===
A) 参数化 db.Exec(`DELETE FROM users WHERE name = ?`, input)
   输入 "小谷"           → 删了 1 行，全表剩 1 行，err=<nil>
   输入 "' OR 1=1 --"  → 删了 0 行，全表剩 1 行，err=<nil>
B) 拼接 db.Exec("DELETE FROM users WHERE name = '" + input + "'")
   输入 "小谷"           → 删了 1 行，全表剩 1 行，err=<nil>
      实际 SQL: DELETE FROM users WHERE name = '小谷'
   输入 "' OR 1=1 --"  → 删了 1 行，全表剩 0 行，err=<nil>
      实际 SQL: DELETE FROM users WHERE name = '' OR 1=1 --'
```

**参数化版删了 0 行、拼接版删了 1 行（`WHEN name = '' OR 1=1` → 删掉全表最后一行）。** 这就是那条老笑话的现实版：*"今天把一个 `'` 传进用户名，删库跑路提前实现了。"*

**为什么参数化能挡住？** 因为它把"SQL 语句"和"参数值"在协议层面分成了两样东西。**数据库收到的是"一条语句 + 一组值"，而不是"一段拼好的文本"** —— 值是值，永远不会被当成语法解析。这跟"转义引号"完全不同：

> ⚠️ **不要把参数化理解成"更安全的字符串拼接"。** 它是**另一条协议通道**。所以它有两个必然的副作用：
> 1. **占位符只能出现在"值"的位置**，不能用在表名、列名、`ORDER BY` 的字段名上（因为那些位置**必须**是语法）。要动态指定列名，只能白名单校验后拼接 —— 而那是**你自己负责**的安全边界。
> 2. **占位符的写法是驱动相关的**：`database/sql` 本身规定的是 `?`，但各驱动可以自己转换。SQLite / MySQL 用 `?`，PostgreSQL 用 `$1`、`$2`…… **`?` 是标准库给的通用写法**，具体驱动可能接受别的形式。

##### §1.7 事务：一个"绑定一条连接"的作用域

事务的四条机制，实测一遍最清楚：

```console
1) 转账 100：BeginTx → UPDATE → Rollback
   事务内看：小谷=900 小林=600（事务里读到的是自己的未提交改动）
   回滚后看：小谷=1000 小林=500 ← 回到原值

2) 同样的转账，这次 Commit
   提交后看：小谷=900 小林=600 ← 生效了

3) defer tx.Rollback() 的经典写法：Commit 之后 Rollback 会怎样
   Commit 之后再 Rollback → err = sql: transaction has already been committed or rolled back
   errors.Is(err, sql.ErrTxDone) = true
   （所以 `defer tx.Rollback()` 是安全的：成功提交后的 Rollback 只是白跑一次）
```

**第 3 条把那个"到处都能看到的 `defer tx.Rollback()`"解释清楚了**：它**不是**"提交之后还要回滚一次"的错误写法，而是**故意的**——用一个必定失败的 `Rollback` 兜住所有"提前 return"的路径，而成功路径上那次 `Rollback` 只会返回 `ErrTxDone`，**无害**。这个错误还有哨兵值可以判：

```go
errors.Is(err, sql.ErrTxDone) = true
```

**第 4 条是事务最重要的一个保证 —— 它占着一条连接：**

```console
4) 事务绑定一条连接：最大连接数 4，事务开着时 InUse 恒为 1
   事务内：Stats().Open=1 InUse=1 Idle=0
   事务内又查一次：Stats().Open=2 InUse=1 Idle=1
```

**注意 `InUse=1` 在事务内是恒定的** —— 事务里不管你查多少次，都用**同一条**连接（这正是"事务内能看到自己未提交的改动"能成立的原因）。而事务内**再查一次**时 `Open=2` —— 那第二次查询**临时借了另一条连接**。

**第 5 条把"忘了 Rollback"的后果量化了：**

```console
5) 忘记 Rollback：把 MaxOpenConns 降到 1，看第二次 BeginTx
   漏掉的 tx 还占着唯一连接时，第二次 BeginTx → err = context deadline exceeded
   Stats(): Open=1 InUse=1 WaitCount=1
   txA.Rollback() 之后，再 BeginTx → err = <nil>
```

**一个泄漏的事务 = 永远占着一条连接。** 上限 1 时，第二个事务直接等到超时；`Rollback()` 之后立刻恢复。**这也解释了为什么事务里的代码必须保证"每条路径都会 `Commit` 或 `Rollback`"** —— `defer tx.Rollback()` 就是干这个的。

**第 7 条推翻了一个很常见的误解 —— "语句报错 = 事务自动回滚"：**

```console
7) 事务里某条语句报错后，事务仍然“活着”，必须显式 Rollback
   事务内一条语句报错 → err = SQL logic error: no such table: 不存在的表 (1)
   报错之后事务里还能继续写、还能读到 6 行 → 说明事务没被自动回滚
   显式 Rollback 之后共 5 行（那一行没进去）
```

**语句报错之后，事务里还能继续写、还能读到之前写的东西。** 因为**"事务回滚"是数据库层面的决定（由隔离级别和具体错误类型决定），不是 Go 层面的自动行为**。所以：

> 🐞 **事务里的错误处理铁律：拿到的 `error` 只要非 nil，就应该"停止业务逻辑 + 显式 `Rollback`"，而不是"接着往下写"。** 标准库不会替你做这个决定 —— 而且**每个数据库、每种错误的"是否可继续"规则都不一样**。统一按"出错就回滚"处理是唯一安全的写法。

##### §1.8 ★ 把 `r.Context()` 接进来：课 10 → 课 11 → 课 12 的取消链路闭环

这是本课**最重要的一个演示**，因为它是课 10 那棵取消树、课 11 的 `r.Context()`、和本课的 `QueryContext` 三者的**汇合点**。

链路是这样的：

```
客户端（带 400ms 超时）
   │  ① 发起 HTTP 请求
   ▼
net/http Server ──► r.Context()          ← 课 11：客户端断开时它被 cancel
   │  ② r.Context() 传下去
   ▼
db.QueryRowContext(ctx, ...)             ← 课 12：把 ctx 交给驱动
   │  ③ 驱动把"取消"翻译成协议层的中断
   ▼
数据库                                      慢查询被中止
```

**实测①：直接在 sql 层看（不经过 HTTP）**

```console
1) QueryRowContext + 300ms 超时（直接看 sql 层）
   耗时 301ms  err = context deadline exceeded
   errors.Is(err, context.DeadlineExceeded) = true
```

**300 毫秒的 ctx，301 毫秒返回 `context deadline exceeded`** —— 干净、准时、可判（`errors.Is` 认得出来）。

**实测②：对照组 —— 不带 ctx 的 `QueryRow`**

```console
2) 对照：QueryRow（不带 ctx）——没人能叫停它
   耗时 476ms  err = <nil>  count = 2000000（跑完了）
```

**同样的慢查询，`QueryRow` 版本没人拦得住**，跑完了。

**实测③：全链路 —— 客户端中途断开**

服务端起了两个端点：`/orders/ctx`（用 `r.Context()`）和 `/orders/nocancel`（用裸 `QueryRow`）。客户端**带 400 ms 超时**打这两个端点：

```console
3) 全链路：客户端中途断开 → r.Context() 取消 → 查询中止
   服务已起：http://127.0.0.1:51073
   3a) /orders/ctx：客户端 400ms 就放弃
[服务端 13:49:22.899] 收到请求 /orders/ctx，handler 开始跑慢查询（递归 CTE，数秒量级）
   客户端 /orders/ctx 在 401ms 后放弃 → err = Get "http://127.0.0.1:51073/orders/ctx": context deadline exceeded
[服务端 13:49:23.300] 查询返回：err=context canceled 耗时=400ms

   3b) /orders/nocancel：客户端同样 400ms 放弃，但 handler 忽略了 ctx
[服务端 13:49:23.901] 收到请求 /orders/nocancel，handler 用 QueryRow（忽略 ctx）
   客户端 /orders/nocancel 在 401ms 后放弃 → err = Get "http://127.0.0.1:51073/orders/nocancel": context deadline exceeded
[服务端 13:49:25.326] 查询返回：err=<nil> 耗时=1.425s

   结论：3a 里查询在客户端放弃的同一瞬间被 ctx 掐断（约 0.4 秒）；
         3b 里同一条查询完整跑完（耗时见上方服务端日志），没有人能叫停它。
```

**读这四行的关键在时间戳：**

| 端点 | 客户端放弃 | 服务端查询结束 | 服务端看到的 error | 查询真的停了吗 |
|---|---|---|---|---|
| `/orders/ctx` | 401 ms | **同一瞬间**（耗时 = 400 ms） | **`context canceled`** | ✅ **停了** |
| `/orders/nocancel` | 401 ms | 客户端走后**又跑了 1 秒多** | `<nil>`（跑完了） | ❌ **没停，白跑** |

**"客户端走了，但服务端还在替一个已经不存在的请求干活"** —— 这就是为什么 3b 那个 1.425 秒是纯粹的浪费。在高并发下，这类浪费会以**连接池被占满 + 数据库 CPU 打满**的形式反噬回来。

> 💡 **`r.Context()` 的服务端侧语义，官方原话**（课 11 已引，这里再引一遍，因为它是这条链路的起点）：
> *"For incoming server requests, the context is canceled when the client's connection closes, the request is canceled (with HTTP/2), or when the ServeHTTP method returns."*
>
> 所以三件事都能 cancel 它：**客户端断开 / HTTP/2 显式取消 / handler 返回。**
>
> ⚠️ **但请回看 §1.1 结尾那句话**：*"Drivers that do not support context cancellation will not return until after the query is completed."* —— **能不能真的掐断，取决于驱动。** 这里用的 `modernc.org/sqlite` 支持；**如果你换一个不支持的驱动，同一个 `QueryRowContext` 只会在数据库跑完之后才返回 `context canceled`** —— 错误对，但"提前返回"这个好处没有了。

**这条链路的完整口诀**：

> **HTTP 层拿到的 ctx，一路往下传，一直传到最底层的 I/O。** 中间任何一层断了（不传 ctx / 自己 `context.Background()` / 起一个不带 ctx 的 goroutine），链路就断在这里。**课 10 讲"取消是树"、课 11 讲"树的落点"、本课讲"树怎么长到数据库上"，三课加起来才是完整的。**

##### §1.9 常用错误与判法速查

| 错误 | 什么时候出现 | 怎么判 |
|---|---|---|
| `sql.ErrNoRows` | `QueryRow().Scan()` 没查到行 | `errors.Is(err, sql.ErrNoRows)` |
| `sql.ErrTxDone` | 对已 `Commit`/`Rollback` 的事务再操作 | `errors.Is(err, sql.ErrTxDone)` |
| `sql: expected N destination arguments in Scan, not M` | `Scan` 的目标个数与列数不匹配 | 直接看错误文本；这是**编码错误**，不是运行时错误 |
| `sql: Scan error on column index …: converting NULL to … is unsupported` | NULL 扫进了非 `Null*` 类型 | 用 `sql.Null*` 或 `COALESCE` |
| `context deadline exceeded` / `context canceled` | 排队超时 / 查询被取消 | `errors.Is(err, context.DeadlineExceeded)` / `context.Canceled` |
| `driver: bad connection` | 池子发现这条连接坏了，会**自动重试一次新连接** | 一般不该冒到你这里；冒出来说明重试也失败了 |

关于最后一条，驱动接口里有两个相关的约定（源码原文，核查于 2026-09）：

```go
// Errors will be checked using [errors.Is]. An error may
// wrap ErrBadConn or implement the Is(error) bool method.
var ErrBadConn = errors.New("driver: bad connection")

type Validator interface {
	// IsValid is called prior to placing the connection into the
	// connection pool. The connection will be discarded if false is returned.
	IsValid() bool
}
```

**意思是**：驱动在"发现这条连接已经不可用"时可以返回 `ErrBadConn`，标准库看到它会**从池里扔掉这条连接、拿一条新的重试**。而 `Validator` 让驱动能在**连接放回池子之前**再确认一次它还活着。**这两条机制合起来，就是"为什么你的代码里很少看到 `bad connection`"** —— 池子在你看不见的地方处理掉了。

#### ④ 示例演示：一个完整可跑的 mini DAO

下面这份代码是本课探针的核心部分（`/tmp/go-l12/p2_query_exec` 与 `p4_tx` 的合并简化版），**在 go1.27.1 上真实跑通过**，输出紧跟其后。

```go
// package main —— 用 modernc.org/sqlite（纯 Go、无 CGO）跑一个真实的 mini DAO
package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"log"
	"time"

	_ "modernc.org/sqlite"
)

// ---------- §1 池子配置：四个旋钮全部显式设 ----------
func newDB(ctx context.Context, dsn string) (*sql.DB, error) {
	// Open 只是建池子，不连接
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("sql.Open: %w", err)
	}

	db.SetMaxOpenConns(10)                  // 0 = 不限 → 必须显式设
	db.SetMaxIdleConns(10)                  // 默认只有 2；先设 MaxOpen 再设它
	db.SetConnMaxLifetime(30 * time.Minute) // 别超过后端 LB 的空闲超时
	db.SetConnMaxIdleTime(5 * time.Minute)

	// Open 不连接，这里显式验证一次，早失败
	if err := db.PingContext(ctx); err != nil {
		db.Close()
		return nil, fmt.Errorf("Ping: %w", err)
	}
	return db, nil
}

// ---------- §2 建表 + 写入：Exec 用 RowsAffected ----------
func initSchema(ctx context.Context, db *sql.DB) error {
	ddl := `CREATE TABLE orders (
		id      INTEGER PRIMARY KEY AUTOINCREMENT,
		sku     TEXT    NOT NULL,
		qty     INTEGER NOT NULL,
		amount  REAL,                 -- 可能为 NULL，用来演示 sql.Null*
		status  TEXT    NOT NULL DEFAULT 'pending'
	)`
	if _, err := db.ExecContext(ctx, ddl); err != nil {
		return fmt.Errorf("create table: %w", err)
	}
	return nil
}

// ---------- §3 参数化查询：占位符 ? 而不是拼接 ----------
func insertOrder(ctx context.Context, db *sql.DB, sku string, qty int, amount *float64) (int64, error) {
	res, err := db.ExecContext(ctx,
		`INSERT INTO orders (sku, qty, amount) VALUES (?, ?, ?)`,
		sku, qty, amount) // ← 参数永远走参数通道，不进 SQL 文本
	if err != nil {
		return 0, fmt.Errorf("insert: %w", err)
	}
	return res.LastInsertId()
}

// ---------- §4 QueryRow + ErrNoRows：注意先判 ErrNoRows ----------
type Order struct {
	ID     int64
	SKU    string
	Qty    int
	Amount sql.NullFloat64
}

func getOrder(ctx context.Context, db *sql.DB, id int64) (*Order, error) {
	var o Order
	err := db.QueryRowContext(ctx,
		`SELECT id, sku, qty, amount FROM orders WHERE id = ?`, id).
		Scan(&o.ID, &o.SKU, &o.Qty, &o.Amount)

	switch {
	case errors.Is(err, sql.ErrNoRows):
		return nil, nil // 业务语义：不存在
	case err != nil:
		return nil, fmt.Errorf("query order %d: %w", id, err)
	}
	return &o, nil
}

// ---------- §5 Query + rows：遍历时先收数据再判 Next ----------
func listOrders(ctx context.Context, db *sql.DB, sku string) ([]Order, error) {
	rows, err := db.QueryContext(ctx,
		`SELECT id, sku, qty, amount FROM orders WHERE sku = ? ORDER BY id`, sku)
	if err != nil {
		return nil, fmt.Errorf("query list: %w", err)
	}
	defer rows.Close() // ← 必须在遍历之前注册

	var out []Order
	for rows.Next() {
		var o Order
		if err := rows.Scan(&o.ID, &o.SKU, &o.Qty, &o.Amount); err != nil {
			return nil, fmt.Errorf("scan: %w", err)
		}
		out = append(out, o)
	}
	// ★ 循环结束后必须查 Err：Scan 内部的错误不会从 Next 里冒出来
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows iteration: %w", err)
	}
	return out, nil
}

// ---------- §6 事务：BeginTx + defer Rollback + 显式 Commit ----------
func transfer(ctx context.Context, db *sql.DB, fromID, toID int64, cents int64, fail bool) error {
	tx, err := db.BeginTx(ctx, nil) // nil = 用默认隔离级别
	if err != nil {
		return fmt.Errorf("begin: %w", err)
	}
	// 幂等、无害：成功 Commit 之后它只会返回 sql.ErrTxDone
	defer tx.Rollback()

	if _, err := tx.ExecContext(ctx, `UPDATE orders SET qty = qty - ? WHERE id = ?`, cents, fromID); err != nil {
		return fmt.Errorf("debit: %w", err)
	}
	if fail {
		// 业务中途出错：直接 return，defer 的 Rollback 会兜住
		return errors.New("业务校验失败，事务作废")
	}
	if _, err := tx.ExecContext(ctx, `UPDATE orders SET qty = qty + ? WHERE id = ?`, cents, toID); err != nil {
		return fmt.Errorf("credit: %w", err)
	}
	return tx.Commit() // 只有这一条路径会真的提交
}

// ---------- main ----------
func main() {
	ctx := context.Background()

	db, err := newDB(ctx, "file:/tmp/l12_demo.db?_pragma=journal_mode(WAL)")
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close() // 进程退出时关一次即可；正常服务里"极少需要 Close"

	if err := initSchema(ctx, db); err != nil {
		log.Fatal(err)
	}

	id1, err := insertOrder(ctx, db, "A-100", 2, ptr(19.90))
	if err != nil {
		log.Fatal(err)
	}
	_, _ = insertOrder(ctx, db, "B-200", 1, ptr(99.00))
	_, _ = insertOrder(ctx, db, "A-100", 5, ptr(49.75))
	fmt.Printf("插入 3 单，第一条 id=%d\n", id1)

	o, err := getOrder(ctx, db, id1)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("查 id=%d → sku=%s qty=%d amount=%.2f(valid=%v)\n", id1, o.SKU, o.Qty, o.Amount.Float64, o.Amount.Valid)

	missing, err := getOrder(ctx, db, 99999)
	fmt.Printf("查 id=99999 → 订单=%v err=%v（业务分支，不是错误）\n", missing, err)

	list, err := listOrders(ctx, db, "A-100")
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("sku=A-100 共 %d 单\n", len(list))

	// 事务：先失败一次（看回滚），再成功一次（看提交）
	if err := transfer(ctx, db, 1, 2, 100, true); err != nil {
		fmt.Printf("事务（预期失败）→ %v\n", err)
	}
	if err := transfer(ctx, db, 1, 2, 100, false); err != nil {
		log.Fatal(err)
	}
	fmt.Println("事务（预期成功）→ 已提交")

	// 观测：池子的四个数字
	s := db.Stats()
	fmt.Printf("Stats(): Open=%d InUse=%d Idle=%d WaitCount=%d\n", s.OpenConnections, s.InUse, s.Idle, s.WaitCount)
}

func ptr[T any](v T) *T { return &v }
```

**它的真实输出**（`/tmp/go-l12/p15_dao`，本机 go1.27.1 逐字记录）：

```console
① 插入 3 单，第一条 id=1
② 查 id=1 → sku=A-100 qty=2 amount=19.90(valid=true)
③ 查 id=99999 → 订单=<nil> err=<nil>（业务分支，不是错误）
④ sku=A-100 共 2 单
⑤ 事务（预期失败）→ 业务校验失败，事务作废
   回滚验证：id=1 的 qty 事务前=2 事务后=2（有变化吗：false）
⑥ 事务（预期成功）→ 已提交；id=1 的 qty 由 2 变 1
⑦ 对已提交的事务再 Rollback → err=sql: transaction has already been committed or rolled back（errors.Is ErrTxDone=true）
⑧ 参数化 WHERE sku=? 传 "' OR 1=1 --" → 命中 0 行
⑨ Stats(): Open=1 InUse=0 Idle=1 WaitCount=0 WaitDuration=0s
```

**逐行读一遍，每行都对应前面讲过的一条原理：**

| 行 | 输出 | 它证明了什么 |
|---|---|---|
| ① | `id=1` | `LastInsertId()` 在 SQLite + 自增主键下可用 |
| ② | `qty=2 amount=19.90(valid=true)` | `sql.NullFloat64` 的 `Valid` 分支正常 |
| ③ | `订单=<nil> err=<nil>` | **"查不到"被 §1.4 的 switch 翻译成了业务语义**（返回 `nil, nil`），**不是错误** —— 这就是"先判 `ErrNoRows`"的价值 |
| ④ | `共 2 单` | 多次 `Scan` + `rows.Err()` 都正常 |
| ⑤ | `事务前=2 事务后=2（有变化吗：false）` | **`defer tx.Rollback()` 真的回滚了**（中途 `return` 的路径被兜住） |
| ⑥ | `由 2 变 1` | 成功路径上 `Commit()` 生效；**同一个 `defer tx.Rollback()` 在提交后没有副作用** |
| ⑦ | `errors.Is ErrTxDone=true` | 幂等性：`defer tx.Rollback()` 的"白跑一次"是可判的、无害的 |
| ⑧ | `命中 0 行` | 参数化把 `' OR 1=1 --` 当成**普通字符串**（撞墙 A 的 §1.6 对照） |
| ⑨ | `Open=1 InUse=0 Idle=1 WaitCount=0` | 全部请求做完后，**池子里只有 1 条空闲连接、没有人排队** |

**注意 ⑨ 行的 `WaitCount=0`** —— 这是本课建议你在生产上加进监控的那两个数字之一。**只要 `WaitCount` 开始涨，就说明池子小了。**

下面是**本课另外两组探针的逐字记录**，覆盖上面的示例没展开的边界（错误原文、NULL、类型不匹配、事务占连接、忘记 `Rollback`）：

```console
1) CREATE TABLE → LastInsertId=0 RowsAffected=0
   INSERT A-100  → id=1 RowsAffected=1
   INSERT B-200  → id=2 RowsAffected=1
   INSERT A-100  → id=3 RowsAffected=1
2) Query 多行：
   id=1  sku=A-100  qty=2 amount=19.9(valid=true)
   id=2  sku=B-200  qty=1 amount=99(valid=true)
   id=3  sku=A-100  qty=5 amount=49.75(valid=true)
3) QueryRow：
   命中 → id=2 sku=B-200 err=<nil>
   未命中 → err=sql: no rows in result set（是 sql.ErrNoRows）
   errors.Is(err, sql.ErrNoRows) = true
4) 用聚合函数就不会 ErrNoRows：COUNT=0 err=<nil>
5) 参数类型不匹配 → err = sql: no rows in result set
6) Scan 目标少一个 → err = sql: expected 3 destination arguments in Scan, not 1
7) NULL 扫进 *float64 → err = sql: Scan error on column index 0, name "amount": converting NULL to float64 is unsupported
   用 sql.NullFloat64 → err=<nil> valid=false
8) Columns() = [id sku amount]
9) SUM(qty*amount) = 387.55
```

```console
1) 转账 100：BeginTx → UPDATE → Rollback
   事务内看：小谷=900 小林=600（事务里读到的是自己的未提交改动）
   回滚后看：小谷=1000 小林=500 ← 回到原值

2) 同样的转账，这次 Commit
   提交后看：小谷=900 小林=600 ← 生效了

3) defer tx.Rollback() 的经典写法：Commit 之后 Rollback 会怎样
   Commit 之后再 Rollback → err = sql: transaction has already been committed or rolled back
   errors.Is(err, sql.ErrTxDone) = true
   （所以 `defer tx.Rollback()` 是安全的：成功提交后的 Rollback 只是白跑一次）

4) 事务绑定一条连接：最大连接数 4，事务开着时 InUse 恒为 1
   事务内：Stats().Open=1 InUse=1 Idle=0
   事务内又查一次：Stats().Open=2 InUse=1 Idle=1

5) 忘记 Rollback：把 MaxOpenConns 降到 1，看第二次 BeginTx
   漏掉的 tx 还占着唯一连接时，第二次 BeginTx → err = context deadline exceeded
   Stats(): Open=1 InUse=1 WaitCount=1
   txA.Rollback() 之后，再 BeginTx → err = <nil>

6) 事务内 PrepareContext + 多次 Exec
   Prepare → err=<nil>
   提交后共 5 行

7) 事务里某条语句报错后，事务仍然“活着”，必须显式 Rollback
   事务内一条语句报错 → err = SQL logic error: no such table: 不存在的表 (1)
   报错之后事务里还能继续写、还能读到 6 行 → 说明事务没被自动回滚
   显式 Rollback 之后共 5 行（那一行没进去）
```

**这份示例里有 6 个"必须这么写"的点**，逐条对上前面的原理：

| # | 写法 | 对应原理 |
|---|---|---|
| 1 | `sql.Open` **一次**，之后全程复用这一个 `db` | §1.1 事实 1；撞墙 A |
| 2 | 四个 setter **全部显式设**，且 `MaxOpen` 先于 `MaxIdle` | §1.2；D 场景"高峰不设防、低谷留太少" |
| 3 | 所有 SQL 全部用 `?` 占位符 | §1.6；注入对照实测 |
| 4 | `QueryRow` 的错误**先判 `ErrNoRows`** | §1.4；"未命中"不是错误（输出 ③） |
| 5 | `defer rows.Close()` + 循环后 `rows.Err()` | §1.5；只 `Next` 不查 `Err` 会漏掉 Scan 错误 |
| 6 | `defer tx.Rollback()` + 成功路径显式 `Commit()` | §1.7；输出 ⑤⑥⑦ 三条一起证明了它 |

#### ⑤ 常见误区（知识点 1）

| # | 误区 | 真相 | 实测依据 |
|---|---|---|---|
| 1 | `sql.Open` 会连上数据库 | **可能一条连接都不建**（首次查询才连） | `Open 次数 = 0` → 首次查询后 `= 1` |
| 2 | `sql.Open` 很贵，所以要用连接池包一层 | `Open` 成本接近零；**它本身就是池** | 文档：*"may just validate its arguments"* |
| 3 | 每次请求 `Open` + `defer Close` 是"好习惯" | 那是**每请求新建一个池子**；官方说 *"should be called just once"* | 5 次查询 = 5 次 OPEN + 5 次 CLOSE（C 例） |
| 4 | `sql.DB` 是一条连接 | 是**零条或多条连接的池**（源码原文 `pool of zero or more`） | A 例：`Open` 后 0 条 |
| 5 | `MaxOpenConns` 默认有个合理值 | **默认 0 = 不限** | D 例：6 个并发就开了 6 条 |
| 6 | `MaxIdleConns` 默认够用 | 默认 **2**，且源码写着 *"may change in a future release"* | D 例 `Stats(): Open=2 Idle=2` |
| 7 | 先设 `MaxIdleConns` 再设 `MaxOpenConns` 没关系 | `MaxIdleConns` 会被**自动压到 ≤ `MaxOpenConns`** | 源码 `if db.maxOpen > 0 && … > db.maxOpen` |
| 8 | `ConnMaxIdleTime` 设小一点会立刻回收 | 清理协程**最快每秒一轮**（`minInterval = time.Second`） | G 例：设 60 ms，1.5 s 后才 `Idle=0` |
| 9 | `db.Close()` 应该 `defer` 在每个请求里 | 官方：*"It is rarely necessary to close a DB"* | — |
| 10 | `QueryRow` 会返回错误 | **它不返回 error**；错误被推迟到 `Scan` | 官方签名如此；"未命中"也从 `Scan` 出来 |
| 11 | `ErrNoRows` 一定是"没有这条记录" | 参数类型不匹配也是它（SQL 里"匹配不到"而已） | 第 5 条：`参数类型不匹配 → err = sql: no rows in result set` |
| 12 | 判 `err != nil` 就报 500 | **必须先 `errors.Is(err, sql.ErrNoRows)`** | §1.4 的 switch 写法 |
| 13 | `rows` 不 `Close` 也没事，GC 会管 | GC 管得**不及时**；池子会先被抽干 | 2 条不关 → 第三次查询 `context deadline exceeded` |
| 14 | 遍历到结束就不需要 `Close` | 是真的（自动归还），**但提前 `break`/`return` 就不成立** | `for rows.Next()` 跑到底 → `InUse=0` |
| 15 | 循环里只判 `rows.Next()` 就够 | **必须再查 `rows.Err()`** | 官方：*"it will suffice to check the result of Rows.Err"* |
| 16 | `rows.Close()` 调两次会出错 | **幂等**，且不影响 `Rows.Err` 的结果 | 源码原文 |
| 17 | `Scan` 的目标个数可以随便给 | 个数不匹配直接报错 | `sql: expected 3 destination arguments in Scan, not 1` |
| 18 | NULL 扫进 `*float64` 会变成 0 | **直接报错**，不静默 | `converting NULL to float64 is unsupported` |
| 19 | `LastInsertId` / `RowsAffected` 总是有意义 | `CREATE TABLE` 返回 `0 / 0`；可靠性由驱动决定 | `CREATE TABLE → LastInsertId=0 RowsAffected=0` |
| 20 | 手写"转义引号"就能防注入 | **不能**。参数化是**另一条协议通道**，不是"更安全的拼接" | 拼接版 `' OR 1=1 --` 删掉全表最后一行 |
| 21 | 参数化能用在表名 / 列名上 | **不能**，那些位置必须是语法；要动态列名只能白名单校验后拼接 | — |
| 22 | 事务里的语句报错会自动回滚 | **不会**。报错后事务还能继续写和读 | 报错后仍读到 6 行；显式 `Rollback` 后剩 5 行 |
| 23 | 事务不占连接 | **绑定一条连接**，`InUse` 恒为 1 | 事务内 `Stats().Open=1 InUse=1` |
| 24 | 忘了 `Rollback` 影响不大 | 一条泄漏的事务**永久占一条连接** | `MaxOpenConns=1` 时第二个事务 `context deadline exceeded` |
| 25 | `defer tx.Rollback()` 在提交后会报错所以不该写 | 报的是 `ErrTxDone`，**无害**，这正是它的用途 | `errors.Is(err, sql.ErrTxDone) = true` |
| 26 | 只要写了 `QueryRowContext` 就一定能取消 | **取决于驱动**；不支持的驱动会等查询跑完 | 文档：*"Drivers that do not support context cancellation will not return until…"* |
| 27 | `:memory:` 数据库在同一个 `sql.DB` 里是同一份数据 | **每条连接一个独立的库**；要多连接共享得 `file::memory:?cache=shared` | 并发 4 次：成功 1 次、失败 3 次（`no such table`） |
| 28 | 用 `db.Stats()` 没意义 | **它是唯一能看见池子内部状态的入口** | E 例 `WaitCount=7 WaitDuration=1.45s` |

#### ⑥ 一句话记住

> **`sql.DB` 是"进程级的连接池句柄"：`Open` 只建池不连接、全程复用一个、极少 `Close`；借了 `rows` 必须还，排队必须带 `ctx`，写 SQL 必须用占位符，开事务必须保证每条路径都 `Commit` 或 `Rollback` —— 而把 `r.Context()` 一路传下来，就是"客户端一走、数据库就停"的唯一办法。**

#### 📚 官方文档

- 包文档与 `DB` 类型定义：`go doc database/sql` ／ [pkg.go.dev/database/sql](https://pkg.go.dev/database/sql)
- 连接池四个旋钮：`go doc database/sql.DB.SetMaxOpenConns` 等（**零值语义只在源码注释里，务必读注释**）
- `Rows` 与 `Row`：`go doc database/sql.Rows` ／ `go doc database/sql.Row`
- 驱动接口（写驱动才需要）：`go doc database/sql/driver`
- 驱动列表：<https://golang.org/s/sqldrivers>
- 本课使用的驱动：`modernc.org/sqlite`（**纯 Go 实现、不需要 CGO**，因此本课示例在任何机器上都能跑）

---

### 知识点 2：http.Client

#### ① 一句话定义

**`http.Client` 是"一个能发 HTTP 请求的、带连接池的、可复用的句柄"——它的零值 `DefaultClient` 能直接用，但它的超时默认是"永不超时"，它的连接池默认是"每主机只留 2 条空闲连接"；而 `resp.Body` 是这次请求占用的资源，**不关就不还**。**

#### ② 直觉建立（类比 + 失效边界）

**类比：打车（以及"你还得自己下车"）。**

把一次 `client.Do(req)` 想成打一次车：

- **`http.Client` 是"你手机里的打车 App"**（不是一个司机）——App 只有一个，但能叫很多次车。**每叫一次车都重装一遍 App**，就是撞墙 B 里那个"100 次请求 100 条连接"。
- **`Transport` 是"车队"**——车队里有多少辆车、每辆车能停多久、同一个目的地最多同时派几辆，这些都是车队参数（`MaxIdleConns` / `IdleConnTimeout` / `MaxConnsPerHost`）。
- **一次 `Do` 是一次行程**，返回的 `resp.Body` 就是**这趟车的行程记录**——**你必须"看完并下车"，车才能回车队接下一单。** 你赖在车上（不 `Close`），这辆车就一直被你占着。
- **`Client.Timeout` 是"整个行程的总时限"**——包含"等车来"（建连）、"路上"（读 headers）、"看行程记录"（读 body）。**超过就整趟作废。**

**这个类比在哪里失效（三条）：**

1. **"车"不会自己回来。** 打车 App 里你不下车，司机也会催你；Go 里 `resp.Body` 不 `Close`，**没有任何人催你**——那条连接就一直在"使用中"状态，连接池里少一条，直到 GC 顺手把 `resp.Body` 收掉（**时间不确定**）。**这是 `net/http` 客户端第一大事故源。**
2. **"看完行程记录"这件事在 Go 1.27 变便宜了。** 老规矩是"必须读到 EOF"；现在**关掉它就会触发一次异步排空**（上限 256 KiB / 50 ms）。所以类比里的"看完"其实是"**关掉就会自动帮你看一小段**"。
3. **"重试"App 不会替你做，而且不该随便做。** `net/http` **完全不做自动重试**（除了极少数幂等连接的透明重试）。要不要重试、重试几次、退避多久，**全是你自己的责任** —— 而这个责任做错了就是"把上游打死的放大器"。

#### ③ 核心原理

##### §2.1 默认值：`Timeout = 0` 与 `DefaultTransport` 的每一个字段

先把"默认到底长什么样"钉死。`Client` 的定义里最关键的两行：

```go
// A Client is an HTTP client. Its zero value ([DefaultClient]) is a
// usable client that uses [DefaultTransport].
//
// The [Client.Transport] typically has internal state (cached TCP
// connections), so Clients should be reused instead of created as
// needed. Clients are safe for concurrent use by multiple goroutines.
...
	// A Timeout of zero means no timeout.
	Timeout time.Duration
}

// DefaultClient is the default [Client] and is used by [Get], [Head], and [Post].
var DefaultClient = &Client{}
```

> 源码原文，核查于 2026-09（`$GOROOT/src/net/http/client.go`）

**三条事实**：

1. **零值是"可用"的**（`usable client`）—— 所以你写 `http.Get(...)` 不会报错。
2. **`Clients should be reused`** —— 和 `sql.Open` 那句 *"should be called just once"* 是同一个设计意图。
3. **`A Timeout of zero means no timeout`** —— **默认永不超时**。这和课 11 讲的 `&http.Server{}` 四个超时全零值是**同一类陷阱**，只不过发生在客户端侧。

实测确认（`DefaultClient.Timeout` 打印出来是 `0s`）：

```console
1) 默认 http.Get —— Timeout 字段是 0，等于“永不超时”
   DefaultClient.Timeout = 0s
   耗时 2.003s，body="慢响应终于来了" ← 硬等了 2 秒，没人拦得住
```

**2 秒的慢响应，默认客户端硬等了 2 秒。** 如果下游挂了、连接一直挂着不返回，它就会**一直等下去** —— 这就是"一个下游故障拖垮整个服务"的经典路径。

那 `DefaultTransport` 呢？把它的字段全部打出来：

```console
5) DefaultTransport 的真实字段值
   DefaultTransport 是 *http.Transport：true
   Proxy               = func(*http.Request) (*url.URL, error)（ProxyFromEnvironment）
   ForceAttemptHTTP2   = true（注意：DefaultTransport 里显式打开了）
   MaxIdleConns        = 100
   MaxIdleConnsPerHost = 0 ← 未设置，所以用常量 2
   IdleConnTimeout     = 1m30s
   TLSHandshakeTimeout = 10s
   ExpectContinueTimeout = 1s
   DisableKeepAlives   = false
   DisableCompression  = false
```

对照源码原文（一个字一个字对得上）：

```go
var DefaultTransport RoundTripper = &Transport{
	Proxy: ProxyFromEnvironment,
	DialContext: defaultTransportDialContext(&net.Dialer{
		Timeout:   30 * time.Second,
		KeepAlive: 30 * time.Second,
	}),
	ForceAttemptHTTP2:     true,
	MaxIdleConns:          100,
	IdleConnTimeout:       90 * time.Second,
	TLSHandshakeTimeout:   10 * time.Second,
	ExpectContinueTimeout: 1 * time.Second,
}
```

> 源码原文，核查于 2026-09（`$GOROOT/src/net/http/transport.go`）

**逐条对照后最该注意的一处**：`MaxIdleConnsPerHost = 0`（**字段没出现在字面量里**），而它的注释写着：

```go
// MaxIdleConnsPerHost, if non-zero, controls the maximum idle
// (keep-alive) connections to keep per-host. If zero,
// DefaultMaxIdleConnsPerHost is used.
MaxIdleConnsPerHost int
```

```go
// DefaultMaxIdleConnsPerHost is the default value of [Transport]'s
// MaxIdleConnsPerHost.
const DefaultMaxIdleConnsPerHost = 2
```

> 源码原文，核查于 2026-09

**`0` 不代表"不限"，它代表"去查那个常量"，而那个常量是 `2`。** 这是本课最容易读错的一处默认值 —— **注意它和 `MaxIdleConns = 0` 的语义完全相反**：

| 字段 | 零值含义 | 实际生效值 |
|---|---|---|
| `MaxIdleConns` | **0 = 不限** | 100（因为 `DefaultTransport` 显式设了） |
| `MaxIdleConnsPerHost` | **0 = 用常量** | **2** |
| `MaxConnsPerHost` | 0 = 不限 | 不限 |
| `IdleConnTimeout` | 0 = 不限 | 90 s（显式设了） |

> ⚠️ **同一份结构体里，两个看起来一样的 `0` 含义相反** —— 一个是"不限"，一个是"去查默认常量"。**读 `Transport` 的字段时必须逐个看注释，不能凭"零值语义"批量推理。**

##### §2.2 `Client.Timeout` 到底覆盖哪几段

`Timeout` 的注释里写着（原文）：

> *"Timeout specifies a time limit for requests made by this Client. The timeout includes connection time, any redirects, and reading the response body."*
> （核查于 2026-09）

**"includes connection time, any redirects, and reading the response body"** —— 三件事都算在里面。逐段实测：

**① 建连 + 首字节（"awaiting headers"）**

```console
2) Client{Timeout: 300ms} —— 300 毫秒后主动放弃
   耗时 302ms
   err = Get "http://127.0.0.1:51078/slow": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
   err.(*url.Error).Timeout() = true
   errors.Is(err, context.DeadlineExceeded) = true
```

**注意括号里那句话：`(Client.Timeout exceeded while awaiting headers)`** —— 这是标准库**明确告诉你超时发生在哪个阶段**。后面还会看到另一个变体，见下。

**② 读 body —— 头已经回来了，body 还在慢慢发**

```console
3) Client.Timeout 覆盖“读 body”：头 1ms 就回来了，body 要 4 秒
   拿到响应头，耗时 1ms，状态 200 OK
   读 body 时被掐断：读了 18 字节，err = context deadline exceeded (Client.Timeout or context cancellation while reading body)，总耗时 301ms
```

**这一条极重要**：**状态码已经 200 了，但读 body 读到一半被掐断。** 很多人以为"`Timeout` 只管到拿到响应为止"，实测证明**它一直管到你读完 body**。如果代码里没有检查 `Read` 的错误，**你会把半截 body 当成完整数据用**。

两种超时文案不一样（`awaiting headers` vs `reading body`），**这是排查"到底卡在哪一段"的最好线索**。

**③ 也可以用 `context` 控超时**

```console
4) 用 context 控超时（Client.Timeout 之外的另一条路）
   耗时 251ms  err = Get "http://127.0.0.1:51078/slow": context deadline exceeded
```

**`Client.Timeout` 与 `ctx` 的关系**（这几句话值得背下来）：

| 问题 | 答案 |
|---|---|
| 两者冲突时谁生效？ | **先到点的那个**。`Client.Timeout` 在内部就是"给请求套一个有 deadline 的 ctx"（官方注释：*"The Client cancels requests to the underlying Transport as if the Request's Context ended."*） |
| 该用哪个？ | **请求级超时用 `ctx`**（因为能沿调用链传下去、能和上游的 deadline 对齐）；**`Client.Timeout` 作为兜底**（防止有人忘了传带超时的 ctx）。**两个都设，不冲突。** |
| 超时后连接会怎样？ | **被丢弃，不会回池子**（半途取消的连接不能复用） |

**超时该设多少？给一个可操作的区间**：

| 场景 | 建议 | 理由 |
|---|---|---|
| 内部 RPC（同机房） | **200 ms ~ 1 s** | 同机房 P99 通常在 50 ms 以内；设 1 s 已经是很宽的容忍 |
| 调用外部第三方 API | **2 s ~ 10 s** | 对方可能慢，但你的用户不能等 |
| 用户的请求总 deadline | **上游给多少，下游就 ≤ 多少** | 别让下游的 timeout 大于上游的 timeout，否则你会"替一个已经不存在的请求干活"（回看知识点 1 §1.8 的 `/orders/nocancel`） |
| **绝不能做** | 留 `0`（永不超时） | 一个卡死的下游会把你的连接池和 goroutine 全部耗尽 |

##### §2.3 `resp.Body` 的生命周期：6 种写法与 Go 1.27 的"关即排空"

这是本课**推翻老教材**的那一节。6 种写法并排（判定方式是**连发两条请求，看第二条的 `httptrace.GotConnInfo.Reused`**）：

```console
A 读到 EOF 再 Close      /small  (4 KiB)                → ✅ 复用了同一条连接
B 不读直接 Close         /small  (4 KiB)                 → ✅ 复用了同一条连接
C 不读直接 Close         /big    (1 MiB)                 → ❌ 没复用（新连接）
D 不读直接 Close         /dribble(128 KiB / 400ms)       → ❌ 没复用（新连接）
E 先 Copy 到 EOF 再 Close /big    (1 MiB)               → ✅ 复用了同一条连接
F 读完再 Close，服务端 Connection: close                    → ❌ 没复用（新连接）
```

**把这张表按"什么时候能复用"重排**，规律就出来了：

| 写法 | 关键变量 | 结论 |
|---|---|---|
| A / E | **主动读到 EOF**（不论 body 多大） | ✅ 一定复用 |
| B | 不读，但 body **≤ 256 KiB 且 50 ms 内能读完** | ✅ 复用（Go 1.27 的自动排空救了你） |
| C | 不读，body **> 256 KiB** | ❌ 不复用 |
| D | 不读，body **需要 > 50 ms 才能读完** | ❌ 不复用 |
| F | 服务端明确说 `Connection: close` | ❌ 不复用（**服务端拒绝复用，你读得再干净也没用**） |

**所以"要不要读完"的判定阈值就是那两个常量**（`maxPostCloseReadBytes = 256 << 10`、`maxPostCloseReadTime = 50 * time.Millisecond`，见第二幕）：

> - **body 很小（几十 KB 以内的 API 响应）**：`defer resp.Body.Close()` 就够了，**不必**再 `io.ReadAll`。
> - **body 可能很大（文件、导出、批量接口）**：**必须读到 EOF**（或者用 `io.Copy(io.Discard, resp.Body)` 丢掉），否则连接不复用。
> - **无论哪种情况："必须 `Close`"这条永远成立。**
> - **更稳妥的工程写法**：不判断，统一 `io.Copy(io.Discard, resp.Body)` 再 `Close` —— 代价是多读一遍数据，收益是"永远不踩这个坑"。**读的是本地 socket 缓冲，不是网络**（数据本来就已经在流进内核缓冲区了）。

**还有两个可观测的细节。**

**① `Close()` 是"立刻返回"的，排空在后台做：**

```console
H) 时序：不读直接 Close，调用本身多久返回
   Close() 调用耗时 26µs（同步返回很快，排空在后台 goroutine 里做）
   120ms 后服务端 idle 连接 0 条（dribble 要 400ms 才发完，排空在 50ms 就被判失败）
```

**26 微秒返回** —— 所以"关 body"不会阻塞你的业务逻辑。**但也意味着"关闭成功"不等于"连接已归还"** —— 排空是异步的，120 ms 后那条连接还是没能回到池子（因为服务端还在慢慢发）。

**② 排空失败会怎样？** `maybeDrainBody` 返回 `false` → 标准库**直接把连接关掉**，不回池子。**这就是"排空失败"和"不复用"是同一件事的原因** —— 不是"留着但不可用"，是**干脆扔掉**。

**最后一条必须点明的边界**：**写法 F 说明"服务端说不复用就不复用"。** 这解释了为什么"读得再干净，某些响应还是每次新建连接" —— 看一眼响应头里的 `Connection: close`，以及服务端有没有开 HTTP/2（HTTP/2 是多路复用，连接复用语义完全不同）。

##### §2.4 三个连接池参数各挡什么

`Transport` 上和连接数量有关的字段有三个，**它们的语义极易混淆**：

| 字段 | 管什么 | 零值 | 典型设置 |
|---|---|---|---|
| `MaxIdleConns` | **跨所有主机**的空闲连接**总量** | **0 = 不限** | 100（`DefaultTransport` 的值） |
| `MaxIdleConnsPerHost` | **每个主机**的空闲连接上限 | **0 = 用常量 2** | 设成"你对单个下游的期望并发数" |
| `MaxConnsPerHost` | **每个主机**的在用 + 空闲**总连接上限** | 0 = 不限 | 设成"你愿意让单个下游承受的最大并发" |

实测（G 段，看"服务端仍处于 idle 的连接"到底留了几条）：

```console
G) MaxIdleConnsPerHost 默认 2：并发 5 条 /big（读完整）之后池里留几条
   MaxIdleConnsPerHost=0（=默认 2）   新建 TCP 连接 5 条，服务端仍处于 idle 的连接 2 条
   MaxIdleConnsPerHost=5          新建 TCP 连接 5 条，服务端仍处于 idle 的连接 5 条
```

**并发 5 条 → 建了 5 条连接 → 默认只留 2 条在池子里，另外 3 条被关掉。** 后果是：下一波同样的 5 并发，**有 3 条要重新建连**（TCP 三次握手 + TLS 握手）。

`MaxConnsPerHost` 的效果更激烈（它卡的是"同时在用"）：

```console
4) Transport.MaxConnsPerHost 把并发连接卡住
   MaxConnsPerHost=0（默认：不限）     6 个并发慢请求，总耗时 203ms，新建连接 6 条，峰值并发连接 6
   MaxConnsPerHost=2            6 个并发慢请求，总耗时 605ms，新建连接 2 条，峰值并发连接 2
```

**`MaxConnsPerHost = 2` 让同样的 6 个并发变了 3 倍慢（≈203 ms → ≈605 ms）**，代价换来的"收益"是**只开了 2 条连接**。

> 📌 **这就是本节最该记住的取舍（带阈值）**：
>
> - **`MaxIdleConnsPerHost` 太小（比如默认的 2）** → 你**不等待**，但**反复建连**。**当你的并发 > 2 且下游是同一台机器时，就该调大它**（设成"你对单个下游的常态并发数"）。
> - **`MaxConnsPerHost` 设得太小** → 你**不建多余连接**，但**请求要排队**（实测 3 倍变慢）。**它只在"保护下游"（防止自己的某个实例把下游打爆）时才设**，而且要配合限流和超时一起用，否则就会把自己的 QPS 一起卡死。
> - **一句话**：**`MaxIdleConnsPerHost` 管"复用得够不够"，`MaxConnsPerHost` 管"给下游的压力上限"。前者该调大，后者要谨慎。**

同时也要知道 **`MaxIdleConns` 与 `MaxIdleConnsPerHost` 是"与"的关系**：如果 `MaxIdleConns = 1`、`MaxIdleConnsPerHost = 10`、下游有 3 台机器，那么**全局只允许留 1 条空闲连接** —— 你调 `PerHost` 的收益会被 `MaxIdleConns` 吃掉。

##### §2.5 代理：本地地址会不会被 `http_proxy` 带走？

课 11 有个方法论坑：**沙箱/公司内网设了 `http_proxy`，`curl` 会把发往 `127.0.0.1` 的请求也走代理**，导致"服务明明起着却返回 502"。那一课用的对策是给 `curl` 加 `--noproxy '*'`。

**那 Go 自己的 `http.Client` 呢？** 实测：

```console
6) 环境变量里的代理会不会把 127.0.0.1 也带走？
   HTTP_PROXY   = http://127.0.0.1:60249
   HTTPS_PROXY  = http://127.0.0.1:60249
   http_proxy   = http://127.0.0.1:60249
   https_proxy  = http://127.0.0.1:60249
   ProxyFromEnvironment(本地地址) → <nil>, err=<nil>
   走默认 Transport 访问本地：成功，body="ok"（耗时 0s）
   Transport{Proxy: nil} 访问本地：成功，body="ok"（耗时 0s）
```

**四个代理环境变量都设着，但 `ProxyFromEnvironment(本地地址)` 返回 `nil`** —— 意思是"**这个地址不需要走代理**"。所以 `http.Client` **直接**就绕过了代理，**不需要任何额外设置**。

原因在 `httpproxy` 的源码里（**硬编码的两条规则**）：

```go
	if host == "localhost" {
		return false
	}
	nip, err := netip.ParseAddr(host)
	var ip net.IP
	if err == nil {
		ip = net.IP(nip.AsSlice())
		if ip.IsLoopback() {
			return false
		}
	}
```

> 源码原文，核查于 2026-09（`$GOROOT/src/vendor/golang.org/x/net/http/httpproxy/proxy.go`）

**`isLoopback()` 的那一判断，让所有 `127.0.0.0/8` 与 `::1` 自动豁免。** 这跟 `curl` 的行为**不一样**。

> 💡 **这一条的教学价值**：**同一个环境变量，两个工具的行为可以完全不同。** 遇到"本地服务明明起着却连不上"时，**先分清是谁在发请求** —— `curl` 要加 `--noproxy '*'`，`http.Client` 不用。**照着另一个工具的结论去改，可能白忙一场。**

##### §2.6 重试：三道显性闸门 + 一道最容易被忽略的

`net/http` 不替你重试，你得自己写。但"自己写重试"最容易写出事故 —— **重试的本质是"用一个请求换 N 个请求"，写错了就是攻击自己的下游**。三道闸门：

**闸门 1：只重试幂等方法。**

```console
1) GET /flaky（前两次 503，第三次 200）：带退避重试
   第 1 次 → 503，退避 81ms 后重试（累计 2ms）
   第 2 次 → 503，退避 185ms 后重试（累计 85ms）
   第 3 次 → 200，放弃重试（累计 272ms）
   最终 body = {"ok":true,"attempt":3}

2) 同样重试逻辑用在 POST 上：不重试（方法不幂等）
   第 1 次 → 503  retrying=false（累计 1ms）
   最终 body = {"error":"上游暂时不可用"} ← 一次就放弃了
```

**同一个 503，GET 打了 3 次，POST 打了 1 次。** 为什么 POST 不能重试？因为 **HTTP 是"请求发出去了但响应没收到"的不确定状态**——POST 可能已经成功了，只是响应丢了，你重试就会**下单两次**。

**"幂等"这个词的定义就用在这里**：

| 方法 | 幂等吗 | 能自动重试吗 |
|---|---|---|
| `GET` / `HEAD` / `OPTIONS` | ✅ | 能 |
| `PUT` / `DELETE` | ✅（**按 HTTP 规范**：重复执行结果相同） | 能，**但要小心**：很多"RESTful 实现"把 `PUT` 写成了"创建"、`DELETE` 写成了"扣减" |
| `POST` / `PATCH` | ❌ | **不能**（除非你自己有幂等键） |

**闸门 2：必须有尝试上限。**

```console
3) 一直 503：重试上限必须存在，否则就是放大器
   一共打了 4 次，退避序列：116ms → 167ms → 384ms，总耗时 672ms
```

**"一直失败"的情况下，一共只打了 4 次（1 + 3 次重试）就停了、672 ms 后返回错误。** 如果没有上限：**1 个用户请求 → 无限次上游请求**。上游本来就快挂了，你这等于**给它加了一个放大器**。

**闸门 3：退避 + 抖动。**

看上面那两条退避序列：`81ms → 185ms`（×2.3）和 `116ms → 167ms → 384ms`。**指数增长**（每次约 ×2），而且**每次都有一个随机增量**（抖动）。

> **为什么要抖动？** 假设 1000 个客户端同时被上游的 503 拒绝。如果没有抖动，它们会在**同一毫秒**一起重试 → 上游刚活过来又被打死 → **惊群（thundering herd）**。加了抖动之后，重试时间被打散在一个区间内。

**✅ 另外还有一道常被忽略的闸门 —— 在重试之前先看 `ctx`。** 这一点是本课在写示例代码时**真的踩到的**：第一版 `Do` 里，网络错误就直接进重试分支，结果**在 `ctx` 已经到点的情况下还傻乎乎地又打了 2 次**（虽然立刻失败）：

```console
5) /slow（服务端睡 800ms）：ctx 200ms vs Client.Timeout 2s，谁更早谁说了算
   尝试 3 次，耗时约 202ms，err=Get "http://127.0.0.1:51774/slow": context deadline exceeded
```

**"尝试 3 次"** —— ctx 200 ms 到点后，它又试了两次。修法是在重试之前插一句：

```go
if ctx.Err() != nil {
	return nil, attempt, err   // 已经取消了，别再打了
}
```

修完再跑，同一场景变成 **"尝试 1 次，耗时约 202ms"**。

> 🐞 **教训**：**重试循环里每一个"还继续吗"的判断，都必须包含 `ctx`。** 否则你的重试会变成一个"无视取消、自己跑完自己"的小循环 —— 而课 10 讲的"取消要沿着链路传下去"就在这里断掉了。

#### ④ 示例演示：一个"生产级"下游客户端封装

下面这份代码把前面六节全部落进一个可复用的封装里 —— **它在 go1.27.1 上真实跑通过（含 `go run -race` 全绿、`gofmt` / `go vet` 干净）**。

**核心结构（`Downstream`）**：

```go
// Downstream 是一个复用的下游客户端。★ 全进程一个实例，绝不每请求新建。
type Downstream struct {
	c          *http.Client
	maxAttempt int
	baseDelay  time.Duration
}

func NewDownstream() *Downstream {
	tr := &http.Transport{
		// 连接池：这里全部显式设，不依赖默认值
		MaxIdleConns:        100,              // 跨主机空闲连接总量（DefaultTransport 也是 100）
		MaxIdleConnsPerHost: 10,               // ★ 默认只有 2，并发一高就不够
		MaxConnsPerHost:     20,               // ★ 默认 0（不限）—— 要"给自己封顶"时设它
		IdleConnTimeout:     90 * time.Second, // 与 DefaultTransport 一致
		// 建连与 TLS 超时（DefaultTransport 里也是这两个值）
		DialContext:         (&net.Dialer{Timeout: 5 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
		TLSHandshakeTimeout: 10 * time.Second,
	}
	return &Downstream{
		// ★ 超时必须显式设：默认 Client 的 Timeout 是 0 = 永不超时
		c:          &http.Client{Timeout: 2 * time.Second, Transport: tr},
		maxAttempt: 3,
		baseDelay:  80 * time.Millisecond,
	}
}
```

**四道闸门全在这里（`Do` + `backoff` + `idempotent`）**：

```go
// idempotent 只有幂等方法才允许重试。★ 这是重试的第一道闸门
func idempotent(method string) bool {
	switch method {
	case http.MethodGet, http.MethodHead, http.MethodPut, http.MethodDelete, http.MethodOptions:
		return true
	}
	return false
}

// Resp 是封装后返回给业务的东西：body 已经读进内存了，调用方不用管 Close
type Resp struct {
	Status int
	Body   []byte
}

// Do 发一次请求，按需重试。返回 (Resp, 尝试次数, error)
func (d *Downstream) Do(ctx context.Context, method, url string, body io.Reader) (*Resp, int, error) {
	var lastErr error

	for attempt := 1; attempt <= d.maxAttempt; attempt++ {
		req, err := http.NewRequestWithContext(ctx, method, url, body)
		if err != nil {
			return nil, attempt, err
		}

		resp, err := d.c.Do(req)
		if err != nil {
			lastErr = err
			// ★ 重试之前必须先看 ctx：已经取消了就别再打了
			if ctx.Err() != nil {
				return nil, attempt, err
			}
			// 网络层错误（含超时）可以重试 —— 但必须满足幂等 + 还有次数
			if !idempotent(method) || attempt == d.maxAttempt {
				return nil, attempt, err
			}
			d.backoff(ctx, attempt)
			continue
		}

		// ★ 无论后续怎么处理，body 都必须关；小 body 顺便读干
		b, readErr := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
		closeErr := resp.Body.Close()
		if readErr != nil {
			return nil, attempt, fmt.Errorf("读 body: %w", readErr)
		}
		_ = closeErr

		// 5xx 才重试；4xx 是"你的错"，重试没意义
		if resp.StatusCode >= 500 && idempotent(method) && attempt < d.maxAttempt {
			lastErr = fmt.Errorf("上游返回 %d", resp.StatusCode)
			d.backoff(ctx, attempt)
			continue
		}

		return &Resp{Status: resp.StatusCode, Body: b}, attempt, nil
	}
	return nil, d.maxAttempt, lastErr
}

// backoff 指数退避 + 抖动，且必须能被 ctx 打断
func (d *Downstream) backoff(ctx context.Context, attempt int) {
	delay := d.baseDelay * time.Duration(1<<(attempt-1))
	delay += time.Duration(rand.Int63n(int64(d.baseDelay))) // 抖动，避免惊群
	select {
	case <-time.After(delay):
	case <-ctx.Done():
	}
}
```

> ⚠️ **注意 `Do` 每次都把 body 读进内存了（`io.ReadAll(io.LimitReader(..., 4<<20))`）** —— 这个封装适合"响应体不大"的场景（API 调用）。**如果下游会返回大文件，这个封装就不能用**，得把"body 交给调用方读+关"的职责还回去。**封装永远是有适用边界的** —— 这里的边界是"4 MiB 以内，并且超过 4 MiB 会被静默截断"（**这也是个坑，生产代码应该改成"超过就报错"**）。

<details>
<summary><b>📦 完整可运行源码（含演示服务端与 main，290 行）</b></summary>

```go
// package main —— 知识点 2 的完整示例：一个"生产级"下游客户端封装
//
//	超时 / 必读必关 body / 连接池参数 / 只在幂等请求上做有上限的退避重试
package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"math/rand"
	"net"
	"net/http"
	"sync"
	"sync/atomic"
	"time"
)

// ============ ① 下游服务（模拟库存 / 风控服务） ============

type server struct {
	mux       *http.ServeMux
	mu        sync.Mutex
	connState map[net.Conn]http.ConnState
	newConns  int64
	getHit    int64
	postHit   int64
}

func newServer() *server {
	s := &server{mux: http.NewServeMux(), connState: map[net.Conn]http.ConnState{}}

	// GET：前两次 503，第三次 200 —— 用来验证"幂等重试"
	s.mux.HandleFunc("/flaky", func(w http.ResponseWriter, r *http.Request) {
		n := atomic.AddInt64(&s.getHit, 1)
		if n <= 2 {
			w.WriteHeader(http.StatusServiceUnavailable)
			io.WriteString(w, `{"error":"上游暂时不可用"}`)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"ok":true,"attempt":%d}`, n)
	})

	// POST：永远 503 —— 用来验证"不幂等就不重试"
	s.mux.HandleFunc("/flaky-post", func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt64(&s.postHit, 1)
		w.WriteHeader(http.StatusServiceUnavailable)
		io.WriteString(w, `{"error":"上游暂时不可用"}`)
	})

	// 1 MiB 响应体 —— 用来验证"读完之后才能复用"
	s.mux.HandleFunc("/big", func(w http.ResponseWriter, r *http.Request) {
		w.Write(make([]byte, 1<<20))
	})

	// 慢响应 —— 用来验证客户端超时
	s.mux.HandleFunc("/slow", func(w http.ResponseWriter, r *http.Request) {
		select {
		case <-time.After(800 * time.Millisecond):
		case <-r.Context().Done():
			return
		}
		io.WriteString(w, "慢响应终于来了")
	})

	// 回显方法 —— 小请求，用来数连接
	s.mux.HandleFunc("/echo", func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		fmt.Fprintf(w, `{"method":"%s","len":%d}`, r.Method, len(b))
	})

	// 占住连接一小会儿 —— 让并发请求真的用上不同连接
	s.mux.HandleFunc("/hold", func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(100 * time.Millisecond)
		io.WriteString(w, "held")
	})

	return s
}

func (s *server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.mux.ServeHTTP(w, r)
}

func (s *server) ConnState(c net.Conn, st http.ConnState) {
	if st == http.StateNew {
		atomic.AddInt64(&s.newConns, 1)
	}
	s.mu.Lock()
	s.connState[c] = st
	s.mu.Unlock()
}

func (s *server) NewConns() int64 { return atomic.LoadInt64(&s.newConns) }

func (s *server) IdleConns() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	n := 0
	for _, st := range s.connState {
		if st == http.StateIdle {
			n++
		}
	}
	return n
}

// ============ ② 生产级客户端封装 ============
// （Downstream / NewDownstream / idempotent / Resp / Do / backoff 见上方正文，此处不再重复）
func (d *Downstream) Close() {
	if tr, ok := d.c.Transport.(*http.Transport); ok {
		tr.CloseIdleConnections()
	}
}

// ============ ③ 演示 ============

func main() {
	srv := newServer()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		panic(err)
	}
	hs := &http.Server{Handler: srv, ConnState: srv.ConnState}
	go hs.Serve(ln)
	defer hs.Close()

	base := "http://" + ln.Addr().String()
	d := NewDownstream()
	defer d.Close()

	ctx := context.Background()

	// 1) GET 幂等 → 会重试
	fmt.Println("1) GET /flaky（前两次 503，第三次 200）—— 幂等，允许重试")
	r, n, err := d.Do(ctx, http.MethodGet, base+"/flaky", nil)
	if err != nil {
		fmt.Printf("   err=%v\n", err)
	} else {
		fmt.Printf("   状态=%d body=%s 共尝试 %d 次\n", r.Status, r.Body, n)
	}

	// 2) POST 不幂等 → 不重试
	fmt.Println("\n2) POST /flaky-post（服务端永远 503）—— 不幂等，一次就放弃")
	r, n, err = d.Do(ctx, http.MethodPost, base+"/flaky-post", nil)
	if err != nil {
		fmt.Printf("   err=%v\n", err)
	} else {
		fmt.Printf("   状态=%d body=%s 共尝试 %d 次（服务端被打了几次：%d）\n",
			r.Status, r.Body, n, atomic.LoadInt64(&srv.postHit))
	}

	// 3) 连接复用基线：先清空池子，再连打 2 条小请求
	d.Close()
	time.Sleep(60 * time.Millisecond)
	before := srv.NewConns()
	for i := 0; i < 2; i++ {
		if _, _, err := d.Do(ctx, http.MethodGet, base+"/echo", nil); err != nil {
			fmt.Printf("   err=%v\n", err)
		}
	}
	fmt.Printf("\n3) 清空池子后连打 2 条 /echo：新建 TCP 连接 %d 条（第 2 条复用了第 1 条）\n",
		srv.NewConns()-before)

	// 4) 大 body 读完之后也复用
	before = srv.NewConns()
	for i := 0; i < 2; i++ {
		if _, _, err := d.Do(ctx, http.MethodGet, base+"/big", nil); err != nil {
			fmt.Printf("   err=%v\n", err)
		}
	}
	fmt.Printf("4) 连打 2 条 /big（1 MiB，读完并关闭）：新建 TCP 连接 %d 条\n", srv.NewConns()-before)

	// 5) 客户端超时：ctx 200ms 比 Client.Timeout 2s 更早
	fmt.Println("\n5) /slow（服务端睡 800ms）：ctx 200ms vs Client.Timeout 2s，谁更早谁说了算")
	tctx, cancel := context.WithTimeout(ctx, 200*time.Millisecond)
	defer cancel()
	t0 := time.Now()
	_, n, err = d.Do(tctx, http.MethodGet, base+"/slow", nil)
	fmt.Printf("   尝试 %d 次，耗时约 %v，err=%v\n", n, time.Since(t0).Round(time.Millisecond), err)
	fmt.Printf("   errors.Is(err, context.DeadlineExceeded)=%v\n", errors.Is(err, context.DeadlineExceeded))

	// 6) 池子的形状与清空
	fmt.Println("\n6) 并发 3 条 /hold（各占 100ms）—— 池子会长成什么样，以及怎么清空")
	d.Close()
	time.Sleep(60 * time.Millisecond)
	before = srv.NewConns()
	var wg sync.WaitGroup
	for i := 0; i < 3; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, _, _ = d.Do(ctx, http.MethodGet, base+"/hold", nil)
		}()
	}
	wg.Wait()
	fmt.Printf("   新建 TCP 连接 %d 条；请求做完后服务端 idle 连接 %d 条\n",
		srv.NewConns()-before, srv.IdleConns())
	d.Close()
	time.Sleep(100 * time.Millisecond)
	fmt.Printf("   CloseIdleConnections() 之后 idle 连接 %d 条\n", srv.IdleConns())
}
```

</details>

**真实输出**（本机 go1.27.1 逐字记录，连跑 3 次结果一致，仅随机端口变化）：

```console
1) GET /flaky（前两次 503，第三次 200）—— 幂等，允许重试
   状态=200 body={"ok":true,"attempt":3} 共尝试 3 次

2) POST /flaky-post（服务端永远 503）—— 不幂等，一次就放弃
   状态=503 body={"error":"上游暂时不可用"} 共尝试 1 次（服务端被打了几次：1）

3) 清空池子后连打 2 条 /echo：新建 TCP 连接 1 条（第 2 条复用了第 1 条）
4) 连打 2 条 /big（1 MiB，读完并关闭）：新建 TCP 连接 0 条

5) /slow（服务端睡 800ms）：ctx 200ms vs Client.Timeout 2s，谁更早谁说了算
   尝试 1 次，耗时约 202ms，err=Get "http://127.0.0.1:51920/slow": context deadline exceeded
   errors.Is(err, context.DeadlineExceeded)=true

6) 并发 3 条 /hold（各占 100ms）—— 池子会长成什么样，以及怎么清空
   新建 TCP 连接 3 条；请求做完后服务端 idle 连接 3 条
   CloseIdleConnections() 之后 idle 连接 0 条
```

**逐条对上前面讲过的原理：**

| 行 | 输出 | 对应哪一节 |
|---|---|---|
| 1 | `共尝试 3 次` | §2.6 闸门 1（幂等）+ 闸门 2（上限 3） |
| 2 | `共尝试 1 次（服务端被打了几次：1）` | §2.6 闸门 1 —— **POST 一次就放弃，服务端真的只被打了一次** |
| 3 | `新建 1 条`（2 条请求） | §2.3/§2.4 —— 复用生效 |
| 4 | `新建 0 条` | §2.3 写法 E —— **1 MiB 读完之后同样复用** |
| 5 | `尝试 1 次，约 202ms` | §2.2 + §2.6 第四道闸门（重试前看 ctx） |
| 6 | `新建 3 条 → idle 3 条 → 0 条` | §2.4 —— `CloseIdleConnections()` 清空池子（发布/切流量时用） |

> ⚠️ 第 6 行的 "idle 3 条" 需要解释一下：**并发 3 条请求 → 池子会长到 3 条连接**（因为 3 条请求同时在用），**用完之后这 3 条都会回流成 idle**。而 `MaxIdleConnsPerHost = 10` 在这里起了作用 —— **如果它是默认的 2，这里只会留 2 条**。

#### ⑤ 常见误区（知识点 2）

| # | 误区 | 真相 | 实测依据 |
|---|---|---|---|
| 1 | `http.Get` 有默认超时 | **没有**。`DefaultClient.Timeout = 0` = 永不超时 | 2 秒慢响应硬等 2 秒；`DefaultClient.Timeout = 0s` |
| 2 | `Client.Timeout` 只管到拿到响应头 | **连读 body 也一起管** | 头 1 ms 到手、body 读到 18 字节被掐断 |
| 3 | `Client.Timeout` 和 `ctx` 二选一 | **两个都设**：ctx 做主、`Timeout` 兜底；先到点的生效 | §2.2 表 |
| 4 | 每次调用都 `http.Get` / 新建 `Client` 是无所谓的 | 等价于**每次新建一个连接池** | 100 次请求：共用 Client → **1** 条连接；每次新建 → **100** 条 |
| 5 | "必须把 `resp.Body` 读到 EOF 才能复用连接" | **Go 1.27 起只对"大 body"成立**（> 256 KiB 或 > 50 ms） | A/B ✅ vs C/D ❌ |
| 6 | `resp.Body` 超过阈值不读也没事 | 会**直接关掉连接**，不复用 | D 例：128 KiB/400 ms → ❌ |
| 7 | 读完 `resp.Body` 就不用 `Close` | **必须 `Close`**（读完只是让它"可复用"） | 官方：*"It is the caller's responsibility to close Body."* |
| 8 | `Close()` 会把连接立刻还回池子 | **排空是异步的**，`Close()` 26 µs 就返回 | 120 ms 后服务端 idle 仍是 0 |
| 9 | 读完了就一定能复用 | **服务端说 `Connection: close` 就不行** | F 例 → ❌ |
| 10 | `MaxIdleConnsPerHost = 0` 表示不限 | **0 表示"用常量 2"**（与 `MaxIdleConns` 的 0 语义相反） | 字段注释 + `DefaultMaxIdleConnsPerHost = 2` |
| 11 | `MaxIdleConnsPerHost` 默认够用 | 默认 **2**；并发 5 条 → 只留 2 条 | G 例：2 条 vs 设 5 时 5 条 |
| 12 | `MaxConnsPerHost` 设小一点只是"慢一点" | 实测**慢 3 倍**（≈203 ms → ≈605 ms） | 4) 例 |
| 13 | 调大 `MaxIdleConnsPerHost` 就一定有效 | 还受全局 `MaxIdleConns` 限制（"与"关系） | §2.4 末尾 |
| 14 | `http.Client` 访问 localhost 会被 `http_proxy` 带走 | **不会**，源码硬编码豁免 `localhost` 与回环 IP | `ProxyFromEnvironment(本地) → <nil>` |
| 15 | `curl` 的代理坑和 Go 一样处理 | **不一样**：`curl` 要 `--noproxy '*'`，Go 不用 | 课 11 + 本课 §2.5 |
| 16 | `net/http` 会自动重试失败的请求 | **基本不会**（只有极少数透明重试）；重试是你自己的责任 | §2.6 |
| 17 | 所有失败都可以重试 | **只有幂等方法能自动重试** | GET 3 次 vs POST 1 次 |
| 18 | 重试不需要上限 | 没有上限就是**放大器**：1 个用户请求 → N 个上游请求 | 一直 503 → 只打 4 次就停 |
| 19 | 退避不需要抖动 | 没抖动 → **惊群**（所有人同一毫秒重试） | 退避序列里每次都有随机增量 |
| 20 | 重试循环不用管 `ctx` | **必须管**，否则会"无视取消自己跑完" | 本课第一版实测"尝试 3 次"，加 `ctx.Err()` 后变 1 次 |
| 21 | 封装一个 `Do` 就一劳永逸 | 封装有边界：本课示例把 body 读进内存，**大文件场景不能用** | 源码里的 `io.LimitReader(..., 4<<20)` |
| 22 | `4xx` 也该重试 | **不该**——那是"你的请求有问题"，重试只会重复犯错 | 示例里只对 `>= 500` 重试 |

#### ⑥ 一句话记住

> **`http.Client` 是"进程级的连接池句柄"：复用、显式设超时、`resp.Body` 必关（大于 256 KiB 或 50 ms 读不完的还要读完）；`Transport` 的 `0` 值有两种含义（`MaxIdleConns` 是不限、`MaxIdleConnsPerHost` 是"用常量 2"）；重试只在幂等请求上做，且必须同时具备"上限 + 退避抖动 + 先看 ctx"三个条件。**

#### 📚 官方文档

- 包文档：`go doc net/http` ／ [pkg.go.dev/net/http](https://pkg.go.dev/net/http)
- `Client` / `Client.Timeout` / `Client.Do`：`go doc net/http.Client`
- `Transport`（连接池参数的真正位置）：`go doc net/http.Transport`
- `DefaultTransport` 与 `DefaultMaxIdleConnsPerHost`：`go doc net/http.DefaultTransport`
- `Response.Body`（**Go 1.27 新增了"异步排空"那段，务必看最新版**）：`go doc net/http.Response`
- 连接状态观测：`go doc net/http/httptrace`、`go doc net/http.Server.ConnState`
- 代理规则源码：`$GOROOT/src/vendor/golang.org/x/net/http/httpproxy/proxy.go`

---

### 知识点 3：时间与定时器

#### ① 一句话定义

**`time.Time` 里装着两块表——一块"墙上时钟"（用来告诉别人现在是几点）和一块"单调时钟"（用来量时间过了多久）；定时器（`Timer` / `Ticker` / `After` / `AfterFunc`）是**有寿命、会被 GC 回收、需要按类型分别对待的对象**；而时间字符串的格式化与解析由一串"魔数布局串"（`2006-01-02 15:04:05`）驱动，写错了既不报错也不生效。**

#### ② 直觉建立（类比 + 失效边界）

**类比：两块表 + 一只秒表。**

- **墙上时钟 = 墙上的挂钟。** 它告诉你"现在是下午三点"，但**它可以被对时（NTP）、可以被手动改、可以在夏令时切换时跳一小时**。你用它回答"几点"这个问题。
- **单调时钟 = 你手里那只秒表。** 你按下开始，它只会单调地往前走，**没人能把它往回拨**。你用它回答"过了多久"这个问题。
- **`time.Now()` 返回的那个 `Time`，同时带了两块表的读数。** 这解释了"为什么改系统时间不会让 `time.Since` 变成负数"这类现象。
- **定时器 = 一只带闹钟的秒表。** 你设定"多久之后响"，然后就有一根 channel 等着它。**但"要不要按停"这件事在 Go 里有过三次规则变化**（见 §3.7）。

**这个类比在哪里失效（三条）：**

1. **"两块表"不是两个独立字段，而是打包在同一份数据里的。** 一旦你做了任何"只对墙上时钟有意义"的操作（`Round` / `Truncate` / `AddDate` / `In` / `UTC` / `Local`），**单调读就被丢掉了**，这个 `Time` 就退化成"只有挂钟读数" —— **它还能告诉你几点，但不能再用来精确量时长**。类比里"两块表互相独立"会让人以为丢了挂钟不影响秒表，实际**恰相反**。
2. **秒表在"机器睡眠"时会停。** 官方文档明确写着：*"On some systems the monotonic clock will stop if the computer goes to sleep."* —— 所以**笔记本合盖再打开之后，`time.Since` 未必反映真实经过的时间**。这是"单调"的代价：它以"保证不倒流"换掉了"保证真实"。
3. **定时器的"响"是通过 channel 送出来的**，所以它会遇到课 8 讲过的全部 channel 语义 —— **没人接的值会被丢掉（ticker）/ 直接阻塞（timer 的同步 channel）**，而不是"排着队等你来取"。这一点是"闹钟"这个类比**完全给不了**的直觉。

#### ③ 核心原理

##### §3.1 `time.Time` 里到底有什么

```go
// In addition to the required “wall clock” reading, a Time may contain an optional
// reading of the current process's monotonic clock, to provide additional precision
// for comparison or subtraction.
// See the “Monotonic Clocks” section in the package documentation for details.
//
// Note that the Go == operator compares not just the time instant but also the
// Location and the monotonic clock reading. Therefore, Time values should not
// be used as map or database keys without first guaranteeing that the
// identical Location has been set for all values, which can be achieved
// through use of the UTC or Local method, and that the monotonic clock reading
// has been stripped by setting t = t.Round(0). In general, prefer t.Equal(u)
// to t == u, since t.Equal uses the most accurate comparison available and
// correctly handles the case when only one of its arguments has a monotonic
// clock reading.
type Time struct {
```

> 源码原文，核查于 2026-09（`$GOROOT/src/time/time.go`）

**这段注释里有四条硬信息**：

1. 单调读是**可选的**（`optional`）—— 不是每个 `Time` 都有。
2. **`==` 比三样东西**：时刻 + `Location` + 单调读。
3. **官方建议：一般用 `t.Equal(u)` 而不是 `t == u`。**
4. 如果非要用 `Time` 当 map key，**必须先 `t = t.Round(0)` 剥掉单调读**。

实测第一条（`String()` 会把单调读写出来，前缀是 `m=`）：

```console
1) time.Now() 身上带着单调读，t.String() 会把它显示出来
   time.Now()        = 2026-09-13 13:49:33.495801 +0800 CST m=+0.000279585
   t.Round(0)        = 2026-09-13 13:49:33.495801 +0800 CST
   t == t.Round(0)   → false   ← == 连单调读一起比
   t.Equal(t.Round(0)) → true ← Equal 只比“时刻”
```

**`m=+0.000279585` 就是单调读** —— 它表示"进程启动后过了 279 微秒"（**注意它是相对进程启动的，不是相对某个纪元**，所以它没有跨进程意义）。`Round(0)` 之后这个 `m=` 就没了，于是 `==` 变成 `false`，但 `Equal` 仍然是 `true`。

**"拿 `Time` 当 map key"的实测 —— 几乎永远取不回来：**

```console
2) 拿 time.Time 当 map key：几乎永远取不回来
   用同一个 t 取        → ok=true
   用 time.Now() 重取    → ok=false
   用 t.Round(0) 取      → ok=false
   （所以官方给的标准做法是：当 key 前先 t = t.Round(0)，并用 t.Equal 比较）
```

**注意第二行和第三行**：用 `t.Round(0)` 也取不回来 —— 因为 map 里存的那个 key **带着单调读**。**必须"存的时候也 `Round(0)`"才行。** 这是"官方建议"背后真正的原因：**要么两边都不带单调读，要么就别用 `==` 语义的容器。**

##### §3.2 哪些操作会丢单调读（官方列表 + 实测）

官方 **"Monotonic Clocks"** 那一节把规则写得很清楚：

> *"If Time t has a monotonic clock reading, `t.Add` adds the same duration to both the wall clock and monotonic clock readings to compute the result. Because `t.AddDate(y, m, d)`, `t.Round(d)`, and `t.Truncate(d)` are wall time computations, they always strip any monotonic clock reading from their results. Because `t.In`, `t.Local`, and `t.UTC` are used for their effect on the interpretation of the wall time, they also strip any monotonic clock reading from their results. **The canonical way to strip a monotonic clock reading is to use `t = t.Round(0)`.**"*
>
> *"Because the monotonic clock reading has no meaning outside the current process, the serialized forms generated by `t.GobEncode`, `t.MarshalBinary`, `t.MarshalJSON`, and `t.MarshalText` omit the monotonic clock reading... Similarly, the constructors `time.Date`, `time.Parse`, `time.ParseInLocation`, and `time.Unix`, as well as the unmarshalers ... **always create times with no monotonic clock reading.**"*
>
> （核查于 2026-09，`$GOROOT/src/time/time.go` 包文档）

实测逐条验证：

```console
3) 哪些操作会把单调读丢掉（官方包文档列过）
   Round(0)               → 还有单调读吗：false
   Round(time.Second)     → 还有单调读吗：false
   Truncate(time.Second)  → 还有单调读吗：false
   AddDate(0,0,0)         → 还有单调读吗：false
   UTC()                  → 还有单调读吗：false
   Local()                → 还有单调读吗：false
   In(time.UTC)           → 还有单调读吗：false
   Add(time.Hour)         → 还有单调读吗：true
   JSON 往返                → 还有单调读吗：false
```

**只有 `Add` 保留**，其余全部丢失 —— 和文档一字不差。**顺便记住：JSON 往返也会丢**（因为 `MarshalJSON` 会省略单调读）—— 所以**任何"存了再取出来"的时间都不带单调读**。

**丢了单调读的第一个后果：精度被"截断"了。**

```console
4) 丢了单调读的后果之一：精度被“截断”到布局粒度
   原始       = 13:49:33.496335000
   截断到秒   = 13:49:33.000000000
   t2.Sub(截断值) = 496.335ms（正的，等于小数秒）
   截断值.Sub(t2) = -496.335ms（负的，同一个差值）
```

**第二个后果（真正会出事故的那个）：把"截断过的时间"当计时起点，会凭空多算最多一个截断粒度。**

```console
5) 后果之二：把「截断过的时间」当计时起点，会凭空多算最多 1 秒
   正常计时 time.Since(start)                 = 251ms
   踩坑计时 time.Since(start.Truncate(1s))     = 747ms ← 多算了 start 的小数秒
   多算的部分 = 496ms（本该为 0）
```

**同一段 250 ms 的代码，一个报 251 ms，一个报 747 ms。** 因为 `start.Truncate(1s)` 把起点往前拉到了"这一秒的零点"，`Since` 算的是"从那个零点到现在"，**凭空多算了 `start` 在那个秒内已经走过的小数秒**。

本课的完整示例里把这个现场又跑了一遍，**规律完全一样**（`Truncate(1s)` 的粒度是 1 秒，所以最多多算 1 秒）：

```console
④ 单调时钟：同一段 250ms 的睡眠，两种写法
   time.Since(start)                = 252.025459ms
   time.Since(start.Truncate(1s))    = 1.117634s ← 凭空多算了 start 的小数秒
```

> 🐞 **这就是"漏了单调读"最典型的翻车方式**：某个中间层（日志、缓存、序列化、`In(loc)` 转时区、`Truncate` 打点）顺手把 `Time` 处理了一下，单调读没了，**上层还在拿它算耗时** → 耗时统计开始随机偏移，最坏偏一个截断粒度。**排查这类问题极其痛苦，因为代码逻辑看起来完全正确。**
>
> **防御手段只有一个**：**"开始时刻"这个变量，从 `Now()` 出来到 `Since()` 用掉，中间不要让任何函数碰它。** 尤其不要传进"格式化 / 转时区 / 截断"的函数。

**阈值就在这里**：**你多算的量 = 截断粒度的一半到全量**（`Truncate(1s)` → 0~1 s；`Truncate(1ms)` → 0~1 ms）。所以 **"打点粒度"就是"误差上界"** —— 用 `Round(0)` 剥单调读是唯一无损的做法。

##### §3.3 `Since` 与 `Until`：同一件事的两种写法，但内部走了快车道

```go
// Since returns the time elapsed since t.
// It is shorthand for time.Now().Sub(t).
func Since(t Time) Duration {
	if t.wall&hasMonotonic != 0 && !runtimeIsBubbled() {
		// Common case optimization: if t has monotonic time, then Sub will use only it.
		return subMono(runtimeNano()-startNano, t.ext)
	}
	return Now().Sub(t)
}
```

> 源码原文，核查于 2026-09（`$GOROOT/src/time/time.go`）

**它确实只是"简写"（文档原话 `shorthand for time.Now().Sub(t)`），但源码里有一条快车道**：当 `t` 带单调读时，直接 `subMono(runtimeNano()-startNano, t.ext)` —— **省掉了构造一个 `Now()` 的开销**（不用读墙上时钟、不用拼 `Time` 结构体）。

实测两者数值等价：

```console
6) time.Since 与 time.Now().Sub 等价，但内部走的是快车道
   time.Since(start)    = 251.085ms
   time.Now().Sub(start)= 251.089ms
```

**那么"该用哪个"就很明确了**：

> **一律用 `time.Since(start)` 和 `time.Until(deadline)`。** 它们更短、更快、意图更清楚，而且**在 `t` 带单调读时还额外享受一个优化**。
>
> ⚠️ 但注意：**"等价"的成立条件是有单调读**。如果 `start` 已经被处理过（丢了单调读），两者**仍然等价**（都退化成墙上时钟相减），**但都不再可靠** —— 因为墙钟可能被调过。**所以真正要守的纪律是"别弄丢单调读"，不是"选哪个函数"。**

##### §3.4 `==`、`Equal`、`Location`：为什么同一个时刻会"不相等"

```console
7) 同一个时刻、不同 Location：== 不等，Equal 相等
   t（本地）      = 2026-09-13 13:49:33 +0800 CST
   转成固定 +8 区  = 2026-09-13 13:49:33 +0800 CST
   utc == loc     → false
   utc.Equal(loc) → true
   utc.Sub(loc)   → 0s
```

**两行打印出来一模一样，`==` 却是 `false`。** 因为 `Location` 是**指针**，`time.FixedZone("CST", 8*3600)` 每次调用都返回一个新 `*Location`（不像 `time.UTC` / `time.Local` 是包级单例）。三条口径：

| 比较方式 | 比什么 | 什么时候用 |
|---|---|---|
| `==` | 时刻 + `Location` 指针 + 单调读 | **几乎永远不要用** |
| `.Equal(u)` | **只比时刻**（fallback 到挂钟） | **比较两个时间点**（默认选它） |
| `.Sub(u)` / `.Compare(u)` | 时刻差 / 三态比较 | 算差值、排序 |

> 📌 **一句话**：**`==` 是"结构体相等"，`Equal` 是"时刻相等"。你几乎永远想要后者。**

##### §3.5 `Ticker`：滴答、丢 tick、Stop、Reset

`NewTicker` 的文档里有一句话，是理解 ticker 全部行为的关键：

> ```go
> // NewTicker returns a new [Ticker] containing a channel that will send
> // the current time on the channel after each tick. The period of the
> // ticks is specified by the duration argument. The ticker will adjust
> // the time interval or drop ticks to make up for slow receivers.
> // The duration d must be greater than zero; if not, NewTicker will
> // panic.
> ```
> 源码原文，核查于 2026-09（`$GOROOT/src/time/tick.go`）

**"adjust the time interval or drop ticks to make up for slow receivers"** —— ticker 面对"接收者跟不上"时有两个选择：**拉长间隔，或者直接丢 tick**。它**绝不会排队**。实测：

```console
5) 慢接收者：Ticker 会「丢 tick」而不是排队
   5ms 的 ticker 放着 120ms 不读，队列里只积压了 1 个（预期应约 24 个）
   → 官方原文：ticker will adjust the time interval or drop ticks to make up for slow receivers
```

**120 ms 不读、5 ms 周期 → 理论上该有 24 个 tick，实际只积压了 1 个。** 这是**设计**，不是丢数据：

> 💡 **ticker 的语义是"到点了该干活了"，不是"每一次滴答都是一个必须处理的事件"。** 所以它丢 tick 是对的 —— 否则一个卡住的消费者会让内存无限增长。
>
> ⚠️ **反过来说：任何"我必须知道错过了几次"的需求，都不能用 `Ticker`。** 这种情况要用 `Timer` + 自己算下一次的绝对时间。

**正常走字与 `Stop`：**

```console
2) Ticker 正常走字 + Stop 之后不再有 tick
   150ms / 20ms → 收到 7 个 tick（预期约 7 个）
   Stop() 之后再等 100ms → 又收到 0 个 tick
   从已 Stop 的 Ticker.C 接收：阻塞住了 ← Stop 不关 channel（这是规范行为）
```

**`Stop()` 之后 `Ticker.C` 不关闭，从它接收会永久阻塞。** 这是**规范**，`NewTicker` 的文档写着：

> *"Stop does not close the channel, to permit calling `Ticker.Reset`, and to prevent a concurrent goroutine reading from the channel from seeing an erroneous "tick"."*
> （核查于 2026-09）

**两个理由**：① 关了就没法 `Reset` 复用；② 关了会让**正在读的 goroutine 收到一个假的"滴答"**（它会读到零值）。

> 🐞 **所以"用 `for range t.C` 读 ticker"这个写法，永远等不到循环退出。** 要退出必须靠别的手段 —— 通常是 `select` 同时看 `ctx.Done()` / `done` channel。本课示例里的 `RunPeriodic` 就是标准写法：

```go
t := time.NewTicker(period)
defer t.Stop() // ★ 无论怎么返回都要 Stop

for {
	select {
	case <-ctx.Done():
		return runs
	case tick := <-t.C:
		runs++
		job(runs, time.Since(start))
	}
}
```

**`Ticker.Reset`（Go 1.15 起）可以换周期：**

```console
6) Ticker.Reset 换周期
   Reset 到 10ms 后 120ms 内收到 12 个 tick（若还是 100ms 只会有 1 个）
```

**12 个 vs 1 个** —— `Reset` 真的生效了。注意 `Ticker` **没有 `Stop` 后再 `Start`**，只有 `Reset`。

**`Ticker` 还有两个使用纪律：**

1. **`NewTicker(0)` / 负数会 panic**（文档：*"if not, NewTicker will panic"*）。而 `time.Tick(d)` 对 `d <= 0` **返回 `nil`**（不 panic）—— 从 `nil` channel 接收会永久阻塞：
   ```go
   // Tick is a convenience wrapper for [NewTicker] providing access to the ticking
   // channel only. Unlike NewTicker, Tick will return nil if d <= 0.
   ```
   **这是"静默失败"的典型**：`time.Tick(0)` 不报错、不 panic，就是一个永远不响的 ticker。
2. **`Ticker` 的 drift 是累积的**（因为它是"每次 tick 之后重新计时"）。要做"整点对齐"的任务，应该用 `time.NewTimer` + 自己算到下一个整点的 `Until`。

##### §3.6 `Timer`：`Stop` / `Reset` 的返回值，以及 Go 1.23 起"不用排空"

**`Timer.Stop()` 的返回值语义**（文档原文）：

> *"Stop prevents the [Timer] from firing. It returns true if the call stops the timer, **false if the timer has already expired or been stopped**."*
> （核查于 2026-09）

实测逐个场景：

```console
3) Timer.Stop 的返回值与「Stop 之后读 t.C 会怎样」
   还没到期就 Stop() → 返回 true
   已经 Stop 过再 Stop() → 返回 false
   Stop 返回 true 之后读 t.C → 一直阻塞（Go 1.23 起的保证：不会读到陈旧值）
   已到期之后再 Stop() → 返回 true（false = 没拦住）
   此时 channel 里有没有值：没有
```

**把这几行放在一起看，规则才完整 —— 而且它跟"老版本文档"说的**不一样**：**

| 情形 | `Stop()` 返回 |
|---|---|
| 还没到期 | `true` |
| **已到期，但值从未被接收** | **`true`** ← ⚠️ 不是 `false` |
| 已到期，并且值已经被接收过 | `false` |
| 已经被 `Stop` 过 | `false` |

**所以 `Stop() == false` 的判据是「这个值有没有被接收过 / 这个定时器有没有被停过」，不是「有没有到期」。** 老版本文档只写 *"false if the timer has already **expired** or been stopped"* —— **在 Go 1.23 之后这句话是不精确的**：`已到期` 本身并不让 `Stop` 返回 `false`，还得看值有没有被接收。

**为了让这个结论有一份干净的证据，本课另建了一个探针 `p18_timerstop`，把 8 种情形一次测全**（为什么"另建"：`p12_timer` 上面那行"已到期之后再 `Stop()` → 返回 true"后面跟的括号文案 `（false = 没拦住）`，是**按老语义写的**；实测值是 `true` —— 与其在别人的证据里改字，不如另起一个探针把它测清楚）：

```console
$ go run ./p18_timerstop（Timer.Stop 返回值语义：Go 1.23 起「已到期但未接收」仍返回 true）
A) chan-based timer（NewTimer）：5 种情形下 Stop() 返回什么
   ----------------------------------------------
   ① 还没到期就 Stop()                                   → true
   ② 已经 Stop 过再 Stop()                              → false
   ③ 已到期、值从未被接收 → Stop()                            → true
      ↳ Stop() 之后从 t.C 读不到值
   ④ 已到期、值已被接收 → Stop()                             → false
   ⑤ 已到期、值未接收，Reset(1h)                             → true
   ⑥ Reset 之后再 Stop()                               → true

B) func-based timer（AfterFunc）：3 种情形
   ----------------------------------------------
   ① 还没到期就 Stop()                                   → true
   ② 已到期、回调已跑（fired=1）→ Stop()                      → false
   ③ 立刻 Stop() 拦回调                                  → true（回调被拦住了吗：true）

C) AfterFunc 的 Timer.C 与 chan-based 的差别
   AfterFunc(...).C == nil ？true
   NewTimer(...).C  == nil ？false

D) 结论（只写实测到的）
   chan-based（NewTimer）：
     · 值从未被接收 → Stop() 返回 true（**已到期也不例外**，这是 Go 1.23 起的行为）
     · 已经被 Stop 过 / 值已被接收 → Stop() 返回 false
   func-based（AfterFunc）：
     · 回调已经跑过 → Stop() 返回 false（这一格才是文档里说的「没拦住」）
```

> 💡 **A 组第 ⑤、⑥ 行顺带纠正了 `Reset` 的同一处误读**：`Reset` 的 `true/false` **也是看"值有没有被接收"**，不是看"有没有到期" —— 值没被接收时，"已到期"的定时器 `Reset` 仍然返回 `true`。而 `p12_timer` 的 4) 里那个"已到期后 `Reset` → `false`"，是因为**它前面已经 `<-t5.C` 把值收走了**。

**第 3 行是 Go 1.23 改变行为的地方** —— `Timer.Stop` 的文档：

> *"For a chan-based timer created with `NewTimer(d)`, **as of Go 1.23, any receive from `t.C` after `Stop` has returned is guaranteed to block rather than receive a stale time value from before the Stop**; if the program has not received from `t.C` already and the timer is running, `Stop` is guaranteed to return `true`. **Before Go 1.23, the only safe way to use `Stop` was insert an extra `<-t.C` if `Stop` returned false to drain a potential stale value.**"*
> （核查于 2026-09）

**这段注释就是本节最该背下来的一段**：**老教材里那句"`Stop` 返回 `false` 就要补一句 `<-t.C` 排空" —— 从 Go 1.23 起不需要了。** 现在的保证是"`Stop` 返回之后从 `t.C` 接收一定阻塞"，所以**没有任何陈旧值可以读到**。

完整的"陈旧值"验证：

```console
2) Stop 之后还能不能读到陈旧值
   到期后从未接收过，此时 Stop() → true
   Stop 之后再接收 → 永久阻塞 ← 值被 Stop 拦下，不会读到陈旧值
   到期后先接收（读到 13:49:35.393），再 Stop() → false（false = 已经晚了）
```

**"永久阻塞"就是那条保证的具体表现** —— 值被拦下了。对照：如果**先接收再 `Stop`**，`Stop` 返回 `false`（已经晚了）。

**`Timer.Reset()` 的返回值语义**（与 `Stop` 相反，很容易记反）：

```console
4) Timer.Reset 的返回值
   活跃状态 Reset(50ms) → 返回 true（true = 原本还活着）
   已到期后 Reset(50ms) → 返回 false（false = 原本已经死了）
```

| 方法 | 返回 `true` 的含义 | 返回 `false` 的含义 |
|---|---|---|
| `Timer.Stop()` | 这次调用**拦下了**一个"值还没被取走"的定时器（**已到期但只要没被接收，也算拦下**） | 值**已经被接收过**，或者它**已经被 `Stop` 过** |
| `Timer.Reset(d)` | 调用前它的值**还没被接收、也没被停过**（于是被重新排程） | 调用前它**已经死透了**（值被接收过 / 被 `Stop` 过） |

> ⚠️ **这两个返回值的方向是相反的**，是本节最容易记错的一处。**口诀：`Stop` 返回"我停成功了吗"，`Reset` 返回"它原本还活着吗"。**

`Timer.Reset` 的文档里还有一句和 `Stop` 对称的保证：

> *"… `Reset` should be invoked on stopped or expired timers with drained channels… As of Go 1.23, any receive from `t.C` after `Reset` has returned is guaranteed to block rather than receive a stale time value from before the `Reset`."*（核查于 2026-09）

**所以老写法里的"`Reset` 前先排空"在 Go 1.23 起也可以省掉了。**

##### §3.7 到底要不要 `Stop`？——三种构造的版本变化，以及一处"文档与实测不一致"

这是本课**第二个推翻老教材**的地方，也是**唯一一处"实测结论与官方说法不完全一致"**的地方。所以要格外小心地拆。

**先看官方怎么说的**（`NewTimer` 文档，核查于 2026-09）：

> *"Before Go 1.23, the garbage collector did not recover timers that had not yet expired or been stopped, so code often immediately deferred `t.Stop` after calling `NewTimer`, to make the timer recoverable when it was no longer needed. **As of Go 1.23, the garbage collector can recover unreferenced timers, even if they haven't expired or been stopped. The `Stop` method is no longer necessary to help the garbage collector.**"*

`Ticker` 和 `Tick` 的文档里也各有一份同样的话（`Tick` 那段还额外提到 *"Before Go 1.23, this documentation warned that the underlying Ticker would never be recovered by the garbage collector"*）。

**"老教材说必须 `Stop` 否则泄漏"这句 —— 从 Go 1.23 起已经过时。** 但实测发现**它有一个例外**：

```console
7) 不 Stop 的 Ticker/Timer 会不会泄漏？Go 1.23 起 GC 能回收未 Stop 的
   基线堆 = 0.24 MB
   300000 个未 Stop 的 Ticker  之后 = 0.24 MB（增量 0.00 MB）
   300000 个未 Stop 的 Timer   之后 = 0.24 MB（增量 0.01 MB）
   300000 个未 Stop 的 AfterFunc 之后 = 37.34 MB（增量 37.11 MB）
   goroutine 数：1 → 1（定时器不需要一个 goroutine 一个）
```

按构造类型分别测（每次新建 30 万个、前后各强制 GC 三次）看得更清楚：

```console
   NewTimer(1h) 未 Stop、不引用                  堆   0.25 →   0.25 MB（Δ  +0.00）  对象 Δ +15
   NewTicker(1h) 未 Stop、不引用                 堆   0.25 →   0.25 MB（Δ  +0.00）  对象 Δ +6
   After(1h) 未接收                            堆   0.25 →   0.25 MB（Δ  +0.00）  对象 Δ +5
   AfterFunc(1h, f) 未 Stop、不引用              堆   0.25 →  37.56 MB（Δ +37.31）  对象 Δ +300020
   AfterFunc(1h, f) 立刻 Stop                 堆  37.56 →  37.56 MB（Δ  +0.00）  对象 Δ +2

   → NewTimer / NewTicker / After：未 Stop 也能被 GC 回收（Δ ≈ 0）
   → AfterFunc：未 Stop 时 300000 个对应 300000 个存活对象，GC 三次不回收
     （每个约 123 B；官方那句「Stop 不再是为了让 GC 回收」在这里不成立）
   ⏳ 机制未查清（runtime.timer 的 isChan 分支只给 channel 定时器用 seq 校验，
      timers.heap 是强引用）——本课按实测结论写，不按机制推测。
```

**结论表（本课最终口径）：**

| 构造 | 官方承诺"未 Stop 也能被 GC 回收" | 实测 | 要不要 `Stop` |
|---|---|---|---|
| `time.NewTimer(d)` | ✅ | Δ ≈ 0.00 MB（对象 +15） | **不必为 GC 而 Stop** |
| `time.NewTicker(d)` | ✅ | Δ ≈ 0.00 MB（对象 +6） | **不必为 GC 而 Stop** |
| `time.After(d)` | ✅ | Δ ≈ 0.00 MB（对象 +5） | 拿不到 `*Timer`，**没法 Stop** |
| `time.AfterFunc(d, f)` | ✅（文档未区分） | **❌ Δ +37 MB / 30 万个对象** | **必须 `Stop`**（如果要取消） |

> ⏳ **机制未查清，本课如实标注**：我在 `runtime/time.go` 里看到了 `timers.heap` 是强引用、也看到了 `newTimer` 对"带 channel 的定时器"做的 `dataqsiz == 0` 校验，**但没找到"为什么 `AfterFunc` 的定时器不能被回收"的确切那一行**。
>
> **本课的处理方式**：把**稳定可复现的实测结论**写出来，**把机制留白**。这是本仓库的纪律 —— 课 11 那条 `jsonv2` 的翻车就是因为"用推理代替了核查"。

**顺便：`AfterFunc` 的 `Stop` 与它的 `C` 字段：**

```console
8) AfterFunc 的 Stop
   200ms 动作，立刻 Stop() → true
   等 300ms 后 fired = false（被 Stop 拦住了）
   AfterFunc 返回的 Timer，其 C 字段 = <nil>（官方：is not used and will be nil）
```

**`AfterFunc` 返回的 `Timer` 的 `C` 字段是 `nil`** —— 这一点值得单独记，因为**对 `nil` channel 做 `select` / 接收会永久阻塞**，很容易写出"永远不响的超时"：

```go
// AfterFunc 的文档原文：
// AfterFunc waits for the duration to elapse and then calls f
// in its own goroutine. It returns a [Timer] that can
// be used to cancel the call using its Stop method.
// The returned Timer's C field is not used and will be nil.
func AfterFunc(d Duration, f func()) *Timer
```

**还有一个必须讲清的"文档与实测不一致"**（本课最需要小心处理的一条）：**`time.NewTimer().C` 的 `cap()` 到底是多少？**

```console
1) timer 的 channel 容量：源码字面 vs 实测
   裸的 make(chan time.Time, 1)          → cap = 1
   time.NewTimer(time.Hour).C            → cap = 0  len = 0
   time.NewTicker(time.Hour).C           → cap = 0  len = 0
   time.After(time.Hour)                 → cap = 0  len = 0
   reflect.ValueOf(t.C).Cap()            → 0（排除 %-verbs 误差）
   unsafe 读 Timer 首字（= C 字段）        → 0x50fc454c070
   %p 打印 t.C                          → 0x50fc454c070（与上一行一致 → 不是打印误差）

   对照证据：
   ·官方文档（time.NewTimer）：Before Go 1.23, the channel associated with a Timer was
     asynchronous (buffered, capacity 1) … As of Go 1.23, the channel is synchronous
     (unbuffered, capacity 0), eliminating the possibility of those stale values.
   ·官方测试 time/tick_test.go:400 断言 len(C), cap(C) = 0, 0
   ·源码 time/sleep.go:111 字面是 make(chan Time, 1)，再交给 runtime.newTimer
   → 三者在字面上不一致；本课程以「实测 + 官方测试断言 + 官方文档行为描述」为准。
```

**三方说法摆在一起：**

| 来源 | 说的是什么 |
|---|---|
| 官方文档 `NewTimer` | *"As of Go 1.23, the channel is synchronous (unbuffered, **capacity 0**)"* |
| 官方测试 `time/tick_test.go:400` | `if l, c := len(C), cap(C); l != 0 \|\| c != 0 { t.Fatalf(..., want 0, 0) }` —— **断言 `cap == 0`** |
| 源码 `time/sleep.go` | `c := make(chan Time, 1)` —— **字面是 1** |
| 实测（三种独立手段） | **`cap == 0`** |

**为什么会这样？** 我在 `runtime/time.go` 里找到了一个关键约束 —— `newTimer` 对带 channel 的定时器做了一次校验：

```go
	if c != nil {
		lockInit(&t.sendLock, lockRankTimerSend)
		t.isChan = true
		c.timer = &t.timer
		if c.dataqsiz == 0 {
			throw("invalid timer channel: no capacity")
		}
	}
```

> 源码原文，核查于 2026-09（`$GOROOT/src/runtime/time.go`）

**`if c.dataqsiz == 0 { throw(...) }`** —— **运行时要求传进来的 channel 必须有容量**（否则直接抛致命错误）。这说明**运行时确实收到了一个"有容量"的 channel**，而 `cap()` 显示 0 —— 说明 `cap()` 看到的 **不是这个 channel 本身**。

> 📌 **本课的结论与处理方式**：这是一处**官方文档、官方测试、源码字面、实测四者不完全一致**的地方。本课**不猜机制**，只做两件事：
> 1. **以"行为"为准**（这对写代码的人来说是唯一重要的）：**Go 1.23 起 `Stop` / `Reset` 之后从 `t.C` 接收一定阻塞、不会读到陈旧值** —— 这一条被官方文档、官方测试、本课实测**三方共同确认**。
> 2. **把"`cap(time.NewTimer().C) == 0`"作为一个可复现的实测事实记录下来**，并明确标注"与源码字面 `make(chan Time, 1)` 不一致、机制未查清"。
>
> ⚠️ **给你的实操建议：不要写任何依赖 `cap(timer.C)` 的代码。** 它是一个"实现细节的观测值"，不在任何契约里。

##### §3.8 热路径上 `time.After` 的成本（带阈值）

`time.After` 的文档里有这么一句：

> *"…As of Go 1.23, the garbage collector can recover unreferenced, unstopped timers. **There is no reason to prefer NewTimer when After will do.**"*
> （核查于 2026-09）

**"当 `After` 够用时，没有理由偏好 `NewTimer`"** —— 这句话是对的，**但它的前提是"够用"**。`After` 的问题从来不是 GC，而是**分配**。基准测试（`-count=2` 两轮）：

```console
BenchmarkAfterInLoop-11      	 2556428	       154.9 ns/op	     248 B/op	       3 allocs/op
BenchmarkAfterInLoop-11      	 2590509	       138.5 ns/op	     248 B/op	       3 allocs/op
BenchmarkNewTimerReuse-11    	 3853380	        93.67 ns/op	       0 B/op	       0 allocs/op
BenchmarkNewTimerReuse-11    	 3900733	        90.36 ns/op	       0 B/op	       0 allocs/op
BenchmarkAfterFired-11       	  103024	      3593 ns/op	     248 B/op	       3 allocs/op
BenchmarkAfterFired-11       	  101078	      3952 ns/op	     248 B/op	       3 allocs/op
BenchmarkNewTimerFired-11    	   95991	      3919 ns/op	       0 B/op	       0 allocs/op
BenchmarkNewTimerFired-11    	   96012	      3942 ns/op	       0 B/op	       0 allocs/op
```

**四个基准其实是两组对照**：

| 组 | 场景 | `time.After` | 复用 `NewTimer` | 差异 |
|---|---|---|---|---|
| 1 | **定时器根本没响**（只是创建/重置，如热路径里的 `select` 超时分支没被走到） | **≈145 ns / 248 B / 3 allocs** | **≈92 ns / 0 B / 0 allocs** | **快 ≈1.6 倍、内存从 248 B 降到 0** |
| 2 | **定时器真的响了**（等满一个短 duration） | **≈3.8 µs / 248 B / 3 allocs** | **≈3.9 µs / 0 B / 0 allocs** | 时间**持平**（都受调度器影响），内存**还是 248 B vs 0** |

**阈值口径**：

> - **如果 `After` 在热路径里被频繁创建，但绝大多数时候不会真正等到**（典型：`select` 里的超时分支 —— 正常路径上响应比超时快得多）→ **第 1 组的差异就是你实际承担的：每个请求 248 B、3 次分配。** 这时**换成复用 `Timer` 是纯赚**。
> - **如果定时器每次都真的响完**（典型：一个循环里每次都 `Sleep` 式等待）→ **时间上两者持平**（因为等待本身的数量级远大于创建的 240 ns），**复用只省内存**。
> - **如果一个进程里 `After` 的调用频率是"每秒几次"级别** → 248 B 完全可以忽略，**不要为了它把代码搞复杂**。
> - **判据不是"`After` 好不好"，而是"`After` 在不在热路径里"。** 每秒百万次 → 换；每秒几次 → 不换。

本课的完整示例用 `TotalAlloc` 把这件事量化了一遍（20 万次）：

```console
② 热路径 200000 次：time.After vs 复用 Timer（累计 TotalAlloc）
   time.After 每次新建：累计分配 47.31 MB（每个约 248 B）
   复用同一个 Timer ：累计分配 0.00 MB
```

**20 万次 → 47 MB vs 0 MB。** 如果这是"每请求一次"，那就是**每天几十 GB 的无谓分配**（这些内存最终都会被回收，但**分配本身要花 CPU、GC 要花 CPU**）。

**§1.5 讲过的 `AfterFunc` 内存现象在这里还有个呼应**：`After` / `NewTimer` / `NewTicker` 未 Stop 都能被 GC 回收，但**"能被回收"不等于"分配不要钱"**。**这两件事是独立的**：

- **GC 回收**决定"内存会不会持续涨"；
- **分配**决定"CPU 花在分配和 GC 上的比例"。

##### §3.9 布局串：`2006-01-02 15:04:05` 这个魔数

Go 的时间格式化**不用 `YYYY-MM-DD` 这种占位符**，而是**用一个固定的"参考时刻"当模板**。这个参考时刻是：

```
Mon Jan 2 15:04:05 MST 2006        （= Unix 时间戳 1136239445，美国山区时间 15:04:05）
```

**为什么是这些数字？** 因为它们拼起来是 `01/02 03:04:05PM '06 -0700` —— **1、2、3、4、5、6、7 递增**，好记。这就是常量 `time.Layout` 的值：

```go
const (
	Layout      = "01/02 03:04:05PM '06 -0700" // The reference time, in numerical order.
	ANSIC       = "Mon Jan _2 15:04:05 2006"
	UnixDate    = "Mon Jan _2 15:04:05 MST 2006"
	RubyDate    = "Mon Jan 02 15:04:05 -0700 2006"
	RFC822      = "02 Jan 06 15:04 MST"
	RFC822Z     = "02 Jan 06 15:04 -0700" // RFC822 with numeric zone
	RFC850      = "Monday, 02-Jan-06 15:04:05 MST"
	RFC1123     = "Mon, 02 Jan 2006 15:04:05 MST"
	RFC1123Z    = "Mon, 02 Jan 2006 15:04:05 -0700" // RFC1123 with numeric zone
	RFC3339     = "2006-01-02T15:04:05Z07:00"
	RFC3339Nano = "2006-01-02T15:04:05.999999999Z07:00"
	Kitchen     = "3:04PM"
	// Handy time stamps.
	Stamp      = "Jan _2 15:04:05"
	StampMilli = "Jan _2 15:04:05.000"
	StampMicro = "Jan _2 15:04:05.000000"
	StampNano  = "Jan _2 15:04:05.000000000"
	DateTime   = "2006-01-02 15:04:05"
	DateOnly   = "2006-01-02"
	TimeOnly   = "15:04:05"
)
```

> 源码原文，核查于 2026-09（`$GOROOT/src/time/format.go`）

**注意最后三个常量是 Go 1.20 新增的**（`DateTime` / `DateOnly` / `TimeOnly`）—— **"2006-01-02 15:04:05" 这个你天天手写的串，现在有官方名字了：`time.DateTime`。** 用它比手写更不容易写错。

**同一个时刻跑各种布局（本课探针的实测表）：**

```console
2) 用同一个时刻 2026-09-13 13:14:15.123 +0800 试各种布局
   DateTime             "2006-01-02 15:04:05"        → 2026-09-13 13:14:15
   带毫秒                  "2006-01-02 15:04:05.000"    → 2026-09-13 13:14:15.123
   带时区偏移                "2006-01-02 15:04:05 -0700"  → 2026-09-13 13:14:15 +0800
   带时区名                 "2006-01-02 15:04:05 MST"    → 2026-09-13 13:14:15 CST
   RFC3339              "2006-01-02T15:04:05Z07:00"  → 2026-09-13T13:14:15+08:00
   RFC3339Nano          "2006-01-02T15:04:05.999999999Z07:00" → 2026-09-13T13:14:15.123456789+08:00
   UnixDate             "Mon Jan _2 15:04:05 MST 2006" → Sun Sep 13 13:14:15 CST 2026
   ANSIC                "Mon Jan _2 15:04:05 2006"   → Sun Sep 13 13:14:15 2026
   Kitchen              "3:04PM"                     → 1:14PM
   只要年月                 "2006-01"                    → 2026-09
   月/日 12 小时制           "01/02 03:04:05PM"           → 09/13 01:14:15PM
   两位年                  "06-01-02"                   → 26-09-13
   一年中的第几天              "2006-002"                   → 2026-256
   星期几                  "Monday"                     → Sunday
   带小数秒（去尾零）            "15:04:05.999"               → 13:14:15.123
```

**几个必须记住的 token**（注意它们是**"按示例值"匹配的，不是按字母**）：

| 你想要 | 写 | 反例（常见错误） |
|---|---|---|
| 年 4 位 | `2006` | ❌ `YYYY` / `yyyy` |
| 月 2 位（补零） | `01` | ❌ `MM`（`MM` 在 Go 里**不是月份**，会原样输出） |
| 日 2 位（补零） | `02` | ❌ `DD` |
| 日不补零 | `2` | |
| 时 24 小时制（补零） | `15` | ❌ `HH` |
| 时 12 小时制（补零） | `03` | |
| 分（补零） | `04` | ❌ `mm`（`mm` 是**分钟**没错，但 `MM` 是月份 —— 大小写在这里是要命的） |
| 秒（补零） | `05` | ❌ `ss` |
| 秒的小数部分（去尾零） | `.999` | |
| 秒的小数部分（补零） | `.000` | |
| 时区偏移 | `-0700` / `Z07:00` | |
| 时区名 | `MST` | |

**然后是本课最该警惕的一条 —— 写错布局串不报错：**

```console
3) 布局串写错会怎样：Format 不报错，只是原样吐出你的字面量
   "2006-01-02 15:04:05"    → "2026-09-13 13:14:15"
   "YYYY-MM-DD HH:mm:ss"    → "YYYY-MM-DD HH:mm:ss"
   "2006-1-2"               → "2026-9-13"
   "2006-01-02 3:04:05"     → "2026-09-13 1:14:15"
   "2006/01/02"             → "2026/09/13"
```

**`Format("YYYY-MM-DD HH:mm:ss")` 返回的就是字符串 `"YYYY-MM-DD HH:mm:ss"` 本身** —— 不报错、不 panic、日志里看着"像那么回事"，**但你把它写进了每一行日志**。

本课示例里也复现了同一个现象：

```console
   布局串写成 YYYY-MM-DD HH:mm:ss → "YYYY-MM-DD HH:mm:ss" ← 不报错，就是原样输出
```

> 🐞 **这就是"魔数布局串"最危险的地方**：**它把"写错了"变成了一件静默的事。** 而这类错误还有一个**注定会在某一天爆发的变体**：`"2006-01-02 15:04:05"` 里的 `01` 不只是"月份占位符" —— **如果你的模板里恰好有一个真实数字片段和 token 撞了**（比如 `"2006-01-02 T15"` 里的 `T15`），它会被**当成 token 解析**，输出一个你完全没预期的结果。
>
> **防御手段**：**布局串一律用常量（`time.DateTime` / 自定义 `const Layout = ...`），不要在代码里散落字面量；并且给格式化/解析写一个"单元测试"级别的往返用例**（`Parse(Format(t)) == t`）。课 13 讲测试时会用到这个模式。

##### §3.10 `Parse`：错误原文、两位年、以及"不带时区算 UTC"

`Format` 不报错，但 `Parse` **会**。四条真实错误原文：

```console
4) Parse 会挑错（原文照抄）
   Parse("2006-01-02 15:04:05" , "2026-09-13 13:14:15" ) → 2026-09-13 13:14:15 +0000 UTC
   Parse("2006-01-02 15:04:05" , "2026/09/13 13:14:15" ) → err = parsing time "2026/09/13 13:14:15" as "2006-01-02 15:04:05": cannot parse "/09/13 13:14:15" as "-"
   Parse("2006-01-02"          , "2026-13-01"          ) → err = parsing time "2026-13-01": month out of range
   Parse("2006-01-02 15:04:05" , "2026-09-13"          ) → err = parsing time "2026-09-13" as "2006-01-02 15:04:05": cannot parse "" as "15"
```

**四种错误各有各的形状**，这在排查时很有用：

| 情况 | 错误形状 |
|---|---|
| 分隔符不匹配 | `cannot parse "/09/13 13:14:15" as "-"` —— **告诉你"从这里开始对不上"** |
| 数值越界 | `month out of range` —— **不带原文，只说范围** |
| 字符串太短 | `cannot parse "" as "15"` —— **空串表示"输入已经用完了"** |
| （另有）布局里有非法 token | `cannot parse ... as "..."` 或 `extra text` 等 |

**⚠️ 第一行那个 `+0000 UTC` 是最隐蔽的一行。** 解析出来的时间是 `2026-09-13 13:14:15 UTC` —— 而输入字符串**根本没有时区信息**。`Parse` 的文档写着：

> *"In the absence of a time zone indicator, `Parse` returns a time in **UTC**."*
> （核查于 2026-09-09）

**这句话的后果非常大**：中国用户传 `"2026-09-13 13:14:15"` 指的是北京时间，`Parse` 直接给你当成 UTC —— **差 8 小时**。本课示例里把它量化了：

```console
   ParseInLocation("2006-01-02 15:04:05") → 2026-09-13 13:14:15 +0800 CST（Unix=1789276455）
   Parse          ("2006-01-02 15:04:05") → 2026-09-13 13:14:15 +0000 UTC（Unix=1789305255）← 差 8 小时
```

**同一个字符串，`Unix()` 相差 `28800` 秒。**

**两位年的 69 分界**（官方明文规则）：

> *"For layouts specifying the two-digit year 06, a value NN >= 69 will be treated as 19NN and a value NN < 69 will be treated as 20NN."*
> （核查于 2026-09）

```console
6) 两位年 '06' 的 69 分界（官方原文：>=69 当 19xx，<69 当 20xx）
   "68-01-01" → 2068-01-01
   "69-01-01" → 1969-01-01
   "70-01-01" → 1970-01-01
   "00-01-01" → 2000-01-01
   "99-01-01" → 1999-01-01
```

> 🐞 **"68 → 2068，69 → 1969"** —— 这个分界是**故意的**（它来自 POSIX 的 `strptime`），**但它会让"1968 年"和"2068 年"走进完全不同的分支。** 结论很简单：**永远别用两位年布局（`06`）来解析业务数据**，只在解析"历史遗留的日志格式"时才用，且要知道这个分界。

##### §3.11 时区：`Parse` vs `ParseInLocation`，以及"取不到时区"的报错

```console
5) 不带时区的字符串：Parse 当成 UTC，ParseInLocation 按给定位置
   Parse                          → 2026-09-13 13:14:15 UTC  (Unix=1789305255)
   ParseInLocation(time.Local)    → 2026-09-13 13:14:15 CST  (Unix=1789276455)
   ParseInLocation(Asia/Shanghai) → 2026-09-13 13:14:15 CST  (Unix=1789276455)
```

`ParseInLocation` 的文档把"两处不同"写得很清楚：

> ```go
> // ParseInLocation is like Parse but differs in two important ways.
> // First, in the absence of time zone information, Parse interprets a time as UTC;
> // ParseInLocation interprets the time as in the given location.
> // Second, when given a zone offset or abbreviation, Parse tries to match it
> // against the Local location; ParseInLocation uses the given location.
> ```
> 源码原文，核查于 2026-09

**注意第二处不同** —— 它更隐蔽：**如果字符串里带了时区名（比如 `MST`），`Parse` 会拿它去和 `Local` 匹配；`ParseInLocation` 则用你给的那个 location。** 而 `Parse` 文档还警告了"时区名匹配不上"的后果：

> *"If the zone abbreviation is unknown, `Parse` records the time as being in a fabricated location with the given zone abbreviation and a zero offset. This choice means that such a time can be parsed and reformatted with the same layout losslessly, but the exact instant used in the representation will differ by the actual zone offset. **To avoid such problems, prefer time layouts that use a numeric zone offset, or use `ParseInLocation`.**"*

**"宁可带数字偏移（`-0700`），也别带时区名（`MST`）"** —— 因为 `CST` 这种缩写在地球上至少对应三个不同的时区。

**时区数据库：**

```console
7) 时区数据库
   LoadLocation("Asia/Shanghai"     ) → 2026-09-13 13:14:15 CST +0800
   LoadLocation("America/New_York"  ) → 2026-09-13 01:14:15 EDT -0400
   LoadLocation("UTC"               ) → 2026-09-13 05:14:15 UTC +0000
   LoadLocation("不存在的时区"            ) → err = unknown time zone 不存在的时区
   LoadLocation("Local"             ) → 2026-09-13 13:14:15 CST +0800
```

**`LoadLocation` 依赖"时区数据库"**（macOS/Linux 上通常是 `/usr/share/zoneinfo`）。这带来一个**部署坑**：**精简容器镜像（比如 scratch / distroless）里没有 zoneinfo** → `LoadLocation("Asia/Shanghai")` 会返回 `unknown time zone`。

> ⚠️ **部署时的对策（本机未实测容器场景，按官方文档陈述）**：Go 会在没有系统时区库时**回退到内置的 `time/tzdata`**（`import _ "time/tzdata"` 可以把整份 tzdata 嵌进二进制，**代价是二进制增大若干百 KB**）；或者把 `zoneinfo` 一起打进镜像。

**还有一个"服务器时区"的通用纪律**：**服务端一律用 UTC 存储和计算，只在"展示给用户"的那一刻转成本地时区。** 本课示例里的 `FormatOrderTime` / `ParseOrderTime` 就是按这个模式写的：

```go
// FormatOrderTime 把订单时间格式化成人能看的样子（固定北京时间）
func FormatOrderTime(t time.Time) string {
	return t.In(time.FixedZone("CST", 8*3600)).Format(LayoutOrder)
}

// ParseOrderTime 解析业务侧传来的时间字符串。
// ★ 用 ParseInLocation：不带时区的字符串按"东八区"解释，而不是 UTC
func ParseOrderTime(s string) (time.Time, error) {
	return time.ParseInLocation(LayoutOrder, s, time.FixedZone("CST", 8*3600))
}
```

**为什么不用 `time.Local`？** 因为**容器里的 `Local` 常常是 UTC** —— 一旦你的宿主机时区变了，解析结果就变了。**用 `FixedZone` / `LoadLocation` 显式钉死，才是可复现的。**

##### §3.12 Unix 时间戳：精度与"2262 年溢出"

```console
8) Unix 时间戳：秒 / 毫秒 / 纳秒
   Unix()      = 1789305255
   UnixMilli() = 1789305255123
   UnixMicro() = 1789305255123456
   UnixNano()  = 1789305255123456789
   time.Unix(秒) 往返丢精度 → 2026-09-13 13:14:15.000000000（纳秒被抹掉）
   time.UnixMilli 往返     → 2026-09-13 13:14:15.123000000（毫秒精度）
   2262-04-11 23:47:16 的 UnixNano = 9223372036000000000
   2263-01-01 的 UnixNano          = -9200561673709551616 ← int64 纳秒溢出成负数
```

**最后两行是最好的"溢出演示"**：`int64` 纳秒的表示范围到 **2262-04-11 23:47:16.854775807** 为止；再往后加，**直接变成负数**。

> 📌 **两个可操作结论**：
> 1. **`UnixNano` 只适合"时间差"**（`time.Duration` 也是 int64 纳秒，所以 `Duration` 的最大值约 292 年 —— 但那是**差值**的容量，不是绝对时刻的容量）。**存"绝对时间"用 `UnixMilli` 更安全**（毫秒能表达到约 292 万年）。
> 2. **一旦有人把 `UnixNano()` 存进了数据库的 bigint，你的系统就有了一个 2262 年的硬墙。** 本机跑出来是负数这一点，正是"墙"的样子。

**精度损失也是实的**：`time.Unix(秒)` 往返会**抹掉纳秒**（因为秒级时间戳本来就不含纳秒）。要保精度就得用 `UnixMilli` / `UnixMicro` / `UnixNano`，或者直接存 `RFC3339Nano` 字符串。

##### §3.13 `AddDate` 的月末回绕，和 `Duration` 的两种取整

```console
9) AddDate 的月末回绕（不是“加 30 天”）
   2026-01-31 AddDate(0,1,0) → 2026-03-03
   2026-01-31 AddDate(0,3,0) → 2026-05-01
   2026-08-31 AddDate(0,1,0) → 2026-10-01
   2026-03-31 AddDate(0,-1,0) → 2026-03-03
```

**"1 月 31 日加 1 个月"** 直觉答案是 2 月 28 日（或 29 日），**Go 给的是 3 月 3 日**。

**为什么？** 因为 `AddDate` 的实现是"**先把月份字段加上去，再把日期字段做规范化**"：`2026-01-31` → 月份 +1 变成 `2026-02-31` → 规范化（2 月只有 28 天，多出来的 3 天顺延到 3 月）→ **`2026-03-03`**。

本课示例里跑了一个对照，说明"按天加"和"按月加"完全是两回事：

```console
   2026-01-31 AddDate(0,1,0) → 2026-03-03（不是 02-28，也不是 03-01）
   2026-01-31 AddDate(0,0,30)→ 2026-03-02（按「天」加才是 03-02）
```

> 🐞 **这是账单、订阅、合同这类业务的经典事故**：用 `AddDate(0, 1, 0)` 算"下个月同日"，**1 月 31 日签约的用户会在 3 月 3 日被扣款**（而不是 2 月 28 日）。
>
> **正确做法**：这类需求要**显式定义规则**（"下个月的最后一个自然日"？"下个月的同一天，不存在则取当月最后一天"？），然后自己用 `time.Date(y, m+1, 0, ...)` 之类的算式实现，**不要依赖 `AddDate` 的规范化行为**。

**Duration 的 `Round` / `Truncate`：**

```console
10) 格式化 Duration：Round 与 Truncate 的差别
   d            = 1m31.234s
   Truncate(1s) = 1m31s（向下截）
   Round(1s)    = 1m31s（四舍五入）
   String()     = 1m31.234s
   手写 mm:ss   = 01:31
```

**注意这一例里两者碰巧一样**（因为小数部分是 `.234`，四舍五入和向下截都回到 `1m31s`）。要看出区别得用 `.5` 以上的小数：

| 输入 | `Truncate(1s)` | `Round(1s)` |
|---|---|---|
| `1m31.234s` | `1m31s` | `1m31s` |
| `1m31.900s` | `1m31s` | **`1m32s`** |

**`String()` 的默认格式**是 `1m31.234s`（`h` / `m` / `s` / `ms` / `µs` / `ns` 组成），**它对人类不友好**。要做 `mm:ss` 得自己算：

```go
func mmss(d time.Duration) string {
	d = d.Round(time.Second)          // 先决定用什么粒度
	return fmt.Sprintf("%02d:%02d", int(d/time.Minute), int(d/time.Second)%60)
}
```

> 💡 **Duration 是一条"有单位但无时区"的纯数字**（`int64` 纳秒），所以它**没有 `time.Time` 的那些时区麻烦**。但要注意 **`Duration` 的 `String()` 在超过 1 小时时是 `1h2m3s` 形式**、**永不出现"天"这个单位**（`48h` 而不是 `2d`）—— 需要"天"就自己除。

#### ④ 示例演示：一个服务端定时任务骨架 + 时间处理工具

下面这份代码是本课探针 `/tmp/go-l12/p17_timeutil`（**在 go1.27.1 上真实跑通，`gofmt` / `go vet` 干净**）。它把本节四块内容串成一个可复用的骨架。

**① 定时任务骨架 —— 服务端里唯一推荐的写法：**

```go
// RunPeriodic 每 period 跑一次 job，直到 ctx 取消。
// ★ 三个纪律：Ticker 必须 Stop；用 select 同时看 ctx 和 tick；
//   job 的耗时要算出来，否则"慢 job"会吃掉整个周期。
func RunPeriodic(ctx context.Context, period time.Duration, maxRuns int, job func(run int, drift time.Duration)) int {
	t := time.NewTicker(period)
	defer t.Stop() // ★ 无论怎么返回都要 Stop

	start := time.Now()
	runs := 0
	for {
		select {
		case <-ctx.Done():
			return runs
		case tick := <-t.C:
			runs++
			// ★ 用 Since 算真实间隔，而不是自己累加 period
			job(runs, time.Since(start))
			if maxRuns > 0 && runs >= maxRuns {
				return runs
			}
			_ = tick
		}
	}
}
```

**三个"★"分别对应本节的三条原理**：`defer t.Stop()`（§3.5）、`select` 同时看 `ctx`（课 10 的取消树 + §3.5"Stop 不关 channel"）、`time.Since` 而不是自己累加（§3.2 单调读）。

**它的真实输出：**

```console
① 定时任务骨架：Ticker + ctx 收口 + Stop
   run #1 已运行 42ms
   run #2 已运行 82ms
   run #3 已运行 122ms
   run #4 已运行 160ms
   run #5 已运行 202ms
   返回 5 次运行（maxRuns=5 到点主动返回）
   ctx 在 60ms 时取消 → 返回 1 次运行（Ticker 已被 defer Stop）
```

**注意两次返回路径都被验证了**：一条是"跑满 5 次自己返回"，一条是"ctx 先取消"。**后者是服务端最常见的路径**（进程要下线 → ctx 取消 → 定时任务收摊）。

**② 热路径分配对比（用 `runtime.MemStats.TotalAlloc`）：**

```go
func allocPerLoop(kind string, n int) uint64 {
	var a, b runtime.MemStats
	runtime.GC()
	runtime.ReadMemStats(&a)

	switch kind {
	case "after":
		for i := 0; i < n; i++ {
			_ = time.After(time.Hour) // 每次新建一个定时器
		}
	case "reuse":
		t := time.NewTimer(time.Hour)
		for i := 0; i < n; i++ {
			t.Reset(time.Hour) // 复用同一个
			_ = t.C
		}
		t.Stop()
	}

	runtime.ReadMemStats(&b)
	return b.TotalAlloc - a.TotalAlloc
}
```

```console
② 热路径 200000 次：time.After vs 复用 Timer（累计 TotalAlloc）
   time.After 每次新建：累计分配 47.31 MB（每个约 248 B）
   复用同一个 Timer ：累计分配 0.00 MB
```

> 💡 **这里用了一个很实用的测量技巧：`TotalAlloc`** —— 它是**累计分配字节数**，**不受 GC 影响**，所以能测出"分配了多少"而不是"当前占了多少"。这正是 §3.8 里"GC 能回收 ≠ 分配不要钱"的量化手段。**课 14 讲 pprof 时会遇到它的亲戚 `allocs` profile。**

**③ 格式化与解析（含三个常量、两位年、月末回绕）：**

```go
const (
	LayoutOrder   = "2006-01-02 15:04:05" // 业务里最常用的这种
	LayoutCompact = "20060102150405"      // 紧凑型（日志文件名、ID）
	LayoutDay     = "2006-01-02"          // 只要日期
)
```

```console
③ 订单时间戳：格式化与解析
   原始时刻   2026-09-13 13:14:15.123456789 +0800 CST
   LayoutOrder   "2006-01-02 15:04:05" → 2026-09-13 13:14:15
   LayoutCompact "20060102150405" → 20260913131415
   LayoutDay     "2006-01-02" → 2026-09-13
   RFC3339           → 2026-09-13T13:14:15+08:00
   RFC3339Nano       → 2026-09-13T13:14:15.123456789+08:00
   ParseInLocation("2006-01-02 15:04:05") → 2026-09-13 13:14:15 +0800 CST（Unix=1789276455）
   Parse          ("2006-01-02 15:04:05") → 2026-09-13 13:14:15 +0000 UTC（Unix=1789305255）← 差 8 小时
   解析错格式 → err=parsing time "2026/09/13 13:14:15" as "2006-01-02 15:04:05": cannot parse "/09/13 13:14:15" as "-"
   布局串写成 YYYY-MM-DD HH:mm:ss → "YYYY-MM-DD HH:mm:ss" ← 不报错，就是原样输出
   两位年 "68-01-01" → 2068-01-01
   两位年 "69-01-01" → 1969-01-01
   两位年 "99-01-01" → 1999-01-01
   2026-01-31 AddDate(0,1,0) → 2026-03-03（不是 02-28，也不是 03-01）
   2026-01-31 AddDate(0,0,30)→ 2026-03-02（按「天」加才是 03-02）
```

**这一屏输出几乎把 §3.9 / §3.10 / §3.13 全部覆盖了**，而且每个坑都有"正确 vs 错误"的对照。

**④ 单调时钟陷阱现场 + 时间戳精度：**

```console
④ 单调时钟：同一段 250ms 的睡眠，两种写法
   time.Since(start)                = 252.025459ms
   time.Since(start.Truncate(1s))    = 1.117634s ← 凭空多算了 start 的小数秒
   t == t.Round(0)      → false（== 连单调读一起比）
   t.Equal(t.Round(0))  → true（Equal 只比时刻）

   Unix()=1789276455 UnixMilli()=1789276455123 UnixNano()=1789276455123456789
   time.Unix(秒) 往返 → 2026-09-13T05:14:15Z（纳秒被抹掉）
   Duration 1m31.234s：Truncate(1s)=1m31s Round(1s)=1m31s
```

**逐条对上原理：**

| 输出 | 对应 |
|---|---|
| `time.Since(start)` = 252 ms vs `Truncate(1s)` = 1.117 s | §3.2 丢单调读的后果（多算 0~1 秒） |
| `t == t.Round(0) → false` / `Equal → true` | §3.1 `==` 比三样、`Equal` 只比时刻 |
| `time.Unix(秒) 往返 → ...T05:14:15Z`（UTC 显示） | §3.12 秒级往返抹掉纳秒 |
| `Duration 1m31.234s` 两种取整 | §3.13 碰巧相同（`.234` 不够进一位） |

<details>
<summary><b>📦 完整可运行源码（185 行）</b></summary>

```go
// package main —— 知识点 3 的完整示例：时间与定时器
//
//	① 定时任务骨架（Ticker + ctx 收口 + Stop）
//	② 热路径上 time.After vs 复用 Timer 的累计分配
//	③ 订单时间戳的格式化与解析（含布局串、两位年、时区、AddDate 月末回绕）
//	④ 单调时钟陷阱现场
package main

import (
	"context"
	"fmt"
	"runtime"
	"time"
)

// ============ ① 服务端定时任务骨架 ============

// RunPeriodic 每 period 跑一次 job，直到 ctx 取消。
// ★ 三个纪律：Ticker 必须 Stop；用 select 同时看 ctx 和 tick；
//
//	job 的耗时要算出来，否则"慢 job"会吃掉整个周期。
func RunPeriodic(ctx context.Context, period time.Duration, maxRuns int, job func(run int, drift time.Duration)) int {
	t := time.NewTicker(period)
	defer t.Stop() // ★ 无论怎么返回都要 Stop

	start := time.Now()
	runs := 0
	for {
		select {
		case <-ctx.Done():
			return runs
		case tick := <-t.C:
			runs++
			// ★ 用 Since 算真实间隔，而不是自己累加 period
			job(runs, time.Since(start))
			if maxRuns > 0 && runs >= maxRuns {
				return runs
			}
			_ = tick
		}
	}
}

// ============ ② 热路径：After vs 复用 Timer ============

func allocPerLoop(kind string, n int) uint64 {
	var a, b runtime.MemStats
	runtime.GC()
	runtime.ReadMemStats(&a)

	switch kind {
	case "after":
		for i := 0; i < n; i++ {
			_ = time.After(time.Hour) // 每次新建一个定时器
		}
	case "reuse":
		t := time.NewTimer(time.Hour)
		for i := 0; i < n; i++ {
			t.Reset(time.Hour) // 复用同一个
			_ = t.C
		}
		t.Stop()
	}

	runtime.ReadMemStats(&b)
	return b.TotalAlloc - a.TotalAlloc
}

// ============ ③ 格式化与解析 ============

const (
	LayoutOrder   = "2006-01-02 15:04:05" // 业务里最常用的这种
	LayoutCompact = "20060102150405"      // 紧凑型（日志文件名、ID）
	LayoutDay     = "2006-01-02"          // 只要日期
)

// FormatOrderTime 把订单时间格式化成人能看的样子（固定北京时间）
func FormatOrderTime(t time.Time) string {
	return t.In(time.FixedZone("CST", 8*3600)).Format(LayoutOrder)
}

// ParseOrderTime 解析业务侧传来的时间字符串。
// ★ 用 ParseInLocation：不带时区的字符串按"东八区"解释，而不是 UTC
func ParseOrderTime(s string) (time.Time, error) {
	return time.ParseInLocation(LayoutOrder, s, time.FixedZone("CST", 8*3600))
}

// ============ ④ 单调时钟 ============

func measure(kind string) time.Duration {
	start := time.Now()
	time.Sleep(250 * time.Millisecond)
	switch kind {
	case "correct":
		return time.Since(start)
	case "trap":
		return time.Since(start.Truncate(time.Second)) // ← 把截断过的时间当起点
	}
	return 0
}

// ============ main ============

func main() {
	// ---------- ① 定时任务 ----------
	fmt.Println("① 定时任务骨架：Ticker + ctx 收口 + Stop")
	ctx, cancel := context.WithCancel(context.Background())
	runs := RunPeriodic(ctx, 40*time.Millisecond, 5, func(run int, drift time.Duration) {
		fmt.Printf("   run #%d 已运行 %v\n", run, drift.Round(time.Millisecond))
	})
	cancel()
	fmt.Printf("   返回 %d 次运行（maxRuns=5 到点主动返回）\n", runs)

	// 再看一次"ctx 先取消"的路径
	ctx2, cancel2 := context.WithCancel(context.Background())
	go func() { time.Sleep(60 * time.Millisecond); cancel2() }()
	runs2 := RunPeriodic(ctx2, 40*time.Millisecond, 0, func(int, time.Duration) {})
	fmt.Printf("   ctx 在 60ms 时取消 → 返回 %d 次运行（Ticker 已被 defer Stop）\n", runs2)

	// ---------- ② 热路径分配 ----------
	const N = 200000
	fmt.Printf("\n② 热路径 %d 次：time.After vs 复用 Timer（累计 TotalAlloc）\n", N)
	afterBytes := allocPerLoop("after", N)
	reuseBytes := allocPerLoop("reuse", N)
	fmt.Printf("   time.After 每次新建：累计分配 %.2f MB（每个约 %.0f B）\n",
		float64(afterBytes)/(1<<20), float64(afterBytes)/float64(N))
	fmt.Printf("   复用同一个 Timer ：累计分配 %.2f MB\n", float64(reuseBytes)/(1<<20))

	// ---------- ③ 格式化与解析 ----------
	fmt.Println("\n③ 订单时间戳：格式化与解析")
	fixed := time.Date(2026, 9, 13, 13, 14, 15, 123456789, time.FixedZone("CST", 8*3600))
	fmt.Printf("   原始时刻   %v\n", fixed)
	fmt.Printf("   LayoutOrder   %q → %s\n", LayoutOrder, fixed.Format(LayoutOrder))
	fmt.Printf("   LayoutCompact %q → %s\n", LayoutCompact, fixed.Format(LayoutCompact))
	fmt.Printf("   LayoutDay     %q → %s\n", LayoutDay, fixed.Format(LayoutDay))
	fmt.Printf("   RFC3339           → %s\n", fixed.Format(time.RFC3339))
	fmt.Printf("   RFC3339Nano       → %s\n", fixed.Format(time.RFC3339Nano))

	parsed, err := ParseOrderTime("2026-09-13 13:14:15")
	fmt.Printf("   ParseInLocation(%q) → %v（Unix=%d）\n", LayoutOrder, parsed, parsed.Unix())
	parsedUTC, _ := time.Parse(LayoutOrder, "2026-09-13 13:14:15")
	fmt.Printf("   Parse          (%q) → %v（Unix=%d）← 差 8 小时\n", LayoutOrder, parsedUTC, parsedUTC.Unix())

	_, err = ParseOrderTime("2026/09/13 13:14:15")
	fmt.Printf("   解析错格式 → err=%v\n", err)

	// 写错布局串：不报错，原样吐出字面量
	fmt.Printf("   布局串写成 YYYY-MM-DD HH:mm:ss → %q ← 不报错，就是原样输出\n",
		fixed.Format("YYYY-MM-DD HH:mm:ss"))

	// 两位年的 69 分界
	for _, s := range []string{"68-01-01", "69-01-01", "99-01-01"} {
		t, _ := time.Parse("06-01-02", s)
		fmt.Printf("   两位年 %q → %s\n", s, t.Format("2006-01-02"))
	}

	// AddDate 月末回绕
	jan31 := time.Date(2026, 1, 31, 0, 0, 0, 0, time.UTC)
	fmt.Printf("   2026-01-31 AddDate(0,1,0) → %s（不是 02-28，也不是 03-01）\n",
		jan31.AddDate(0, 1, 0).Format("2006-01-02"))
	fmt.Printf("   2026-01-31 AddDate(0,0,30)→ %s（按「天」加才是 03-02）\n",
		jan31.AddDate(0, 0, 30).Format("2006-01-02"))

	// ---------- ④ 单调时钟 ----------
	fmt.Println("\n④ 单调时钟：同一段 250ms 的睡眠，两种写法")
	correct := measure("correct")
	trap := measure("trap")
	fmt.Printf("   time.Since(start)                = %v\n", correct)
	fmt.Printf("   time.Since(start.Truncate(1s))    = %v ← 凭空多算了 start 的小数秒\n", trap)

	now := time.Now()
	fmt.Printf("   t == t.Round(0)      → %v（== 连单调读一起比）\n", now == now.Round(0))
	fmt.Printf("   t.Equal(t.Round(0))  → %v（Equal 只比时刻）\n", now.Equal(now.Round(0)))

	// Unix 时间戳精度
	fmt.Printf("\n   Unix()=%d UnixMilli()=%d UnixNano()=%d\n",
		fixed.Unix(), fixed.UnixMilli(), fixed.UnixNano())
	fmt.Printf("   time.Unix(秒) 往返 → %v（纳秒被抹掉）\n",
		time.Unix(fixed.Unix(), 0).UTC().Format(time.RFC3339Nano))

	// Duration 的 Round / Truncate
	d := 91*time.Second + 234*time.Millisecond
	fmt.Printf("   Duration %v：Truncate(1s)=%v Round(1s)=%v\n", d, d.Truncate(time.Second), d.Round(time.Second))
}
```

</details>

#### ⑤ 常见误区（知识点 3）

| # | 误区 | 真相 | 实测依据 |
|---|---|---|---|
| 1 | `time.Time` 只存"时刻" | 还带 `Location` 指针 + **单调读** | `String()` 里的 `m=+0.000279585` |
| 2 | 两个 `Time` 打印一样就 `==` | `==` 比时刻 + Location + 单调读 | `t == t.Round(0)` → **false** |
| 3 | 比较时间用 `==` 就行 | **用 `t.Equal(u)`**（官方建议） | `Equal` → true |
| 4 | 拿 `Time` 当 map key 很方便 | 几乎取不回来，除非**存和取都先 `Round(0)`** | 三次查找两次 `ok=false` |
| 5 | `Round` / `Truncate` / `In` 只是"改一下显示" | 它们会**永久丢掉单调读** | 9 项操作只有 `Add` 保留 |
| 6 | `Add` 也会丢单调读 | **只有 `Add` 保留** | `Add(time.Hour) → true` |
| 7 | 转成 JSON 再解析，时间还是那个时间 | 时刻对，但**单调读没了**，`==` 会变 false | `JSON 往返 → false` |
| 8 | 打点时候顺手 `Truncate` 一下没影响 | 会让耗时统计**随机多算最多一个截断粒度** | `251ms` vs `747ms`；`252ms` vs `1.117s` |
| 9 | `time.Since` 只是 `Now().Sub` 的语法糖 | 文档说是简写，但源码里有**快车道**（省掉一次 `Now()`） | `Since` 源码的 `subMono(...)` 分支 |
| 10 | 单调时钟总是反映真实经过时间 | **机器睡眠时它会停**（官方明文） | 文档：*"may not accurately reflect the actual time that passed"* |
| 11 | `Ticker` 会为慢消费者排队 | **丢 tick 或拉长间隔**，绝不排队 | 5 ms 周期挂 120 ms → 只积压 1 个 |
| 12 | `Ticker.Stop()` 会关闭 channel | **不关**（为了支持 `Reset`、避免假 tick） | 从已 Stop 的 `C` 接收**阻塞** |
| 13 | `for range ticker.C` 会在 Stop 后退出 | **永远不会退出**（channel 不关） | 同上；要 `select` + `ctx` |
| 14 | `time.Tick(0)` 会 panic | **返回 `nil`**（静默变成一个永不触发的 channel） | 官方注释 *"Tick will return nil if d <= 0"* |
| 15 | `Timer.Stop()` 返回 `false` = "已经响过了" | `false` 的真正判据是**值已经被接收过 / 已经被 `Stop` 过**；**"已到期但值没被接收"时 `Stop()` 仍返回 `true`**（Go 1.23 起） | `p18_timerstop` A 组 8 种情形 |
| 16 | `Stop` 返回 `false` 就必须补 `<-t.C` 排空 | **Go 1.23 起不需要**：`Stop` 返回后接收一定阻塞 | 官方注释 + 实测"永久阻塞" |
| 17 | `Reset` 的返回值和 `Stop` 一样 | **方向相反**：`Reset` 返回"原本还活着吗" | 活跃 → `true`；已到期 → `false` |
| 18 | `Reset` 之前必须先排空 channel | **Go 1.23 起不需要** | 官方注释 |
| 19 | "Go 1.23 起定时器不 Stop 也不泄漏"，所以全都不用管 | 对 `NewTimer` / `NewTicker` / `After` 成立；**`AfterFunc` 不成立** | 30 万个未 Stop 的 `AfterFunc` → **37.56 MB** |
| 20 | `AfterFunc` 返回的 `Timer` 能读 `C` | **`C` 是 `nil`**，读它会永久阻塞 | 官方注释 + 实测 `<nil>` |
| 21 | GC 能回收 = 分配不要钱 | **两件事独立**；`After` 在热路径里每次 248 B / 3 allocs | 基准 + 20 万次 → 47.31 MB |
| 22 | `After` 永远比 `NewTimer` 差 | **"响应比超时快"的热路径上才差**；真等满时两者持平 | 154.9 ns vs 93.67 ns（未响）；3593 vs 3919 ns（响了） |
| 23 | `cap(time.NewTimer().C)` 是 1 | **实测 0**（与源码字面 `make(chan Time, 1)` 不一致，机制未查清） | 三种独立手段都是 0；官方测试断言 0 |
| 24 | 布局串用 `YYYY-MM-DD` 是通用写法 | **Go 不认**，`Format` 会把它**原样输出**且不报错 | `→ "YYYY-MM-DD HH:mm:ss"` |
| 25 | 布局串写错会报错 | **`Format` 永远不报错**；只有 `Parse` 会 | 同上 |
| 26 | `Parse` 和 `ParseInLocation` 差不多 | 不带时区时一个当 **UTC**、一个按给定位置，**差 8 小时** | `Unix=1789305255` vs `1789276455` |
| 27 | 字符串里带了时区名就万事大吉 | `CST` 这种缩写**在地球上对应多个时区**；官方建议**改用数字偏移** | `Parse` 文档原文 |
| 28 | 两位年的 `69` 只是个数字 | **它是 `19xx` / `20xx` 的分界点** | `68 → 2068`，`69 → 1969` |
| 29 | `LoadLocation` 一定成功 | 精简镜像里**没有 tzdata** → `unknown time zone` | `LoadLocation("不存在的时区")` 的报错形状 |
| 30 | 服务端可以直接用 `time.Local` | 容器里 `Local` 常是 UTC；**显式用 `UTC` / `FixedZone` 才可复现** | 本课示例用 `FixedZone` 钉死 |
| 31 | `AddDate(0,1,0)` 就是"下个月同一天" | **是"加一个月再规范化"**；1/31 → 3/3 | 四组实测 |
| 32 | `UnixNano` 可以存任意时刻 | **2262 年之后 int64 溢出成负数** | `2263-01-01 → -9200561673709551616` |
| 33 | `time.Unix(秒)` 往返不丢精度 | **抹掉纳秒**；要精度用 `UnixMilli` / `RFC3339Nano` | `13:14:15.000000000` |
| 34 | `Duration.String()` 会输出"天" | **永不输出"天"**，最多到 `h` | `48h` 而不是 `2d` |
| 35 | `Duration` 也有时区问题 | **没有**，它是纯 `int64` 纳秒 | `truncate` / `round` 只是取整 |

#### ⑥ 一句话记住

> **`time.Time` 里装着墙钟和单调读两块表：`Round` / `Truncate` / `In` / `UTC` / `Local` / `AddDate` / JSON 往返都会把单调读丢掉，所以"开始时刻"这个变量在传给 `Since` 之前不要让它碰任何函数；定时器按构造类型分四种，**只有 `AfterFunc` 未 `Stop` 会持续占内存**，而且 Go 1.23 起 `Stop` / `Reset` 之后不再需要排空 channel；布局串是"用一个参考时刻当模板"，写错了既不报错也不生效 —— 所以请用 `time.DateTime` 这类常量，别散写字面量。**

#### 📚 官方文档

- 包文档（**必读的 "Monotonic Clocks" 一节**）：`go doc time` ／ [pkg.go.dev/time](https://pkg.go.dev/time)
- `Time` 类型与 `Equal` / `Compare` / `Round` / `Truncate` / `AddDate`：`go doc time.Time`
- 定时器：`go doc time.Timer` ／ `go doc time.Ticker` ／ `go doc time.After` ／ `go doc time.AfterFunc`
- 布局串常量全表：`go doc time.Layout`（含 `DateTime` / `DateOnly` / `TimeOnly`）
- 解析：`go doc time.Parse` ／ `go doc time.ParseInLocation`
- 时区：`go doc time.LoadLocation` ／ `go doc time.FixedZone` ／ `go doc time/tzdata`

---

# 第四幕 · 实操验证

> **本机环境**：`go1.27.1 darwin/arm64`（`GOROOT=/usr/local/Cellar/go/1.27.1/libexec`），Apple M3 Pro，逻辑 CPU 11，macOS 26.6.2（build 25G83）。
> **探针目录**：`/tmp/go-l12/`（模块 `example.com/l12`，`go 1.27`）——共 **18 个包**：**17 个可运行探针**（`p1_pool` / `p2_query_exec` / `p3_injection` / `p4_tx` / `p5_ctx_chain` / `p6_rows_memory` / `p8_client_timeout` / `p9_bodyclose` / `p10_retry` / `p11_monotonic` / `p12_timer` / `p12b_timer_gc` / `p14_layout` / `p15_dao` / `p16_downstream` / `p17_timeutil` / `p18_timerstop`）+ **1 组基准**（`p13_afterbench`），另有 `regen.sh`（一键重跑全部证据）。
> **唯一外部依赖**：`modernc.org/sqlite v1.58.0` —— **纯 Go 实现、不需要 CGO**，所以这份探针在任何装了 Go 的机器上都能跑（**这是本课刻意选它的原因**：`go-sql-driver/mysql` 要连真库、`mattn/go-sqlite3` 要 CGO，都不适合当教学探针）。
> **本幕所有 `console` 块逐字来自** `/tmp/go-l12/ALL_OUTPUT.txt`（**1484 行**，由 `regen.sh` 一次性生成）。
> **证据归档**：探针源码 + 证据文件 + 两个核对脚本已整体归档到仓库内 **`go/playground/lesson-12/`**（**25 个文件**，含一份 `README.md`）—— `/tmp` 会被系统清理，不归档的话"逐字来自证据文件"这句声明就再也无法被验证了。
> ⚠️ **归档不改运行位置口径**：正文里的 `/tmp/go-l12/...` **不是笔误**，探针的规范运行位置仍是 `/tmp/go-l12`。这里说清一点，免得读成"路径不一致就会对不上"：**本课证据文件里其实没有任何绝对路径** —— 对 `ALL_OUTPUT.txt` 全量扫 `/var` `/tmp` `/Users` `/private` **0 命中**，panic 栈式 `.go:NN +0x` 也是 **0 命中**。所以位置差异**不会**让输出对不上。固定口径的理由是另两条：**① 跨课惯例** —— 课 11 的证据里**确实有 23 处** `/tmp/go-l11/*.go:NN`（课 12 是"恰好没有"，不是"不需要"）；**② 文档一致性** —— 本课环境块与各段"探针目录"标注都按该路径叙述。
> **想复跑**：先把归档**拷贝**到 `/tmp/go-l12`，再 `./regen.sh > ALL_OUTPUT.txt 2>&1` —— **别在归档目录里直接跑**：`regen.sh` 会 `cd` 到自己所在目录，且输出用 `>` **覆盖**，而那份 `ALL_OUTPUT.txt` 是交付时冻结的审计快照。只想**核对**数字的话不必拷：归档目录里的 `check_evidence.py` 会**优先读它自己旁边的** `ALL_OUTPUT.txt`，可脱离 `/tmp` 独立复核（已实测：与在 `/tmp` 下跑结果一致，`未直接命中 0 行`）。
>
> ⚠️ **"逐字"的边界（这一点必须说清，否则重跑会对不上）**：下面 **10 类内容每次运行都会变**，课文里保留的是**写作那一轮**的值——
> **① 随机端口号**（`127.0.0.1:5xxxx`，所有探针都用 `:0` 让内核分配）；**② 各种耗时**（`耗时 301ms`、`Close() 调用耗时 26µs`、`耗时约 202ms`）；**③ 基准测试的数字与迭代次数**（`ns/op` / `allocs/op` 每轮都不同）；**④ 堆占用与存活对象数**（`37.56 MB` / `对象 Δ +300020` 这类，每次 GC 时点不同会差 ±0.02 MB，对象数会差几十）；**⑤ 累计分配量**（`47.31 MB` 随 GC 时点与后台活动波动）；**⑥ 单调时钟的纳秒尾部与墙钟时间**（`m=+0.000279585` / `13:49:33.495801` / `1789305255`）；**⑦ 并发调度导致的日志交错顺序**（`p1_pool` 里同一批连接 OPEN/QUERY/CLOSE 的先后**不稳定**）；**⑧ `WaitDuration` / `WaitCount` 的具体值**（`1.453062293s` vs `1.452552208s`）；**⑨ sqlite 临时文件路径与进程内地址**（`/var/folders/...`、`0x50fc454c070`）；**⑩ 环境变量里的代理端口**（`http://127.0.0.1:60249`，沙箱每次会话不同）。
> **除这 10 类之外的每一个字符，都与证据文件严格一致。** 本课用脚本机械化核对过一遍（做法沿用课 10 / 课 11，见 §3.4 的自检清单）。
> **口径说清楚**：**`console` 块内一律逐字保留**（不做四舍五入，重跑时对不上是正常的、且上面已把这 10 类列明）；**叙述性文字**里引用这些易变数值时，会写成约数（如 `≈37.5 MB`、`≈47 MB`）或直接说明"这是实测那一轮的值"。

---

## 实操 1：`database/sql` 连接池

> 对应知识点 1。目标：把「池子怎么建、怎么借、怎么还、什么时候排队」从**会背**变成**看得见**。

### 1.1 先给自己造一个"能看见的数据库"

真正连数据库时，连接池的行为是**不可观测**的 —— 你只看到 SQL 结果，看不到"第几条连接被开了"。所以本课的第一个探针 `p1_pool` 干了一件"很重但很值"的事：

**手写一个假驱动。** 实现 `driver.Driver` / `driver.Conn` / `driver.Stmt` / `driver.Rows` / `driver.Tx` 五个接口，内部只是一个内存里的假表；每次 `OPEN` / `CLOSE` / `QUERY` 都打日志，并用两个计数器记录**当前存活连接数**与**历史峰值**。

```go
sql.Register("fakedb", fakeDriver{})
db, _ := sql.Open("fakedb", "tcp(fake:1)/a")
```

**收益**：连接池的每一个动作都变成了可读的轨迹。**代价**：三百来行样板代码 —— 但只写一次，后面七个场景全部受益。

> 💡 **这个手法值得记住**：**当"系统行为不可观测"时，造一个"能打日志的替身"比自己盯着代码推理有效得多。** 课 10 的 `genReader`、本课的这个假驱动、课 11 的 `ConnState` 回调，是同一个思路。（这也是"接口 + 隐式实现"最后的实战价值：**因为 `database/sql` 面向 `driver.*` 接口编程，我才可能插一个自己的实现进去。**）

### 1.2 七个场景，跑一遍

```console
$ go run ./p1_pool（自写 driver 证明 sql.DB 是池）
```

**场景 A —— `Open` 不连接：**

```console
A) 刚 sql.Open 完：Open 次数 = 0（池是空的，一条连接都没建）
   第一次真正查询之后：Open 次数 = 1
```

**场景 B / C —— 串行的两种极端：**

```console
B) 串行 5 次查询 → Open 次数 = 0，Close 次数 = 0
C) MaxIdleConns=0，串行 5 次查询 → Open 次数 = 5，Close 次数 = 5
```

**场景 D —— 默认配置 + 6 并发（"高峰不设防、低谷留太少"）：**

```console
D) 默认配置，并发 6 次慢查询 → 峰值连接 6，Open 合计 6
   Stats(): Open=2 Idle=2 InUse=0   ← 6 条用完后只留 2 条
```

**场景 E —— `MaxOpenConns=3` + 10 并发（排队可观测）：**

```console
E) MaxOpenConns=3，并发 10 次慢查询 → 存活峰值 = 3
   Stats(): Open=3 InUse=0 Idle=3 WaitCount=7 WaitDuration=1.453062293s
```

**场景 F —— 池满 + ctx 超时：**

```console
F) MaxOpenConns=1，第二条等不到连接 → err = context deadline exceeded
   Stats(): WaitCount=1 WaitDuration=31.0585ms
```

**场景 G —— 空闲超时回收：**

```console
G) MaxIdleTime=60ms，刚查完：Idle=1
   睡 1.5s 后：Idle=0（清理协程把它关了）
   注意：源码里 connectionCleaner 有 const minInterval = time.Second，
   所以即使设 60ms，清理也最快 1 秒一轮。
```

### 1.3 该看哪几个数字（判断标准）

| 你想知道的事 | 看什么 | 判断标准 |
|---|---|---|
| 池子够不够大 | `Stats().WaitCount` | **> 0 就说明池子小了**（有人排过队） |
| 排队严重不严重 | `Stats().WaitDuration / WaitCount` | **接近接口超时 → 立刻加池子或查慢查询** |
| 有没有连接泄漏 | `Stats().InUse` 在"请求都做完了"之后 | **不回落 → 有 `rows` 忘了 `Close`** |
| 池子是不是在反复建连 | `Stats().MaxIdleClosed` / `MaxLifetimeClosed` | 涨得快 → `MaxIdleConns` 太小 or `ConnMaxLifetime` 太短 |
| 有没有连接老化问题 | `ConnMaxLifetime` 是不是**比 LB 空闲超时短** | 不短 → 会周期性出现"僵尸连接"错误 |

> 📌 **生产建议**：把 `db.Stats()` 的四个数字（`WaitCount` / `WaitDuration` / `InUse` / `Idle`）**定时打进监控**。`database/sql` **不会主动告警**，你不看，它就永远沉默。**这和课 11 的结论一致：标准库的默认值是"能用"而不是"安全"，观测手段要自己接。**

### 1.4 动手任务

把 `/tmp/go-l12/p1_pool` 里的假驱动拷出来，做三件事：

1. **加一个场景 H**：`MaxOpenConns=2`、`MaxIdleConns=2`，跑一轮 10 并发后**再跑一轮 10 并发**，观察第二轮的 `Open` 次数比第一轮少多少（这直接量化了"`MaxIdleConns` 该设多大"）。
2. **加一个场景 I**：故意泄漏 3 个 `rows`，把 `MaxOpenConns` 设成 5，看第 4 个请求多久返回 `context deadline exceeded`。
3. **把场景 D 的 `MaxOpenConns` 设成 100、并发改成 100**，观察 `Stats().OpenConnections` —— 这就是"`MaxOpenConns` 零值"在真实压力下的样子。

### 1.5 本实操的自检清单

- [ ] 能说出"为什么 `sql.Open` 完 `Open` 次数是 0"，以及"该调用几次"
- [ ] 能说出 `MaxIdleConns` 的默认值（**2**）和 `MaxOpenConns` 的默认值（**0 = 不限**）
- [ ] 知道设两个参数的**顺序**（先 `MaxOpen` 再 `MaxIdle`）
- [ ] 知道 `ConnMaxIdleTime` 最短的生效周期是 **1 秒**（`minInterval`）
- [ ] 能说出"池子被抽干"的两种成因（每次请求 `Open`+`Close` / 忘了 `rows.Close()`）
- [ ] 知道 `QueryRow` **不返回 error**，错误在 `Scan` 里
- [ ] 知道判 `ErrNoRows` **必须放在 `err != nil` 之前**
- [ ] 知道参数化**不是**"更安全的拼接"，而是**另一条协议通道**
- [ ] 知道事务**绑定一条连接**，且语句报错**不会**自动回滚
- [ ] 能画出"客户端断开 → `r.Context()` → `QueryRowContext` → 查询中止"这条链路，并说出它的前提（**驱动要支持 ctx 取消**）

---

## 实操 2：`http.Client`

> 对应知识点 2。目标：把「超时 / 复用 / 池子参数 / 重试」从**背下来**变成**量出来**。

### 2.1 默认值到底长什么样（两行命令）

```console
$ go run ./p8_client_timeout（默认无超时 / Timeout 覆盖读 body / DefaultTransport 实参 / 代理）
```

**要看的三个数字：**

```console
   DefaultClient.Timeout = 0s
   耗时 2.003s，body="慢响应终于来了" ← 硬等了 2 秒，没人拦得住
   MaxIdleConnsPerHost = 0 ← 未设置，所以用常量 2
```

**做法**：把 `DefaultTransport` 断言成 `*http.Transport` 然后**逐字段打印**。这个方法值得抄走 —— 排查"客户端行为不符合预期"时，**第一件事就是把真实生效的配置打出来**，而不是看文档猜。

### 2.2 `Timeout` 覆盖哪几段（看括号里的话）

```console
   耗时 302ms
   err = Get "http://127.0.0.1:51078/slow": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
```
```console
   拿到响应头，耗时 1ms，状态 200 OK
   读 body 时被掐断：读了 18 字节，err = context deadline exceeded (Client.Timeout or context cancellation while reading body)，总耗时 301ms
```

> 📌 **判断标准**：**错误文本末尾的括号就是"卡在哪一段"的答案**。
> - `while awaiting headers` → 卡在**建连或等服务端首字节**
> - `while reading body` → **头已经回来了**，卡在读 body（这一种最危险，因为状态码可能是 200）

### 2.3 连接复用：6 种写法 + 两个阈值

```console
$ go run ./p9_bodyclose（连接复用 6 种写法 + MaxIdleConnsPerHost）
```

```console
A 读到 EOF 再 Close      /small  (4 KiB)                → ✅ 复用了同一条连接
B 不读直接 Close         /small  (4 KiB)                 → ✅ 复用了同一条连接
C 不读直接 Close         /big    (1 MiB)                 → ❌ 没复用（新连接）
D 不读直接 Close         /dribble(128 KiB / 400ms)       → ❌ 没复用（新连接）
E 先 Copy 到 EOF 再 Close /big    (1 MiB)               → ✅ 复用了同一条连接
F 读完再 Close，服务端 Connection: close                    → ❌ 没复用（新连接）
```

**判定方法**：连发两条请求，看第二条的 `httptrace.GotConnInfo.Reused`。**这个手法值得抄走** —— 它是"连接复用"这件事**唯一可靠的观测手段**（数 `netstat` 太脆）。

**两个阈值 + 一个反例：**

```console
G) MaxIdleConnsPerHost 默认 2：并发 5 条 /big（读完整）之后池里留几条
   MaxIdleConnsPerHost=0（=默认 2）   新建 TCP 连接 5 条，服务端仍处于 idle 的连接 2 条
   MaxIdleConnsPerHost=5          新建 TCP 连接 5 条，服务端仍处于 idle 的连接 5 条
```

**⚠️ 这里有一个必须点明的观测方法陷阱**：我第一版想用 `(*http.Transport).IdleConnections()` 来数池子，**这个方法根本不存在**。改成"**在服务端用 `ConnState` 回调统计处于 `http.StateIdle` 的连接**"之后，反而更硬 —— **它证明的是"服务端真的看到了这些空闲连接"**，而不是"客户端自己说它有几条"。

### 2.4 重试：四道闸门逐个验证

```console
$ go run ./p10_retry（重试边界 + MaxConnsPerHost + 复用 Client）
```

```console
1) GET /flaky（前两次 503，第三次 200）：带退避重试
   第 1 次 → 503，退避 81ms 后重试（累计 2ms）
   第 2 次 → 503，退避 185ms 后重试（累计 85ms）
   第 3 次 → 200，放弃重试（累计 272ms）
   最终 body = {"ok":true,"attempt":3}
```
```console
4) Transport.MaxConnsPerHost 把并发连接卡住
   MaxConnsPerHost=0（默认：不限）     6 个并发慢请求，总耗时 203ms，新建连接 6 条，峰值并发连接 6
   MaxConnsPerHost=2            6 个并发慢请求，总耗时 605ms，新建连接 2 条，峰值并发连接 2
```
```console
5) 复用 Client vs 每次都新建 Transport（各 100 次请求）
   共用同一个 Client：服务端新建 TCP 连接 1 条
   每次新建 Client+Transport：服务端新建 TCP 连接 100 条
```

**判断标准**：

| 现象 | 结论 |
|---|---|
| `MaxConnsPerHost=2` 让耗时变成 **3 倍** | 这个参数是"**给自己封顶**"，只在保护下游时用，**必须配合限流一起用** |
| 共用 Client → **1** 条连接 vs 每次新建 → **100** 条 | **`Client` 必须复用**，这是 100 倍的差别 |
| POST 一次就放弃 | **幂等闸门生效** |

> ⚠️ **这里有一个本课实测踩到的"测量陷阱"**：`p10_retry` 第一版跑出来 `MaxConnsPerHost=2` **反而更快**（峰值并发连接显示 0）。根因是**上一轮留下的 `Transport` 还攥着一批暖着的空闲连接** —— 新的一轮直接复用了它们，根本没建连。修法是每轮开始前 `prev.CloseIdleConnections()` 并 sleep 一小段。**教训：测连接池行为时，必须先把上一轮的池子清干净，否则测的是上一轮。**（这条已写进课内。）

### 2.5 动手任务

在 `p16_downstream` 的基础上改：

1. **把 `maxAttempt` 改成 10、`baseDelay` 改成 10 ms**，跑 `/flaky`，观察"总耗时"变成了多少 —— 体会一下"重试次数 × 退避"是怎么把延迟堆上去的。
2. **增加一个 `/breaker` 端点**（连续返回 500），实现一个最简单的**熔断器**：连续失败 N 次后在 M 秒内直接拒绝，不打下游。**这是"重试"的下一站**（课 15 会讲生产可观测时再回收）。
3. **给 `Do` 加一个 `X-Request-Id` 透传**，让重试的每一次尝试带同一个 ID —— 这样上游日志里能看出"这是同一个逻辑请求的第几次尝试"。

### 2.6 本实操的自检清单

- [ ] 能说出默认 Client 的 `Timeout`（**0 = 永不超时**）
- [ ] 能说出 `MaxIdleConnsPerHost` 的零值含义（**0 = 用常量 2**，不是"不限"）
- [ ] 能说出 `MaxIdleConns = 0` 的含义（**不限**）—— 并能说出这两个 0 的区别
- [ ] 知道"不读 body 也能复用"的两个阈值（**256 KiB / 50 ms**）
- [ ] 知道"必须 `Close`"这条**没有例外**
- [ ] 知道读 body 的错误会以 `(Client.Timeout or context cancellation while reading body)` 的形式出现，**且状态码可能已经是 200**
- [ ] 知道 `http.Client` **不会**被 `http_proxy` 带到 localhost（与 `curl` 不同）
- [ ] 能说出重试的四道闸门（**幂等 / 上限 / 退避抖动 / 先看 ctx**）
- [ ] 知道 `4xx` 不该重试

---

## 实操 3：时间与定时器

> 对应知识点 3。目标：把「单调时钟 / 定时器寿命 / 布局串」从**用着心慌**变成**有据可依**。

### 3.1 单调读的观测与丢失（一张表）

```console
$ go run ./p11_monotonic（单调时钟与它的丢失）
```

```console
1) time.Now() 身上带着单调读，t.String() 会把它显示出来
   time.Now()        = 2026-09-13 13:49:33.495801 +0800 CST m=+0.000279585
   t.Round(0)        = 2026-09-13 13:49:33.495801 +0800 CST
   t == t.Round(0)   → false   ← == 连单调读一起比
   t.Equal(t.Round(0)) → true ← Equal 只比“时刻”
```
```console
3) 哪些操作会把单调读丢掉（官方包文档列过）
   Round(0)               → 还有单调读吗：false
   Round(time.Second)     → 还有单调读吗：false
   Truncate(time.Second)  → 还有单调读吗：false
   AddDate(0,0,0)         → 还有单调读吗：false
   UTC()                  → 还有单调读吗：false
   Local()                → 还有单调读吗：false
   In(time.UTC)           → 还有单调读吗：false
   Add(time.Hour)         → 还有单调读吗：true
   JSON 往返                → 还有单调读吗：false
```

**观测方法**：把 `Time` 的**内部状态**用一个辅助函数探出来（本课探针里用的是 `time.Time` 的 `String()` 里有没有 `m=` 前缀，以及 `t == t.Round(0)` 的布尔值来间接判断）。**注意 `m=` 只出现在 `String()` 里**，`Format()` 不提供任何打印单调读的布局 —— 这是官方设计（*"`t.Format` provides no format for it"*）。

### 3.2 定时器的四种构造 + 内存表

```console
$ go run ./p12_timer（Ticker/Timer 的 Stop 与 Reset）
$ go run ./p12b_timer_gc（cap 之谜 + AfterFunc 内存）
```

```console
7) 不 Stop 的 Ticker/Timer 会不会泄漏？Go 1.23 起 GC 能回收未 Stop 的
   基线堆 = 0.24 MB
   300000 个未 Stop 的 Ticker  之后 = 0.24 MB（增量 0.00 MB）
   300000 个未 Stop 的 Timer   之后 = 0.24 MB（增量 0.01 MB）
   300000 个未 Stop 的 AfterFunc 之后 = 37.34 MB（增量 37.11 MB）
   goroutine 数：1 → 1（定时器不需要一个 goroutine 一个）
```

**观测方法**（值得抄走）：每个场景**各跑一个独立进程**，在**新建前和新建后各强制 GC 三次**，然后比 `HeapAlloc` 与 `runtime.MemStats` 的**存活对象数**（`Mallocs - Frees`）。

> 💡 **为什么坚持"独立进程 + 强制 GC 三次"？** 因为本课第一次测出 `AfterFunc` 的 37 MB 时，我**先怀疑是测量误差**（对象被引用着、`time.After` 的 channel 还在被写…）。于是换了三种回调写法、跑了多轮、并放进独立进程逐一验证 —— **结论稳定复现**，才敢写进讲义。**"先怀疑测量方法，再宣布结论"** 是本仓库的一条硬纪律（课 10 的 embed 倍率、课 11 的 JSON 内存数字都吃过这个亏）。

**另外补测了一个"返回值语义"的格子** —— 因为初稿这一段是**照抄老版文档**写的，实测对不上：

```console
$ go run ./p18_timerstop（Timer.Stop 返回值语义：Go 1.23 起「已到期但未接收」仍返回 true）
```

| 情形（`NewTimer` 建的定时器） | `Stop()` 返回 |
|---|---|
| 还没到期 | `true` |
| **已到期、值从未被接收** | **`true`** ← 老文档说 `false`，实测是 `true` |
| 已到期、值已被接收 | `false` |
| 已被 `Stop` 过 | `false` |

**判据是「值有没有被接收过」/「有没有被 `Stop` 过」，不是「有没有到期」。** 详见知识点 3 的 §3.6。

### 3.3 布局串与解析（一屏覆盖最多坑）

```console
$ go run ./p14_layout（布局串 / Parse / 时区 / 时间戳）
```

**最该盯住的三行：**

```console
3) 布局串写错会怎样：Format 不报错，只是原样吐出你的字面量
   "2006-01-02 15:04:05"    → "2026-09-13 13:14:15"
   "YYYY-MM-DD HH:mm:ss"    → "YYYY-MM-DD HH:mm:ss"
```
```console
5) 不带时区的字符串：Parse 当成 UTC，ParseInLocation 按给定位置
   Parse                          → 2026-09-13 13:14:15 UTC  (Unix=1789305255)
   ParseInLocation(time.Local)    → 2026-09-13 13:14:15 CST  (Unix=1789276455)
```
```console
8) Unix 时间戳：秒 / 毫秒 / 纳秒
   ...
   2263-01-01 的 UnixNano          = -9200561673709551616 ← int64 纳秒溢出成负数
```

**判断标准**：

| 现象 | 结论 |
|---|---|
| `Format("YYYY-MM-DD ...")` 返回原串 | **写错布局串不报错** → 布局串必须用常量 + 往返测试 |
| `Parse` 与 `ParseInLocation` 的 `Unix()` 差 28800 | **不带时区时 `Parse` 按 UTC** → 国内业务一律用 `ParseInLocation` |
| `UnixNano` 变负数 | **2262 年的硬墙** → 存绝对时间用 `UnixMilli` / `RFC3339Nano` |

### 3.4 收尾：三条"证据链"级别的做法（建议后续课沿用）

**① 用脚本机械化核对证据链（课 10 首创、课 11 升级、本课沿用）。** 做法：把正文里所有 ```` ```console ```` 块逐行抽出来，**归一化空白**后与 `ALL_OUTPUT.txt` 做集合比对，把"未直接命中"的行**逐类归因清零**。本课的结果：

| 指标 | 数值 |
|---|---|
| 正文 `console` 块数 | **118 个** |
| 正文 `console` 输出行数（非空、非占位） | **653 行** |
| 直接命中证据文件的行 | **653 行**（归一化端口 / 耗时 / 内存量 / 时钟读数后） |
| 结构化省略占位行（`...`，不算输出） | 1 行 |
| 证据文件行数 | **1484 行** |
| **真实残差** | **0 条**（写作与评审过程中被这条脚本抓出的问题见 §3.4 的 ②③） |

> 归一化时被抹平的，就是上面开头列出的 **10 类"每次运行都会变"**的内容（随机端口 / 各种耗时 / 基准数字 / 堆占用与存活对象数 / 累计分配量 / 时钟读数 / 并发日志交错顺序 / `WaitDuration` / sqlite 临时路径与地址 / 代理端口）。**除这 10 类之外，正文每一个字符都与证据文件严格一致。**

**② 这次脚本抓到了什么？**（如实记录，因为"核对了"要能说出核对出了什么）

- **一处"代码与输出对不上"**：知识点 1 的 ④ 示例演示第一版，我把 `p2_query_exec` / `p4_tx` 的输出**贴在了一份新写的 mini DAO 代码下面**。脚本比对不上 → 于是我**真的把那份代码建成 `p15_dao` 跑了一遍**，换成它自己的输出，并把原两组输出降级为"另一组探针的逐字记录"。**这正是"「实测」两个字不能挂在没跑过的项上"那个纪律要抓的东西。**
- **一处"引用了不在证据文件里的输出"**：知识点 2 §2.6 那段"修复前 `尝试 3 次`"的现场，是写作过程中**真的踩到并修掉的 bug**，但 `regen.sh` 跑的是**修复后**的版本 → 已在 `ALL_OUTPUT.txt` 里**补录这一轮的修复前输出**，并在正文标明它来自"修复前"。**结论：凡正文引用的输出，证据文件里必须有对应记录，哪怕是"修复前"的中间态。**
- **一处"并行改同一文件丢改动"**（工具使用层面的教训）：同一份文件上**两个并行编辑**会导致**其中一个被覆盖丢失**（`sync.Mutex` 字段进了、加锁代码没进，`go vet` 也不报错因为字段未使用是合法的）。→ **同一文件的多次修改必须串行执行，并且改完要看一眼关键行是否真的进去了。**
- **四处"版本归属写错了"**（这次是**回查 `$GOROOT/api/*.txt`** 抓出来的，不是脚本抓的）：`DefaultMaxIdleConnsPerHost` / `Transport.MaxIdleConnsPerHost` 初稿写"Go 1.1"、`time.RFC3339` 写"Go 1.1"、`time.AfterFunc` 写"Go 1.21" —— **全部错**：它们从 **Go 1.0** 就在（Go 1.21 新增的是 `context.AfterFunc`，不是 `time` 包的）。根因是**误把 `api/go1.1.txt` 里的重录当成了"1.1 新增"**（Go 1.1 起 api 文件才开始记录常量值，于是所有老常量都被重录了一遍）。**教训：判断某个 API 的引入版本，看它"最早"出现在哪个 api 文件里；`go1.txt` = Go 1.0。**
- **一处"照抄文档导致语义错"**：`Timer.Stop()` 返回 `false` 的判据，初稿抄了老版文档的 *"already **expired** or been stopped"*，写成"两种含义"。**实测发现 Go 1.23 之后"已到期但值没被接收"时 `Stop()` 仍然返回 `true`** → 为此**另建探针 `p18_timerstop`** 把 8 种情形测全（A 组 6 格 + B 组 3 格，见知识点 3 §3.6），并把正文里 3 处相关表述全部改写。**教训：文档里"为兼容而保留的老句子"，要拿它后面的新段落一起读。**

**③ "先怀疑测量方法再宣布结论"，本课的两个正面例子与一个"不结案"的处理：**

- 正面例 1：`p10_retry` 的"`MaxConnsPerHost` 反倒更快" → 查出是**上一轮遗留的暖连接**，修掉之后结论恢复确定性。
- 正面例 2：`p12b` 的 `AfterFunc` 内存 → **换三种回调写法 + 独立进程 + 多轮**，稳定复现才落盘。
- **不结案**：`cap(time.NewTimer().C) == 0` 与源码字面 `make(chan Time, 1)` 的冲突 → **三方（文档 / 官方测试 / 源码）字面不一致**，本课**只记录实测事实 + 官方测试断言**，**机制标注 ⏳ 未查清**，并给出实操建议（"不要写依赖 `cap(timer.C)` 的代码"）。**"不知道"是一个可以接受的结论，编一个解释才是不可接受的。**

### 3.5 本实操的自检清单

- [ ] 能用一句话说清"墙上时钟"和"单调时钟"各回答什么问题
- [ ] 能背出**至少 5 个**会丢单调读的操作
- [ ] 知道"打点粒度 = 误差上界"这个阈值口径
- [ ] 知道 `==` 比三样、`Equal` 只比时刻、map key 要先 `Round(0)`
- [ ] 能说出 `Ticker` 对慢消费者是"丢 tick"而不是排队
- [ ] 知道 `Ticker.Stop()` **不关 channel**，所以 `for range` 不会退出
- [ ] 能说出 `Timer.Stop()` 与 `Timer.Reset()` 返回值**方向相反**
- [ ] 能说出这两个返回值的**判据是"值有没有被接收过"**，而**不是"有没有到期"**（已到期但值没被接收 → `Stop()` 仍返回 `true`）
- [ ] 知道 Go 1.23 起 `Stop` / `Reset` 之后**不用再排空 channel**
- [ ] 知道**只有 `AfterFunc` 未 `Stop` 会持续占内存**
- [ ] 知道 `AfterFunc` 返回的 `Timer.C` 是 `nil`
- [ ] 知道 `After` 在热路径上的成本（≈248 B / 3 allocs）与它"什么时候才值得换"
- [ ] 能说出 `Format` 写错布局串的后果（**不报错、原样输出**）
- [ ] 知道 `Parse` vs `ParseInLocation` 在无时区时差 8 小时
- [ ] 知道两位年的 **69 分界**
- [ ] 知道 `UnixNano` 的 **2262 年溢出**

### 3.6 收尾：把三个实操的探针合并成一张"证据地图"

| 结论 | 探针 | 证据文件段 |
|---|---|---|
| `sql.Open` 不连接、只建池 | `p1_pool` A | §2 |
| 默认 `MaxIdleConns = 2`、`MaxOpenConns = 0`（不限） | `p1_pool` D / E | §2 |
| `ConnMaxIdleTime` 最短生效周期 1 s | `p1_pool` G | §2 |
| `rows` 不关会抽干池子 | `p6_rows_memory` 1) | §2 |
| `sql.ErrNoRows` 的三条边界（未命中 / 类型不匹配 / 聚合函数） | `p2_query_exec` 3–5) | §2 |
| 参数化 vs 拼接（含破坏性注入） | `p3_injection` | §2 |
| 事务绑定连接 / `ErrTxDone` / 语句报错不回滚 | `p4_tx` | §2 |
| **客户端断开 → `r.Context()` → 查询中止** | `p5_ctx_chain` 3a / 3b | §2 |
| 完整 mini DAO（池配置 + CRUD + 事务 + Stats） | `p15_dao` | §2 |
| 默认 Client 无超时 | `p8_client_timeout` 1) | §3 |
| `Timeout` 覆盖读 body（两种错误文案） | `p8_client_timeout` 2) 3) | §3 |
| `DefaultTransport` 全字段 / `MaxIdleConnsPerHost` 走常量 2 | `p8_client_timeout` 5) | §3 |
| 代理不会带走 localhost | `p8_client_timeout` 6) | §3 |
| 连接复用 6 种写法 + 两个阈值（256 KiB / 50 ms） | `p9_bodyclose` A–F | §3 |
| `MaxIdleConnsPerHost` 2 vs 5 的池子形状 | `p9_bodyclose` G | §3 |
| `Close()` 26 µs 返回、排空是异步的 | `p9_bodyclose` H | §3 |
| 幂等闸门 / 上限 / 退避抖动 | `p10_retry` 1–3) | §3 |
| `MaxConnsPerHost` 3 倍代价 | `p10_retry` 4) | §3 |
| 复用 Client 1 条 vs 每次新建 100 条 | `p10_retry` 5) | §3 |
| 生产级下游客户端封装（四道闸门） | `p16_downstream` | §3 |
| 单调读的观测与 9 项丢失清单 | `p11_monotonic` 1) 3) | §4 |
| `Since(start.Truncate(1s))` 多算 | `p11_monotonic` 5)、`p17_timeutil` ④ | §4 |
| `Ticker` 丢 tick / `Stop` 不关 channel | `p12_timer` 2) 5) | §4 |
| `Timer.Stop` / `Reset` 的 `true`/`false` 判据（**是"值有没有被接收过"，不是"有没有到期"**） | `p18_timerstop` A 组 6 格 + B 组 3 格 | §4 |
| `Timer.Stop` / `Reset` 返回值方向相反 | `p12_timer` 3) 4) | §4 |
| 四种构造的 GC 内存表（`AfterFunc` 例外） | `p12_timer` 7)、`p12b_timer_gc` 3) | §4 |
| `cap(timer.C)` 三方不一致 | `p12b_timer_gc` 1) | §4 |
| `After` vs 复用 `Timer` 的基准（248 B / 3 allocs） | `p13_afterbench` | §4 |
| 布局串全表 / 写错不报错 / Parse 错误原文 / 69 分界 / 2262 溢出 | `p14_layout` 1–10) | §4 |
| 定时任务骨架 / `TotalAlloc` 对比 / 时间工具 | `p17_timeutil` ①②③④ | §4 |

---

# 第五幕 · 体系收束

## 知识点 1 收束：`database/sql`

**一句话结构**：`sql.DB` 是**连接池的句柄**（不是连接）→ 池子有**四个旋钮**（默认值全都不生产级）→ `rows` 是**借出去的一条连接**（必须还）→ SQL 必须走**参数通道**（不是拼接）→ 事务是**绑定一条连接的作用域** → `r.Context()` 是**把取消传到数据库的唯一办法**。

| 问 | 答 | 实测 |
|---|---|---|
| `sql.Open` 会连接数据库吗？ | **不会**，只建池子（首次查询才连） | `Open 次数 = 0` → 查询后 `= 1` |
| `sql.Open` 该调用几次？ | **一次**（官方 *"should be called just once"*） | B 例复用同一条连接 |
| `db.Close()` 该 `defer` 在哪？ | **进程退出处**（*"It is rarely necessary to close a DB"*） | — |
| `MaxOpenConns` 默认多少？ | **0 = 不限** | D 例 6 并发 → 6 条连接 |
| `MaxIdleConns` 默认多少？ | **2**（源码 `defaultMaxIdleConns`） | D 例收工只留 2 条 |
| 两个参数的设置顺序？ | **先 `MaxOpen` 再 `MaxIdle`** | 源码里 `MaxIdle` 会被压到 ≤ `MaxOpen` |
| `ConnMaxIdleTime` 设 60 ms 会立刻回收吗？ | **不会**，清理协程最快 1 s 一轮 | G 例 1.5 s 后才 `Idle=0` |
| 池子满了会怎样？ | **阻塞排队**（不是报错） | E 例 `WaitCount=7`、`WaitDuration≈1.45s` |
| 排队能被打断吗？ | **能**，只要传带 deadline 的 ctx | F 例 `context deadline exceeded` |
| 观测池子看哪个？ | **`db.Stats()`** 的四个数字 | E / F 例 |
| `Query` / `Exec` / `QueryRow` 怎么分？ | 有结果集 / 只看影响行数 / 只取一行 | p2 输出 |
| `QueryRow` 会返回 error 吗？ | **不会**，错误推迟到 `Scan` | 官方签名 |
| "记录不存在"怎么判？ | **先判 `ErrNoRows`**（它也是 `err != nil`） | `errors.Is(err, sql.ErrNoRows) = true` |
| "类型不匹配"会报什么？ | 也可能报 **`ErrNoRows`**（SQL 里只是"匹配不到"） | p2 第 5 条 |
| NULL 扫进 `*float64`？ | **直接报错**，用 `sql.Null*` | `converting NULL to float64 is unsupported` |
| `rows` 会自动归还吗？ | **遍历到结束会**；提前 `break`/`return` **不会** | `InUse=0` vs 池被抽干 |
| `rows.Close()` 调两次？ | **幂等**，且不影响 `Rows.Err` | 源码原文 |
| 循环里只判 `Next()` 够吗？ | **不够**，要再查 `rows.Err()` | 官方原文 |
| 怎么防 SQL 注入？ | **参数化**（另一条协议通道，不是转义） | 拼接版删掉全表最后一行 |
| 占位符能用在表名上吗？ | **不能**（那必须是语法） | — |
| 事务占几条连接？ | **一条**（`InUse` 恒为 1） | `Stats().Open=1 InUse=1` |
| 忘了 `Rollback` 会怎样？ | **永久占一条连接** | `MaxOpenConns=1` 时第二个事务超时 |
| 事务里语句报错会自动回滚吗？ | **不会**，且事务还活着 | 报错后仍能写、能读 |
| `defer tx.Rollback()` 提交后报错？ | 报 `ErrTxDone`，**无害**（这正是它的用法） | `errors.Is(err, sql.ErrTxDone) = true` |
| `QueryRowContext` 一定能取消吗？ | **取决于驱动** | 官方：*"Drivers that do not support context cancellation..."* |
| 客户端断开后查询会停吗？ | **会，只要把 `r.Context()` 传下去** | 3a 服务端 `err=context canceled 耗时=400ms` |
| 不传 ctx 呢？ | **查询完整跑完，纯浪费** | 3b 服务端 `err=<nil> 耗时=1.425s` |
| `:memory:` 在同一个 `DB` 里是同一份数据吗？ | **不是**（每条连接一个库） | 并发 4 次：成功 1 次、失败 3 次 |

**一句话**：**`sql.DB` 只用建一次、`rows` 一定要还、池子四个旋钮全要显式设、SQL 全走占位符、事务保证每条路径都有结局、ctx 一路传到最底层。**

---

## 知识点 2 收束：`http.Client`

**一句话结构**：`Client` = **连接池句柄**（复用）→ `Timeout` **覆盖全程**（含读 body）→ `resp.Body` **必关**（大于 256 KiB 或 50 ms 还要读完）→ `Transport` 的 **`0` 有两种含义** → 重试**四道闸门**。

| 问 | 答 | 实测 |
|---|---|---|
| 默认 Client 有超时吗？ | **没有**（`Timeout = 0`） | 2 s 慢响应硬等 2 s |
| `Timeout` 管哪些段？ | **建连 + 重定向 + 读 body** | 两种错误文案 |
| 超时该设多少？ | 内部 RPC **200 ms~1 s**、外部 **2~10 s**、**不大于上游 deadline** | — |
| `Timeout` 和 `ctx` 怎么选？ | **都设**，先到点者生效 | 251 ms（ctx）vs 302 ms（Timeout） |
| `Client` 该复用吗？ | **必须**（*"Clients should be reused"*） | 1 条 vs 100 条连接 |
| `resp.Body` 必须关吗？ | **必须** | 官方原文 |
| 必须读到 EOF 吗？ | **只对"大 body"**（> 256 KiB 或 > 50 ms） | A/B ✅ vs C/D ❌ |
| 阈值是哪两个常量？ | `maxPostCloseReadBytes = 256 << 10`、`maxPostCloseReadTime = 50 ms` | 源码 |
| `Close()` 会阻塞吗？ | **不会**（26 µs 返回，排空在后台） | H 例 |
| 读完了就一定能复用？ | **不**，服务端 `Connection: close` 就不行 | F 例 |
| `TotalAlloc` 该怎么读 body？ | **不判断，统一 `io.Copy(io.Discard, …)` 再 `Close`** | 最稳妥 |
| `MaxIdleConns` 零值？ | **不限** | — |
| `MaxIdleConnsPerHost` 零值？ | **用常量 2** | G 例 2 条 vs 5 条 |
| `MaxConnsPerHost` 零值？ | **不限** | 203 ms vs 605 ms |
| 该调哪个？ | **`MaxIdleConnsPerHost` 调大**（复用够不够）；**`MaxConnsPerHost` 谨慎**（给下游的压力上限） | 阈值见 §2.4 |
| `http_proxy` 会带走 localhost 吗？ | **不会**（源码硬编码豁免回环） | `ProxyFromEnvironment(本地) → <nil>` |
| `curl` 也一样吗？ | **不一样**（`curl` 要 `--noproxy '*'`） | 课 11 + 本课 |
| `net/http` 会自动重试吗？ | **基本不会**，重试是你的事 | — |
| 什么能重试？ | **只有幂等方法**（GET/HEAD/PUT/DELETE/OPTIONS） | GET 3 次 vs POST 1 次 |
| 重试要有上限吗？ | **必须**，否则是放大器 | 一直 503 → 4 次即停 |
| 为什么要有抖动？ | 避免**惊群** | 退避序列每次有随机增量 |
| 重试前还要看什么？ | **`ctx.Err()`** | 本课实测"尝试 3 次" → 修复后 1 次 |
| `4xx` 该重试吗？ | **不该** | 示例只对 `>= 500` 重试 |
| 封装 `Do` 就万能了？ | **有边界**（本课示例把 body 读进内存，大文件场景不适用） | `io.LimitReader(..., 4<<20)` |

**一句话**：**`Client` 复用、`Timeout` 显式设、`Body` 必关（大的还要读完）、`Transport` 的 `0` 有两种含义、重试四道闸门（幂等 / 上限 / 退避抖动 / 先看 ctx）。**

---

## 知识点 3 收束：时间与定时器

**一句话结构**：`Time` = **两块表**（墙钟 + 单调读）→ 一堆操作会**丢单调读**（`Round`/`Truncate`/`In`/`UTC`/`Local`/`AddDate`/JSON）→ 定时器**四种构造、寿命规则不同** → 布局串是**参考时刻模板**（写错静默生效）。

| 问 | 答 | 实测 |
|---|---|---|
| `Time` 里有什么？ | 墙钟 + `Location` 指针 + **单调读（可选）** | `m=+0.000279585` |
| 单调读有什么用？ | **量时长**（不受对时影响；但机器睡眠时会停） | 官方 Monotonic Clocks 一节 |
| 怎么剥掉它？ | **`t = t.Round(0)`**（官方"canonical way"） | — |
| 哪些操作会丢它？ | `Round` / `Truncate` / `AddDate` / `In` / `UTC` / `Local` / JSON 往返 | 9 项里只有 `Add` 保留 |
| 丢了有什么后果？ | 精度被截断；**打点会多算最多一个截断粒度** | `251ms` vs `747ms`；`252ms` vs `1.117s` |
| 该用哪个函数算间隔？ | **`time.Since(t)`**（有快车道） | 源码 `subMono` 分支 |
| 比较时间用什么？ | **`t.Equal(u)`**（`==` 比三样） | `== false` / `Equal true` |
| 能当 map key 吗？ | **能，但存和取都要先 `Round(0)`** | 三次查找两次失败 |
| `Ticker` 慢消费者会怎样？ | **丢 tick / 拉长间隔**，不排队 | 5 ms 周期挂 120 ms → 1 个 |
| `Ticker.Stop()` 关 channel 吗？ | **不关**（为 `Reset`、为防假 tick） | 接收**阻塞** |
| `for range ticker.C` 能退出吗？ | **不能**，要 `select` + `ctx` | — |
| `time.Tick(0)` 会怎样？ | **返回 `nil`**（静默失效） | 官方注释 |
| `NewTicker(0)` 呢？ | **panic** | 官方注释 |
| `Timer.Stop()` 返回 `false`？ | 判据是**值已被接收过 / 已被 `Stop` 过**（**不是"已到期"**） | `p18_timerstop` |
| `Stop` 后读 `t.C`？ | **永久阻塞**（Go 1.23 保证） | 实测 |
| 还要补 `<-t.C` 排空吗？ | **不要了**（Go 1.23 起） | 官方注释 |
| `Timer.Reset()` 返回 `true`？ | **原本还活着**（与 `Stop` 方向相反） | 活跃 `true` / 已到期 `false` |
| 不 `Stop` 会泄漏吗？ | `NewTimer`/`NewTicker`/`After` **不会**；**`AfterFunc` 会** | ≈37.5 MB / 30 万个 |
| `AfterFunc` 的 `C` 是什么？ | **`nil`** | 官方 + 实测 |
| `After` 在热路径贵吗？ | **≈145 ns / 248 B / 3 allocs**；复用 `Timer` 是 **≈92 ns / 0 B / 0 allocs** | 基准 + 20 万次 47 MB |
| 什么时候才值得换成复用？ | 调用频率到"每秒成千上万次"级别 | §3.8 阈值口径 |
| `cap(timer.C)` 是多少？ | **实测 0**，与源码字面 `make(chan Time, 1)` 不一致（⏳ 机制未查清） | 三方证据 |
| 布局串写错会报错吗？ | **`Format` 不报错**，原样输出；`Parse` 会报错 | `"YYYY-MM-DD HH:mm:ss"` |
| 该用字面量还是常量？ | **常量**（`time.DateTime` / 自定义 `const`） | — |
| `Parse` 遇无时区字符串？ | **当 UTC**；用 `ParseInLocation` 按给定位置 | `Unix` 差 28800 |
| 两位年的分界？ | **69**（`>=69` → `19xx`，`<69` → `20xx`） | `68→2068`、`69→1969` |
| 时区名能用吗？ | **尽量用数字偏移**（`CST` 对应多个时区） | 官方建议 |
| `LoadLocation` 一定成功？ | **不一定**（精简镜像没 tzdata） | `unknown time zone` |
| 服务端能用 `time.Local` 吗？ | **最好不用**（容器里常是 UTC） | 用 `FixedZone` / `LoadLocation` |
| `AddDate(0,1,0)` 是"下月同日"吗？ | **不是**（加一个月再规范化）：1/31 → **3/3** | 四组实测 |
| `UnixNano` 能存任意时刻吗？ | **2262 年溢出成负数** | `-9200561673709551616` |
| `Duration.String()` 有"天"吗？ | **没有**，最多到 `h` | `48h` |

**一句话**：**区分"报时"和"量时"（一个用墙钟、一个用单调读，且别让量时的变量碰任何处理函数）；定时器按构造分四种寿命、只有 `AfterFunc` 必须 `Stop`、Go 1.23 起不用再排空；布局串用常量、解析用 `ParseInLocation`、存绝对时间用 `UnixMilli`。**

---

## 小谷的收尾

他三个需求，现在都有答案了：

| 症状 | 根因 | 解法 | 实测依据 |
|------|------|------|---------|
| ① "压测时数据库连接数爆 / 服务卡住" | **A. 每请求 `sql.Open`+`Close`** —— 把进程级的池子做成了请求级；**B. `rows` 忘了 `Close`** —— 连接只借不还 | **进程级一个 `sql.DB`** + **`defer rows.Close()`** + 四个旋钮显式设 | A 例 `Open=0 → 1`；C 例 5 次查询 5 次 OPEN；`rows` 泄漏 2 条 → 第三次查询 `context deadline exceeded` |
| ② "压测时新连接一路涨、QPS 上不去" | `resp.Body` 不关 → 连接不回池；且 `MaxIdleConnsPerHost` 默认只有 **2** | **必关 body**（大的还要读完）+ **显式调大 `MaxIdleConnsPerHost`** + **复用 `Client`** | 1 条 vs 100 条连接；G 例留 2 条 vs 留 5 条 |
| ③ "RSS 一路涨、热路径分配高" | **A. 循环里 `time.After`** 每次 248 B / 3 allocs；**B. 未 `Stop` 的 `AfterFunc`** 持续占内存 | **复用 `Timer`**（`Reset`）+ **`AfterFunc` 必须 `Stop`** | 20 万次 47 MB vs 0 MB；30 万个未 Stop 的 `AfterFunc` ≈37.5 MB |
| ④（顺手发现）"客户端放弃了，服务端还在跑" | handler 里用了裸 `QueryRow`，**没把 `r.Context()` 传下去** | **`db.QueryRowContext(r.Context(), …)`** | 3a 服务端 `err=context canceled 耗时=400ms`（客户端一断就停）；3b 服务端 `err=<nil> 耗时=1.425s`（白跑） |
| ⑤（顺手发现）"下游一抖，我的重试把下游打死了" | 重试**没有幂等闸门 / 没有上限 / 没有抖动**，也**没看 ctx** | 四道闸门：**幂等 / 上限 / 退避抖动 / 先看 `ctx.Err()`** | GET 3 次 vs POST 1 次；一直 503 只打 4 次；"尝试 3 次" → 修复后 1 次 |
| ⑥（顺手发现）"日志里的时间是 `YYYY-MM-DD HH:mm:ss`" | **布局串是从别的语言抄来的**，`Format` 不报错、原样输出 | 布局串**用常量**；解析用 **`ParseInLocation`**；写往返测试 | `→ "YYYY-MM-DD HH:mm:ss"`；`Unix` 差 28800 |
| ⑦（顺手发现）"耗时统计偶尔多算几百毫秒" | 打点的时候**顺手 `Truncate` 了一下 `start`**，单调读丢了 | **"开始时刻"不要被任何函数碰过** | `Since` 251 ms vs `Since(Truncate(1s))` 747 ms（多算 = `start` 落在那一秒里的小数部分，随机，上界 1 s） |

**他现在的自检清单**（课 8 两句 + 课 9 三句 + 课 10 五句 + 课 11 六句 + 本课六句，**共 22 句**；前 16 句与课 11 那份逐字一致，本课只往后追加）：

1. 谁来关这个 channel？（课 8）
2. 交出去的东西，我还在碰吗？（课 8）
3. 超时之后，那个 goroutine 还在跑吗？（课 9）
4. 共享的这块内存，谁在保护它？（课 9）
5. 这个 goroutine 有没有退出路径？（课 9）
6. 这个数据流是 O(文件) 还是 O(缓冲)？（课 10）
7. 我写的 `Read` 循环，是先收数据还是先判 `err`？（课 10）
8. 这个 `cancel` 我在所有路径上都调了吗？（课 10）
9. 我传给下游的 ctx，和上游给我的是同一个吗？（课 10）
10. 我开的每个文件 / 临时文件，关和删都配对了吗？（课 10）
11. **我用的是自己的 mux，还是 `DefaultServeMux`？**（课 11 → 永远用自己的）
12. **我所有的 `w.Header().Set` 都写在第一次写操作之前吗？**（课 11 → 必须）
13. **我的 `http.Server` 里 `ReadHeaderTimeout` 设了吗？**（课 11 → 没设 = 欢迎 Slowloris）
14. **我的请求体有上限吗？——`MaxHeaderBytes` 管不到 body。**（课 11 → `MaxBytesReader`）
15. **我调 `Shutdown` 时用的是新起的 `context.Background()`，并把它的 `deadline exceeded` 当成"不等了"而不是"被打断"吗？**（课 11）
16. **我的 handler 里，有没有把 `context.Context` 放进 struct 字段？**（课 11 → `-race` 见）
17. **这个池子（`sql.DB` / `http.Client`）是进程级的，还是我每次请求都在新建？**（课 12）
18. **借出去的东西（`rows` / `resp.Body`）还了吗？——而且 `resp.Body` 那一条"还"里，还包括"大的要读到 EOF"。**（课 12）
19. **我的 SQL 里有字符串拼接吗？**（课 12）
20. **重试前我问过"这个请求幂等吗""ctx 还活着吗"吗？**（课 12）
21. **我拿来做耗时统计的那个时间变量，途中被人 `Truncate` / `In` / 序列化过吗？**（课 12）
22. **这个布局串是从别的语言抄来的吗？**（课 12）

第 17~22 句，就是本课新增的全部。

## 阶段 4 的进度

```
课 10  io 与 context      ——  数据怎么流、怎么停          ✅ 2026-09-10
课 11  net/http 服务端     ——  怎么把它挂到网上            ✅ 2026-09-10
课 12  数据访问与客户端     ——  怎么存下来 + 怎么访问别人    ✅ 2026-09-13  ★ 本课
────────────────────────────────────────────────────────────
阶段 4 完成：3 / 3 课  →  知识点 36 / 45  →  阶段 4 收官 ✅
```

**下一站是阶段 5《工程化与生产落地》**：课 13《模块、测试与规范》、课 14《性能与诊断》、课 15《构建部署与选型决策》。

**课 12 给阶段 5 埋下的三条线**：

1. **课 13（测试）**：本课的 `p1_pool` 假驱动其实就是"用测试替身控制外部依赖"的手法；而"布局串要写往返测试"（§3.9）会直接变成课 13 的一个练习。
2. **课 14（性能与诊断）**：本课的 `TotalAlloc` 对比（§3.8）就是 `allocs` profile 的入门；`p13_afterbench` 是本课的 benchmark 雏形，课 14 会把它讲成方法论。
3. **课 15（构建部署与选型）**：本课 §3.11 那个"精简镜像里没有 tzdata 导致 `LoadLocation` 失败"会变成"构建产物要考虑什么"的一个真实案例；而"要不要引入 ORM / 连接池库"是选型决策的经典题型。

---

## 📋 速查卡

### 一、`database/sql`

```go
// ① 建池子：进程级一次，四个旋钮全显式设
db, err := sql.Open("driver", dsn)          // 不连接；"should be called just once"
db.SetMaxOpenConns(10)                      // 默认 0 = 不限
db.SetMaxIdleConns(10)                      // 默认 2（先设 MaxOpen 再设它）
db.SetConnMaxLifetime(30 * time.Minute)     // 默认 0 = 不过期（要短于 LB 空闲超时）
db.SetConnMaxIdleTime(5 * time.Minute)      // 默认 0 = 不过期（清理最快 1s 一轮）
_ = db.PingContext(ctx)                     // 想早失败就 Ping 一次
defer db.Close()                            // 进程退出处；"rarely necessary to close"

// ② 写：Exec（不关心结果集）
res, err := db.ExecContext(ctx, `INSERT INTO t (a,b) VALUES (?,?)`, a, b)
id, _ := res.LastInsertId(); n, _ := res.RowsAffected()   // 可靠性由驱动决定

// ③ 查一行：QueryRow（不返回 error！）
err := db.QueryRowContext(ctx, `SELECT a FROM t WHERE id=?`, id).Scan(&a)
switch {
case errors.Is(err, sql.ErrNoRows):   // ★ 必须先判它
case err != nil:
default:
}

// ④ 查多行：Query + defer Close + 循环后查 Err
rows, err := db.QueryContext(ctx, `SELECT a FROM t WHERE k=?`, k)
if err != nil { return err }
defer rows.Close()                     // ★ 遍历之前注册
for rows.Next() {
	if err := rows.Scan(&a); err != nil { return err }
}
if err := rows.Err(); err != nil { return err }   // ★ 别忘

// ⑤ NULL → Go：用 sql.Null*
var amount sql.NullFloat64
_ = rows.Scan(&id, &sku, &amount)      // if amount.Valid { amount.Float64 }

// ⑥ 事务：defer Rollback + 显式 Commit
tx, err := db.BeginTx(ctx, nil)
if err != nil { return err }
defer tx.Rollback()                    // 幂等；提交后只返回 sql.ErrTxDone
if _, err := tx.ExecContext(ctx, `UPDATE ...`); err != nil { return err }
return tx.Commit()

// ⑦ 观测（唯一入口）
s := db.Stats()   // OpenConnections / InUse / Idle / WaitCount / WaitDuration / MaxIdleClosed
```

**一句话坑表**：`Open` 不连接 | 池子是进程级 | `rows` 必须还 | `QueryRow` 无 error | 先判 `ErrNoRows` | NULL 要 `Null*` | 参数化不是转义 | 事务绑连接 | 语句报错不回滚 | ctx 要传到底（且依赖驱动支持）。

### 二、`http.Client`

```go
// ① 一个进程一个 Client，Transport 参数显式设
tr := &http.Transport{
	MaxIdleConns:        100,
	MaxIdleConnsPerHost: 10,               // 默认常量 2（0 = 用常量！）
	MaxConnsPerHost:     20,               // 默认 0 = 不限
	IdleConnTimeout:     90 * time.Second,
	TLSHandshakeTimeout: 10 * time.Second,
}
client := &http.Client{Timeout: 2 * time.Second, Transport: tr}   // 默认 Timeout = 0 = 永不超时
defer tr.CloseIdleConnections()            // 发布 / 切流量时清池

// ② 发请求：ctx 做主
req, _ := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
resp, err := client.Do(req)
if err != nil { return err }

// ③ 关 body：小 body 直接关，大 body 先读干
defer resp.Body.Close()
// 或（最稳妥）：_, _ = io.Copy(io.Discard, resp.Body); resp.Body.Close()

// ④ 读数据
b, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))   // ★ 一定要有上限

// ⑤ 重试四道闸门
if idempotent(method) && ctx.Err() == nil && attempt < maxAttempt {
	backoff(ctx, attempt)   // 指数 + 抖动，且 select 里要看 ctx.Done()
}
```

**一句话坑表**：默认无超时 | `Timeout` 含读 body | `Body` 必关 | >256 KiB 或 >50 ms 要读干 | `MaxIdleConnsPerHost` 默认 2 | 两个 `0` 含义相反 | localhost 不走代理 | 只重试幂等 | 上限 + 抖动 + 看 ctx | 4xx 不重试。

### 三、时间与定时器

```go
// ① 量时长：用 Since，且别让 start 碰任何函数
start := time.Now()
// ... 干活（不要 start = start.Truncate(...) / In(loc) / 序列化）
elapsed := time.Since(start)               // 有单调读时走快车道

// ② 比较：用 Equal；要当 key 就先 Round(0)
if a.Equal(b) { }
key := t.Round(0).UTC()                     // 标准做法

// ③ 定时任务骨架
t := time.NewTicker(30 * time.Second)
defer t.Stop()
for {
	select {
	case <-ctx.Done(): return
	case <-t.C:        job()
	}
}

// ④ 单次等待 / 超时
timer := time.NewTimer(d)                   // 复用比 time.After 省 248 B / 3 allocs
defer timer.Stop()
select {
case <-timer.C:
case <-ctx.Done():
}
timer.Reset(d)                              // true = 值还没被接收、也没被 Stop 过
// ★ Stop/Reset 的 true/false 看「值有没有被接收过」，不看「有没有到期」：
//   已到期但值从未接收 → Stop() 仍返回 true（Go 1.23 起，实测见 p18_timerstop）

// ⑤ 延迟执行（可取消）—— ★ 这种必须 Stop
ft := time.AfterFunc(d, func() { ... })
defer ft.Stop()                             // 否则未触发的会被持续持有（实测 ≈123 B/个）
// ft.C 是 nil，不要读它

// ⑥ 格式化 / 解析
const LayoutOrder = "2006-01-02 15:04:05"
s := t.Format(time.DateTime)                // 用常量，别散写字面量
tt, err := time.ParseInLocation(LayoutOrder, s, time.FixedZone("CST", 8*3600))
// ★ 无时区时 Parse 会当 UTC；ParseInLocation 按给定位置
// ★ Format 写错布局串不报错，会原样输出
```

**一句话坑表**：`Round`/`Truncate`/`In`/`UTC`/`Local`/`AddDate`/JSON 丢单调读 | `Ticker` 丢 tick 且 `Stop` 不关 channel | `Timer.Stop`/`Reset` 返回值方向相反（**判据是"值有没有被接收过"，不是"有没有到期"**） | Go 1.23 起不用排空 | **`AfterFunc` 必须 `Stop`** | `After` 热路径 248 B/3 allocs | 布局串写错静默 | `Parse` 无时区算 UTC | 两位年 69 分界 | `UnixNano` 2262 溢出 | `AddDate` 月末回绕。

### 四、本课 API 的版本归属（全部查 `$GOROOT/api/*.txt`，核查于 2026-09）

| API | 版本 |
|---|---|
| `net/http.Client` / `Transport` / `Transport.MaxIdleConnsPerHost` / `DefaultMaxIdleConnsPerHost` | **Go 1.0** |
| `time.AfterFunc` / `time.RFC3339` | **Go 1.0** |
| `database/sql.SetMaxIdleConns` | **Go 1.1** |
| `time.Round` / `Truncate` / `ParseInLocation` / `Timer.Reset` | **Go 1.1** |
| `database/sql.SetMaxOpenConns` | **Go 1.2** |
| `Client.Timeout` / `Transport.TLSHandshakeTimeout` | **Go 1.3** |
| `database/sql.DB.Stats` | **Go 1.5** |
| `database/sql.SetConnMaxLifetime` | **Go 1.6** |
| `Transport.MaxIdleConns` / `IdleConnTimeout` | **Go 1.7** |
| `QueryContext` / `ExecContext` / `QueryRowContext` / `PingContext` / `BeginTx` | **Go 1.8** |
| `time.Until` | **Go 1.8** |
| `Client.CloseIdleConnections` | **Go 1.12** |
| `Transport.ForceAttemptHTTP2` / `NewRequestWithContext` | **Go 1.13** |
| `database/sql.SetConnMaxIdleTime` | **Go 1.15** |
| `Ticker.Reset` | **Go 1.15** |
| `time.DateTime` / `DateOnly` / `TimeOnly` / `Time.Compare` | **Go 1.20** |
| `context.AfterFunc`（**不是 `time.AfterFunc`**） | **Go 1.21** |
| `database/sql` 的连接池实现细节、`http.Client` 的 drain-on-close | **Go 1.27（行为变更，无 API 变化）** |

> ⚠️ **查证方法（两个坑，本课都踩过）**：
> **①** 方法在 api 文件里写作 **`method (*DB) SetMaxOpenConns(int)`**，**不是** `func (DB)…`。用 `func (DB)` 搜会**什么都搜不到**，容易误判成"没这个 API"。正确的查法：`grep -n "method (\*DB) SetMaxOpenConns" $GOROOT/api/go1*.txt`
> **② `api/go1.1.txt` 里出现 ≠ Go 1.1 新增。** Go 1.1 起 api 文件才开始记录**常量的值**（`const Foo = 2`，Go 1.0 记的是 `const Foo ideal-int`），于是**所有老常量都被重录了一遍** —— 这就是 `go1.1.txt`（50454 行）比 `go1.2.txt`（32484 行）还长的原因。**判断引入版本，看它最早出现在哪个文件；`go1.txt` 就是 Go 1.0。**

---

## 🐞 常见误区

> 本表把三个知识点各自的「常见误区」汇总整理并重新表述，**共 82 条**（三个分表分别是 28 ／ 22 ／ 35 条）。
> 用脚本比对过一遍：其中 **30 条与分表原文逐字一致**（这些是三张表里最值得反复看的高频项），其余 52 条是改写或跨知识点补充的。带 ⚠️ 的是"老教材已经过时"或"官方文档与实测不一致"的重点条目。

| # | 误区 | 真相 | 关联 |
|---|------|------|------|
| 1 | `sql.Open` 会连上数据库 | **可能一条连接都不建** | 1 |
| 2 | `sql.Open` 很贵，得自己包一层池 | 它**本身就是池**，`Open` 成本接近零 | 1 |
| 3 | 每次请求 `Open`+`Close` 是好习惯 | 那是**每请求新建一个池子**；官方说"只调一次" | 1 |
| 4 | `sql.DB` 是一条连接 | 是**零条或多条连接的池** | 1 |
| 5 | `MaxOpenConns` 默认有合理值 | **0 = 不限** | 1 |
| 6 | `MaxIdleConns` 默认够用 | **2**，且源码写着"将来可能变" | 1 |
| 7 | 先设 `MaxIdleConns` 再设 `MaxOpenConns` 没关系 | 前者会被**自动压到 ≤ 后者** | 1 |
| 8 | `ConnMaxIdleTime` 设小立刻生效 | 清理协程**最快 1 秒一轮** | 1 |
| 9 | `db.Close()` 该写在每个请求里 | "**rarely necessary to close a DB**" | 1 |
| 10 | `QueryRow` 会返回 error | **不返回**；错误在 `Scan` 里 | 1 |
| 11 | `ErrNoRows` 一定是"没这条记录" | 参数类型不匹配也是它 | 1 |
| 12 | 判 `err != nil` 就报 500 | **必须先判 `ErrNoRows`** | 1 |
| 13 | `rows` 不关 GC 会管 | GC 管得不及时；池子先被抽干 | 1 |
| 14 | 遍历到结束就不需要 `Close` | 是真的，**但提前 `break`/`return` 就不成立** | 1 |
| 15 | 只判 `rows.Next()` 就够 | **必须再查 `rows.Err()`** | 1 |
| 16 | `rows.Close()` 调两次会出错 | **幂等** | 1 |
| 17 | `Scan` 目标个数可以随便给 | 不匹配直接报错 | 1 |
| 18 | NULL 扫进 `*float64` 会变 0 | **直接报错** | 1 |
| 19 | `LastInsertId`/`RowsAffected` 总有意义 | `CREATE TABLE` 返回 `0/0`；可靠性由驱动定 | 1 |
| 20 | 转义引号就能防注入 | **不能**；参数化是另一条协议通道 | 1 |
| 21 | 占位符能用在表名/列名上 | **不能**（那必须是语法） | 1 |
| 22 | 事务里语句报错会自动回滚 | **不会**，事务还活着 | 1 |
| 23 | 事务不占连接 | **绑定一条连接**，`InUse` 恒为 1 | 1 |
| 24 | 忘了 `Rollback` 影响不大 | **永久占一条连接** | 1 |
| 25 | `defer tx.Rollback()` 提交后报错所以不该写 | 报 `ErrTxDone`，**无害** | 1 |
| 26 | 写了 `QueryRowContext` 就能取消 | **取决于驱动** | 1 |
| 27 | `:memory:` 在同一个 `DB` 里是同一份数据 | **每条连接一个独立的库** | 1 |
| 28 | `db.Stats()` 没用 | **它是唯一能看见池子内部的入口** | 1 |
| 29 | `http.Get` 有默认超时 | **没有**，`Timeout = 0` | 2 |
| 30 | `Client.Timeout` 只管到响应头 | **连读 body 也管** | 2 |
| 31 | `Timeout` 和 `ctx` 二选一 | **都设**，先到点者生效 | 2 |
| 32 | 每次调用都新建 `Client` 无所谓 | 等价于**每次新建一个连接池** | 2 |
| 33 | ⚠️ "必须读到 EOF 才能复用连接" | **Go 1.27 起只对"大 body"成立**（>256 KiB 或 >50 ms） | 2 |
| 34 | 超过阈值不读也没事 | 会**直接关掉连接** | 2 |
| 35 | 读完就不用 `Close` | **必须 `Close`** | 2 |
| 36 | `Close()` 会把连接立刻还回池 | **排空是异步的** | 2 |
| 37 | 读完了就一定能复用 | 服务端 `Connection: close` 就不行 | 2 |
| 38 | `MaxIdleConnsPerHost = 0` 表示不限 | **0 表示"用常量 2"** | 2 |
| 39 | `MaxIdleConnsPerHost` 默认够用 | 默认 **2** | 2 |
| 40 | `MaxConnsPerHost` 设小只是"慢一点" | 实测**慢 3 倍** | 2 |
| 41 | 调大 `MaxIdleConnsPerHost` 一定有效 | 还受全局 `MaxIdleConns` 限制 | 2 |
| 42 | `http.Client` 访问 localhost 会被代理带走 | **不会**（源码硬编码豁免回环） | 2 |
| 43 | `curl` 的代理坑和 Go 一样 | **不一样**（`curl` 要 `--noproxy '*'`） | 2 |
| 44 | `net/http` 会自动重试 | **基本不会** | 2 |
| 45 | 所有失败都可以重试 | **只有幂等方法能自动重试** | 2 |
| 46 | 重试不需要上限 | 那是**放大器** | 2 |
| 47 | 退避不需要抖动 | 没抖动 → **惊群** | 2 |
| 48 | 重试循环不用管 `ctx` | **必须管**（本课实测踩过） | 2 |
| 49 | 封装一个 `Do` 就万能 | **有边界**（大文件场景不适用） | 2 |
| 50 | `4xx` 也该重试 | **不该** | 2 |
| 51 | `time.Time` 只存"时刻" | 还带 `Location` + **单调读** | 3 |
| 52 | 打印一样就 `==` | `==` 比三样 | 3 |
| 53 | 比较时间用 `==` | **用 `Equal`** | 3 |
| 54 | `Time` 当 map key 很方便 | 存和取都要先 `Round(0)` | 3 |
| 55 | `Round`/`Truncate`/`In` 只是"改显示" | **永久丢掉单调读**（只有 `Add` 保留） | 3 |
| 56 | 转 JSON 再解析还是"同一个时间" | 时刻对，**单调读没了** | 3 |
| 57 | 打点顺手 `Truncate` 没影响 | 耗时统计**随机多算** | 3 |
| 58 | 单调时钟总反映真实经过时间 | **机器睡眠时它会停** | 3 |
| 59 | `Ticker` 会为慢消费者排队 | **丢 tick 或拉长间隔** | 3 |
| 60 | ⚠️ `Ticker.Stop()` 会关 channel | **不关**（为 `Reset`、为防假 tick） | 3 |
| 61 | `for range ticker.C` 会在 Stop 后退出 | **永远不退出** | 3 |
| 62 | `time.Tick(0)` 会 panic | **返回 `nil`**（静默失效） | 3 |
| 63 | `Timer.Stop()` 返回值不重要 | `false` 有**两种**含义 | 3 |
| 64 | ⚠️ `Stop` 返回 `false` 就必须补 `<-t.C` | **Go 1.23 起不需要** | 3 |
| 65 | `Reset` 和 `Stop` 返回值一样 | **方向相反** | 3 |
| 66 | `Reset` 前必须先排空 | **Go 1.23 起不需要** | 3 |
| 67 | ⚠️ "Go 1.23 起定时器都不用 Stop" | 对三种成立，**`AfterFunc` 不成立** | 3 |
| 68 | `AfterFunc` 的 `Timer` 能读 `C` | **`C` 是 `nil`** | 3 |
| 69 | GC 能回收 = 分配不要钱 | **两件事独立** | 3 |
| 70 | `After` 永远比 `NewTimer` 差 | **只在"热路径 + 通常不响"时才差** | 3 |
| 71 | ⚠️ `cap(time.NewTimer().C)` 是 1 | **实测 0**（与源码字面不一致，⏳ 机制未查清） | 3 |
| 72 | 布局串用 `YYYY-MM-DD` 通用 | **Go 不认，原样输出且不报错** | 3 |
| 73 | 布局串写错会报错 | **`Format` 永不报错** | 3 |
| 74 | `Parse` 和 `ParseInLocation` 差不多 | 无时区时**差 8 小时** | 3 |
| 75 | 带时区名就万事大吉 | `CST` 对应多个时区；**推荐数字偏移** | 3 |
| 76 | 两位年的 69 只是数字 | **它是 `19xx`/`20xx` 的分界** | 3 |
| 77 | `LoadLocation` 一定成功 | 精简镜像**没有 tzdata** | 3 |
| 78 | 服务端可以直接用 `time.Local` | 容器里常是 UTC | 3 |
| 79 | `AddDate(0,1,0)` 是"下月同日" | 1/31 → **3/3** | 3 |
| 80 | `UnixNano` 能存任意时刻 | **2262 年溢出成负数** | 3 |
| 81 | `time.Unix(秒)` 往返不丢精度 | **抹掉纳秒** | 3 |
| 82 | `Duration.String()` 会输出"天" | **永不输出"天"** | 3 |

---

## 🗺️ 一图总结

```mermaid
graph TD
    subgraph A["① database/sql：一个池子 + 一条参数通道"]
        OPEN["sql.Open<br/>只建池不连接<br/>只调一次、极少 Close"]
        POOL["四个旋钮<br/>MaxOpen 0=不限<br/>MaxIdle 默认 2<br/>Lifetime / IdleTime 0=不过期<br/>cleaner 最快 1s 一轮"]
        WAIT["池满 → 排队<br/>必须带 ctx 才能被打断<br/>Stats: WaitCount / WaitDuration"]
        API["三个入口<br/>Query 有结果集<br/>Exec 只看影响行数<br/>QueryRow 无 error、错误在 Scan"]
        ROWS["rows = 借出的连接<br/>defer Close 必写<br/>循环后查 Err<br/>遍历到底才自动归还"]
        INJ["参数化<br/>另一条协议通道<br/>不是转义、不能用在列名"]
        TX["事务<br/>绑定一条连接<br/>defer Rollback 幂等<br/>语句报错不自动回滚"]
        CTX["QueryRowContext(r.Context())<br/>客户端一断 → 查询即停<br/>前提：驱动支持 ctx 取消"]
        OPEN --> POOL --> WAIT --> API --> ROWS
        API --> INJ
        API --> TX
        API --> CTX
    end

    subgraph B["② http.Client：一个池句柄 + 四道重试闸门"]
        CLIENT["Client 零值可用<br/>Timeout=0 永不超时<br/>必须复用，别每次新建"]
        TMO["Timeout 覆盖全程<br/>建连 + 重定向 + 读 body<br/>括号文案指示卡在哪一段"]
        BODY["resp.Body 必关<br/>Go 1.27：关即异步排空<br/>≤256 KiB 且 ≤50 ms<br/>超过阈值必须读到 EOF"]
        TR["Transport<br/>MaxIdleConns 0=不限<br/>MaxIdleConnsPerHost 0=用 2<br/>MaxConnsPerHost 0=不限"]
        PROXY["ProxyFromEnvironment<br/>回环地址自动豁免<br/>curl 则不同"]
        RETRY["重试四道闸门<br/>幂等 / 上限 / 退避抖动<br/>先看 ctx.Err()"]
        CLIENT --> TMO --> BODY
        CLIENT --> TR --> PROXY
        CLIENT --> RETRY
    end

    subgraph C["③ 时间与定时器：两块表 + 四种寿命"]
        TIME["time.Time = 墙钟 + 单调读<br/>== 比三样；用 Equal<br/>map key 先 Round(0)"]
        STRIP["丢单调读的操作<br/>Round/Truncate/In/UTC/Local<br/>AddDate / JSON 往返<br/>只有 Add 保留"]
        SINCE["time.Since 有快车道<br/>打点粒度 = 误差上界"]
        TICK["Ticker<br/>丢 tick 不排队<br/>Stop 不关 channel<br/>要 select + ctx 退出"]
        TIMER["Timer<br/>Stop/Reset 返回值反向<br/>判据是「值是否被接收」<br/>Go 1.23 起不用排空<br/>热路径复用省 248 B/3 allocs"]
        AF["AfterFunc<br/>未 Stop 会持续占内存<br/>C 字段是 nil"]
        LAY["布局串 = 参考时刻模板<br/>写错静默原样输出<br/>Parse 无时区当 UTC<br/>两位年 69 分界<br/>UnixNano 2262 溢出"]
        TIME --> STRIP --> SINCE
        TIME --> TICK --> TIMER --> AF
        TIME --> LAY
    end

    A --> B --> C
    C -.->|"课 13：测试（假驱动 / 布局串往返测试）"| N["阶段 5 工程化与生产落地"]
    B -.->|"课 14：benchmark 与 pprof（TotalAlloc → allocs profile）"| N
    A -.->|"课 15：选型（要不要 ORM / 连接池库）、构建（tzdata）"| N
```

---

## 📝 课后小测

<details>
<summary><b>第 1 题</b>：下面这段 handler 至少有 <b>6 个</b>问题。逐个指出，并说出实测依据（哪一条探针输出能证明它有问题）。</summary>

```go
var db *sql.DB // 全局变量

func getOrder(w http.ResponseWriter, r *http.Request) {
	// ①
	d, err := sql.Open("sqlite", "orders.db")
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	db = d

	id := r.URL.Query().Get("id")

	// ②
	rows, err := db.Query("SELECT id, sku, amount FROM orders WHERE id = " + id)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}

	// ③
	for rows.Next() {
		var o struct {
			ID     int64
			SKU    string
			Amount float64
		}
		if err := rows.Scan(&o.ID, &o.SKU, &o.Amount); err != nil {
			http.Error(w, err.Error(), 500)
			return // ④
		}
		json.NewEncoder(w).Encode(o)
	}

	// ⑤
	// 忘了 rows.Close()

	// ⑥
	// 全程没用 r.Context()
}
```

<details>
<summary><b>参考答案</b></summary>

| # | 位置 | 问题 | 实测依据 |
|---|---|---|---|
| 1 | ① `sql.Open` | **每请求都建一个新池子**；而且赋给全局变量会造成数据竞争 | `p1_pool` A 例：`Open` 完 0 条连接 —— 但它建的**是一个全新的池子**；C 例显示"不保留空闲连接"的形状（5 次查询 5 次 OPEN/CLOSE）。官方：*"the Open function should be called just once"* |
| 2 | ② **字符串拼接 SQL** | **SQL 注入**。`?id=1 OR 1=1` 会返回全表 | `p3_injection`：拼接版 `' OR '1'='1` **命中 2 行**（参数化版命中 0 行）；`DELETE` 场景拼接版删掉全表最后一行 |
| 3 | ② 用 `Query` 而不是 `QueryRow` | 语义错（只要一行却用多行接口），且**没有 `ctx`** | — |
| 4 | ②③ 没传 `ctx` | **客户端断开后查询还继续跑** | `p5_ctx_chain` 3b：服务端 `err=<nil> 耗时=1.425s`（客户端 400 ms 就走了） |
| 5 | ③ `Amount float64` | **`amount` 列若是 NULL 会 `Scan` 报错** | `p2_query_exec` 第 7 条：`converting NULL to float64 is unsupported` |
| 6 | ④ `return` 时未 `Close` | **连接不归还，池子被抽干** | `p6_rows_memory` 1)：两条不关 → 第三次查询 `context deadline exceeded` |
| 7 | ④⑤ 循环里 `Encode` 直接写响应，且**提前 `return`** | 既没有 `Close`，也不会有"遍历到底自动归还" | 同 6 |
| 8 | ⑤ 忘了 `rows.Close()` | 同 6 | 同 6 |
| 9 | ⑤ 没有 `rows.Err()` | `Scan` 之外的迭代错误会被吞掉 | 官方：*"it will suffice to check the result of Rows.Err"* |
| 10 | ③ 循环里直接 `Encode(w)` | 会**多写多个 JSON 对象**（不是合法 JSON），且无法再改状态码 | 课 11：Header 必须在写之前设 |
| 11 | ① 全局 `db` 被赋值 | **数据竞争**（多个请求同时写全局变量） | 课 11 `p13_ctxmiddleware` 的 `-race exit status 66` |
| 12 | 全程没有 pool 参数配置 | 默认 `MaxOpenConns = 0`（不限）→ 高并发打爆数据库 | `p1_pool` D 例：6 并发 → 6 条连接；`MaxIdleConns` 默认 2 |

**正确版本的核心改动**：① 把 `db` 初始化移到 `main`/`init`（进程级一次），加四个 setter；② 用 `QueryRowContext(r.Context(), "… WHERE id = ?", id)`；③ `Amount` 用 `sql.NullFloat64`；④ 用 `switch` 先判 `ErrNoRows`；⑤ 如果要列多行，用 `defer rows.Close()` + 循环后 `rows.Err()`。

</details>
</details>

<details>
<summary><b>第 2 题</b>：某服务用 `http.Get` 调用下游。压测时 QPS 上不去，`netstat` 显示大量新连接。已知：下游响应体平均 800 KB，客户端代码是 <code>resp, _ := http.Get(url); defer resp.Body.Close()</code>。请指出根因，并给出<b>两个</b>独立成立的原因（各用实测数据支持）。</summary>

<details>
<summary><b>参考答案</b></summary>

**根因 1：800 KB > 256 KiB，不读 body 就不复用连接。**

`Go 1.27` 的 `maybeDrainBody` 只愿意在 `Close()` 之后异步排空 **最多 `256 << 10` 字节、最多 `50 ms`**。800 KB 超过了字节上限 → 排空失败 → **连接被直接丢弃**（不是"留着但不可用"，是扔掉）。

实测依据：`p9_bodyclose` 的 C 例（1 MiB，不读直接 `Close`）→ **❌ 没复用**；E 例（先 `io.Copy` 到 EOF 再 `Close`）→ **✅ 复用**。B 例（4 KiB，不读直接 `Close`）→ ✅，说明阈值确实在"大小"上。

**修法**：`_, _ = io.Copy(io.Discard, resp.Body)` 再 `Close()`（或者真读它）。

**根因 2：`MaxIdleConnsPerHost` 默认只有 2。**

即使修好了根因 1，**每主机的空闲连接上限仍然是 2** —— 并发一高，多余的连接用完就被关掉，下一波还要重建。

实测依据：`p9_bodyclose` 的 G 例：并发 5 条、每条都读完 → `MaxIdleConnsPerHost=0`（默认 2）时"服务端仍处于 idle 的连接 **2 条**"；设成 5 时 → **5 条**。

**修法**：`Transport{MaxIdleConnsPerHost: <你对单个下游的常态并发数>}`。

**还有一个应当顺手排掉的"隐藏第三个原因"**：如果代码里是"每次调用都 `http.Get`"（用 `DefaultClient`），那没问题（`DefaultClient` 是复用的）；**但如果它是"每次新建 `&http.Client{}`"** —— 那就是**每次新建一个连接池**。实测：`p10_retry` 5) 共用同一个 `Client` → **1** 条连接；每次新建 → **100** 条（100 次请求）。

**顺带指出题目代码里的另一个问题**：`resp, _ := http.Get(url)` **忽略了 error** —— error 非 nil 时 `resp` 可能是 `nil`，`resp.Body` 会 panic。而且**默认 Client 的 `Timeout = 0`（永不超时）**，必须换成显式的 `&http.Client{Timeout: ...}`。
</details>
</details>

<details>
<summary><b>第 3 题</b>：下面这个"订单超时取消"的 goroutine，跑一周后 RSS 一直涨。请指出问题所在，并说明为什么"官方文档说 Go 1.23 起不 Stop 也没事"在这里<b>不适用</b>。（提示：这一类问题有两处，一处跟内存有关，一处跟"逻辑"有关。）</summary>

```go
func watchOrders(ctx context.Context, orders <-chan Order) {
	for {
		select {
		case <-ctx.Done():
			return
		case o := <-orders:
			// 15 分钟后没支付就取消
			time.AfterFunc(15*time.Minute, func() {
				cancelOrder(o.ID)
			})
		}
	}
}
```

<details>
<summary><b>参考答案</b></summary>

**问题 1（内存）：`AfterFunc` 没有 `Stop`，未触发的定时器会被持续持有。**

官方文档在 `NewTimer` / `NewTicker` / `Tick` 上都写了 *"As of Go 1.23, the garbage collector can recover unreferenced timers, even if they haven't expired or been stopped."* —— 但**本课实测发现 `AfterFunc` 是例外**：

```console
   NewTimer(1h) 未 Stop、不引用                  堆   0.25 →   0.25 MB（Δ  +0.00）  对象 Δ +15
   NewTicker(1h) 未 Stop、不引用                 堆   0.25 →   0.25 MB（Δ  +0.00）  对象 Δ +6
   After(1h) 未接收                            堆   0.25 →   0.25 MB（Δ  +0.00）  对象 Δ +5
   AfterFunc(1h, f) 未 Stop、不引用              堆   0.25 →  37.56 MB（Δ +37.31）  对象 Δ +300020
   AfterFunc(1h, f) 立刻 Stop                 堆  37.56 →  37.56 MB（Δ  +0.00）  对象 Δ +2
```

**30 万个未 `Stop` 的 `AfterFunc` → ≈37.5 MB、30 万个存活对象，GC 三次不回收**（每个约 123 B）。15 分钟在这段代码里是"未触发的定时器"的存活期 —— **高峰期积压的量直接乘以 123 B**。

**修法**：把 `*Timer` 存下来，订单支付/取消时 `Stop()`；或者改用"一个 ticker + 一张到期表"的集中式扫描（**这也是唯一能让你"看到积压了多少"的方案**）。

> ⏳ 顺带说明：**为什么 `AfterFunc` 不能被回收，本课没有查清**（`timers.heap` 是强引用，但为什么另外三种能回收而它不能，源码里没找到确切的一行）。本课按实测结论写，**不猜机制**。

**问题 2（逻辑/内存双重）：每个订单都起一个 15 分钟的定时器，这本身就是不可扩展的。**

即使 `AfterFunc` 能被 GC 回收，"每个订单一个定时器"在订单量大时也是错的：

- 10 万个待支付订单 = 10 万个定时器；
- 每个 `AfterFunc` 到期时会在**自己的 goroutine** 里执行回调（文档：*"calls f in its own goroutine"*）→ 到期时间集中的时候会**瞬间起大量 goroutine**；
- **进程重启后所有定时器都没了**（定时器不是持久化的）→ 用户会发现"重启之后有些订单永远不会被取消"。

**正确做法**：**持久化"到期时间"到数据库**（订单表上加一列 `expire_at`），然后用**一个 `Ticker`**（比如每 30 秒）扫描"`expire_at < now` 且未支付"的订单。这样：内存 O(1)、重启不丢、能观测积压、还能顺便做"分批清理"。

**顺手指出第三个问题**：`case o := <-orders` **没有判 channel 是否已关闭**。channel 关闭后这里会**无限收到零值 `Order{}`**，疯狂起定时器。标准写法是 `case o, ok := <-orders: if !ok { return }`。

**还有第四个（与课 10/11 呼应）**：`cancelOrder` 是个"写数据库"的操作，它**没有 `ctx`**、**没有超时**、**没有错误处理**。如果数据库抖一下，这些 goroutine 会堆积。
</details>
</details>

<details>
<summary><b>第 4 题</b>：某接口耗时统计"偶尔会多出几百毫秒"。代码是：<code>start := time.Now(); ...; cost := time.Since(start)</code>，中间只有几行日志，<b>看不出来哪里动了 start</b>。请说出最可能的原因、给出实测数据，并说明"打点粒度"和"误差上界"的关系。</summary>

<details>
<summary><b>参考答案</b></summary>

**最可能的原因：`start` 被一个"看起来只是格式化/记录"的函数处理过，单调读被丢掉了。**

课内列的"丢单调读的操作"里，**最容易被顺手用掉就是 `Truncate` / `Round` / `In(loc)` / `UTC()` / `Local()` / JSON 往返**。典型场景：为了把耗时按"秒"打点，代码里出现了 `start.Truncate(time.Second)`；或者中间层把 `start` 当成"一个时间对象"塞进了结构化日志（**JSON 序列化就会丢单调读**）。

**实测数据**：

```console
   正常计时 time.Since(start)                 = 251ms
   踩坑计时 time.Since(start.Truncate(1s))     = 747ms ← 多算了 start 的小数秒
   多算的部分 = 496ms（本该为 0）
```
```console
   time.Since(start)                = 252.025459ms
   time.Since(start.Truncate(1s))    = 1.117634s ← 凭空多算了 start 的小数秒
```

**"打点粒度"和"误差上界"的关系**：

> `Since(Truncate(T))` 的误差 = **`start` 在其所在的那个 `T` 区间内已经走过的时间**，取值范围 **`[0, T)`**。
>
> - `Truncate(1s)` → 误差 **0 ~ 1 秒** → 平均多算 **0.5 秒**
> - `Truncate(1ms)` → 误差 **0 ~ 1 ms**
> - `Truncate(1m)` → 误差 **0 ~ 1 分钟**
>
> **所以：截断粒度就是误差上界。** "偶尔多出几百毫秒"完全符合 `Truncate(1s)` 的特征（平均 +500 ms，且**随机** —— 因为 `start` 落在秒内的哪个位置是随机的）。这也解释了"为什么是偶尔"：`start` 恰好接近整秒时误差很小，恰好在半秒附近时误差最大。

**为什么"丢单调读"本身也放大了这个问题**：本来 `Truncate` 之后**没有单调读**了，`Since` 会 fallback 到**墙上时钟相减** —— 于是不仅误差变大，还额外引入了"墙钟可能被 NTP 调整"的风险。

**修法**：
1. **`start` 一旦取出来，到 `Since` 用掉之前，不许传给任何函数**（包括日志、包括格式化）。
2. **要打"秒粒度"的日志，应该截断比较结果（`cost.Truncate(time.Second)`），而不是截断起点。** 顺带记住：`Duration.Truncate` 和 `Time.Truncate` 是两回事 —— 前者是纯整数运算，**不会引入任何误差**（课内实测 `1m31.234s → Truncate(1s) = 1m31s`）。
3. 需要显式剥离单调读时，用官方的规范做法 **`t = t.Round(0)`**，并且**只在你真的需要"可比较的 key"时才剥**。

**顺便**：如果是"跨服务传播"的时间戳（把一个时间塞进 HTTP 头或消息体），**单调读注定会丢**（它只在当前进程内有意义）。所以**跨进程永远不要传"开始时刻"，要传"deadline"或"已耗时"**。
</details>
</details>

<details>
<summary><b>第 5 题</b>：判断下面 5 个说法，对就写"对"，错就写出<b>正确的说法</b>。<br/>
（1）"要把 `resp.Body` 读完才能复用连接。"<br/>
（2）"`Timer.Stop()` 返回 `false`，说明定时器已经响过了。"<br/>
（3）"`sql.Open` 每次调用都会建立一条新连接，所以很慢。"<br/>
（4）"`MaxIdleConnsPerHost = 0` 意味着不限制每主机的空闲连接数。"<br/>
（5）"`time.Parse("2006-01-02 15:04:05", "2026-09-13 13:14:15")` 得到的是北京时间。"</summary>

<details>
<summary><b>参考答案</b></summary>

**（1）错。** 正确说法：**"Go 1.27 起，只要 body 不超过 256 KiB 且在 50 ms 内能读完，`Close()` 就会异步帮你读完并复用连接；超过任一阈值才必须自己读到 EOF。"** 而且**"必须 `Close`"这条没有例外**。

依据：`p9_bodyclose` A（读到 EOF）✅、B（4 KiB 不读直接关）✅、C（1 MiB 不读直接关）❌、D（128 KiB/400 ms 不读直接关）❌；源码 `maxPostCloseReadBytes = 256 << 10`、`maxPostCloseReadTime = 50 * time.Millisecond`、`maybeDrainBody`。

**（2）错。** 正确说法：**"对 `NewTimer` 建的定时器，`Stop()` 返回 `false` 的判据是「值已经被接收过」或「已经被 `Stop` 过」—— `已到期` 本身并不会让它返回 `false`：已到期但值从未被接收时，`Stop()` 仍然返回 `true`（Go 1.23 起的新语义）。而对 `AfterFunc` 建的定时器，`false` 才是真的'回调已经跑出去了、没拦住'。"**

依据：`p18_timerstop` A 组 —— ③（已到期、值未接收 → `true`）vs ④（已到期、值已被接收 → `false`）vs ②（已 `Stop` 过再 `Stop` → `false`）；B 组 ②（`AfterFunc` 回调已跑 → `false`）。补充：`p12_timer` 3) 里那行 `已到期之后再 Stop() → 返回 true（false = 没拦住）`，后半句括号是**探针作者按老语义写的文案**，与实测值 `true` 矛盾 —— 这正是本课新加 `p18_timerstop` 的原因。

**（3）错（两处都错）。** 正确说法：**"`sql.Open` 可能一条连接都不建（只校验参数并建一个池子），所以它本身不慢；但它应该只调用一次 —— 每次调用会新建一个连接池，把池子做成请求级才是问题。"**

依据：`p1_pool` A 例 `Open 次数 = 0`；官方 *"Open may just validate its arguments without creating a connection"* + *"should be called just once"*。

**（4）错。** 正确说法：**"`0` 表示'用默认常量 `DefaultMaxIdleConnsPerHost`'，而那个常量是 `2`。** 注意同一个结构体里 `MaxIdleConns = 0` 才是'不限'。"

依据：`p9_bodyclose` G 例（默认留 2 条、设为 5 时留 5 条）；源码 `const DefaultMaxIdleConnsPerHost = 2` + 字段注释 *"If zero, DefaultMaxIdleConnsPerHost is used"*。

**（5）错。** 正确说法：**"`Parse` 在字符串不带时区信息时会当成 UTC —— 也就是北京时间减 8 小时。国内业务应该用 `ParseInLocation(layout, s, time.FixedZone("CST", 8*3600))`。"**

依据：`p14_layout` 5) —— `Parse` → `Unix=1789305255`，`ParseInLocation` → `Unix=1789276455`，差 **28800** 秒；官方原文 *"In the absence of a time zone indicator, Parse returns a time in UTC."*

</details>

---

## 🚀 下一批接力提示词

> 学完本课后，**复制下面这段文字发给 AI**，即可无缝进入下一课（无需重新描述上下文）：

```
继续学 Go。我的学习档案在 go/00-学习档案.md，
刚学完阶段 4《标准库与网络编程》的课 12《数据访问与客户端》
（知识点：database/sql / http.Client / 时间与定时器），
阶段 4 已完成（36 / 45 知识点，阶段 4 三课收官），
请按大纲进入阶段 5《工程化与生产落地》，讲解课 13《模块、测试与规范》
（知识点：模块与依赖 / 测试 / 静态检查与规范），
第四幕的示例代码必须在本机真实跑通并贴实测输出。
```

---

## 🧭 课程导航

- ⬅️ 上一课：[课 11 · net/http 服务端](lesson-11-nethttp服务端.md)（**同阶段**）
- ➡️ 下一课：[课 13 · 模块、测试与规范](../../5-工程化与生产落地/lessons/lesson-13-模块、测试与规范.md)（**下一阶段 · 阶段 5 开篇**）
- 📚 返回：[课程目录](../../../02-课程目录.md) ｜ [阶段概览](../overview.md) ｜ [学习路径总览](../../../01-学习路径总览.md)
