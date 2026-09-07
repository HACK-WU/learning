# 第 3 课：变量与 Dashboard 组织：一张图服务 N 台机器

> 所属阶段：阶段 1《看得见》｜ 水平：入门 ｜ 本课知识点：Dashboard 与 Panel 的关系、变量入门、Row 与 JSON Model
> 故事情节：主角学会"变形"——从写死一台机器，到下拉框一选就切换；并在课末埋下"共享时间选择器"的伏笔

## 🎯 本课目标

- 解释为什么同一个 dashboard 里的所有图天然时间对齐
- 建一个 Query 类型变量并把它写进 PromQL
- 导出 dashboard 的 JSON，指出变量定义在哪一段

## 知识点导航

| # | 知识点 | 关键点 | 状态 |
|---|--------|--------|------|
| 3.1 | Dashboard 与 Panel 的关系：时间选择器是共享的 | 共享时间范围 / 刷新机制 / 为什么这是下钻的前提 | ✅ 已完成 |
| 3.2 | 变量入门：`$host` 从哪来、怎么注入查询 | Query 类型变量 / 注入语法 / 预览值 | ✅ 已完成 |
| 3.3 | Row 与折叠、面板复用与 JSON Model 初见 | Row 折叠 / JSON Model 结构 / 变量在 JSON 中的位置 | ✅ 已完成 |

---

## 第一幕：起源——从"一台机器一张图"到"一张图看所有机器"

上一课结束时，你有了一个能看的面板：一条 CPU 曲线，带单位、带阈值、带图例。

挺好的。然后现实来了。

你有 3 台机器。按上一课的做法，你需要：

1. 复制这个面板
2. 改里面的查询，把 `instance="grafana-node:9100"` 改成 `instance="grafana-node2:9100"`
3. 再复制一份，改成 `grafana-node3:9100`

3 台机器，3 份面板，3 处要改。

现在把数字换一下：**30 台机器呢？300 台呢？**

更要命的是第二个场景：半夜告警响了，你打开 dashboard，看到有一台机器 CPU 飙到 90%。你盯着屏幕，想看清楚**是哪一台**——但图上只有 20 条挤在一起的曲线，图例里全是 `grafana-node-37:9100` 这样的名字，你得一条条去对。

这两个场景指向同一件事：**"写死"是仪表盘的天花板**。

写死一台机器，你的 dashboard 就永远只能看那一台；写死一个时间范围，它就永远只能看那一段。而运维真正需要的恰恰相反——**同一张图，换个参数就能看不同的东西**。

这一课要解决的就是这件事。我们会学三个东西：

- **时间选择器为什么是共享的**（3.1）：这是"同一时间窗口内对比"能成立的地基
- **变量怎么把写死的部分变成可切换的**（3.2）：这是从玩具走向工具的分界线
- **面板怎么组织、怎么复用**（3.3）：这是让仪表盘能长大的骨架

学完这一课，你会得到一个能"变形"的 dashboard：下拉框选主机，图上就显示那一台；勾选多台，图上就同时显示多台；而**所有这些图，看的都是同一段时间**。

---

## 第二幕：认知冲突——"我明明配了时间，为什么这张图的时间是错的"

先给你看一个真实的坑，它比想象中更容易踩。

假设你在 dashboard 上做了两张图：

- 上面一张：最近 **6 小时**的 CPU 曲线，用来看趋势
- 下面一张：只想看最近 **10 分钟**的细节，用来看当下

于是你在下面那张图的面板设置里找到了"Query options → Relative time"，填了 `10m`。保存。

打开 dashboard，时间选择器选"Last 6 hours"。

**下面那张图，真的只显示 10 分钟吗？**

我们去实测。做法是：把这个面板的 `timeFrom` 写进 dashboard，再用 Grafana 自己的查询通道发请求，看后端算出来的**时间步长**——步长是时间窗口的忠实映射，窗口越小步长越小（这一点我们在下面第四幕会先标定）。

```bash
# 面板 B 设置 timeFrom='10m'，dashboard 窗口为 6h
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l03-cal.sh"
```

结果：

```
### 标定：固定 maxDataPoints=1000 / intervalMs=1000，只改请求窗口 ###
      窗口 |  calculatedMinStep
--------------------------------
      5m   |            1000 ms
     10m   |            1000 ms
      1h   |            5000 ms
      6h   |           20000 ms
     24h   |           60000 ms

### 用探针检验 timeFrom：dashboard 窗口 6h，B 声明 timeFrom='10m' ###
  A（跟随 dashboard，窗口 6h）      step = 20000 ms
  B（timeFrom='10m' 期望窗口 10m）  step = 20000 ms
  10m 窗口的基准 step 应为 = 1000 ms
```

**B 的步长是 20000 ms，和 A 一模一样，而不是 10m 窗口该有的 1000 ms。**

也就是说：**后端根本没理 `timeFrom`，B 查的还是完整的 6 小时。**

那 `timeFrom` 存到哪去了？我们直查数据库：

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l03-timefrom-tri.sh"
```

```
【手法 A】把 timeFrom 写进真实 dashboard，再从 API 读回来
  panel[1] title='跟随 dashboard 6h'  timeFrom = <未设置>
  panel[2] title='覆写为 10m'          timeFrom = 10m
  → timeFrom 确实被持久化到 dashboard JSON 里（存在性确认）
```

配置**存进去了**，但后端查询时没用它。

（停一停。这个现象值得你想一想：一个"存得进去但不生效"的配置，通常意味着什么？）

答案是：**它被另一层消费了，而不是被查询层消费。**

`timeFrom` 是**前端渲染层**的概念。前端在计算"这一帧该画多宽"时会读取它、把面板的 X 轴裁剪到 10 分钟；但**后端真正去 Prometheus 取数时，用的是 dashboard 级的时间窗**。

这就是本课要讲的第一个核心认知，而且它比 `timeFrom` 本身重要得多：

> **Grafana 里有两套"时间"：一套是 dashboard 级的、所有面板共享的取数窗口；另一套是面板级的、只影响显示的裁剪。**
> 你以为自己在改"查询范围"，其实改的常常只是"显示范围"。

区分这两者，是后面课 9（从指标下钻到日志）能成立的前提——如果时间不是共享的，你在指标图上点一个时间点，跳到日志系统时就得重新手工对齐时间戳，那正是我们故事开头要消灭的痛点。

---

## 第三幕：层层揭示

### 知识点 3.1：Dashboard 与 Panel 的关系——时间选择器是共享的

#### 一句话定义

Dashboard 是一个**容器与上下文提供者**，Panel 是容器里的**一个查询 + 一种画法**；时间范围、刷新频率、变量值都由 Dashboard 统一持有，Panel 只是按这个上下文去取数并画出来。

#### 直觉建立

把 Dashboard 想成**一张考卷**，Panel 是考卷上的**一道道题**：

- 考卷上写着"考试时间：90 分钟"——这是**所有题目共享**的，不会有一道题单独说"我只给 5 分钟"
- 每道题有自己的题型（选择 / 填空 / 计算）——对应 Panel 的 type（timeseries / stat / table）
- 你把考卷上的时间从 90 分钟改成 60 分钟，**所有题的可用时间一起变**

但这个类比有个必须点明的地方：

> ⚠️ **类比的失效边界**：真实的考卷上，每道题可以额外标注"建议用时 5 分钟"。Grafana 里也有这个东西，就是第二幕那个 `timeFrom`——**但它是"建议"不是"强制"**。它只影响这道题**显示**多宽，不影响它实际**取数**的窗口。把"建议用时"当成"实际用时"，是这一课最常见的误解。
> 而且我们实测过（第四幕实验 A）：**`timeFrom` 存得进去，后端查询时不认**——所以把它当"查询范围"用，会得到一个看着对、实际错的结果。

#### 核心原理

**1）Dashboard 与 Panel 在数据模型上的关系**

一个 dashboard 的 JSON 长这样（简化后）：

```json
{
  "uid": "l03-row",
  "title": "L03-Row与复用",
  "time":     { "from": "now-1h", "to": "now" },     ← 时间范围，dashboard 级
  "templating": { "list": [ ...变量定义... ] },        ← 变量，dashboard 级
  "panels":   [ ...面板数组... ],                     ← 面板，每个自带查询
  "schemaVersion": 41
}
```

注意 `time` 和 `templating` 都在**顶层**，和 `panels` 平级——它们不属于任何单个面板。

实测确认（第四幕实验 B）：把 `time.from` 从 `now-15m` 改成 `now-6h`，读回来整个 dashboard 的时间范围就变了，而**没有任何一个面板需要改动**。

**2）时间是怎么从选择器流到每一条查询的**

```
你点"Last 6 hours"
      ↓
前端把 "now-6h" 解析成绝对毫秒 from / to
      ↓
一次 HTTP 请求里，把这个 from / to 带给【所有】面板的查询
      ↓
Prometheus 按同一个窗口返回数据
      ↓
每张图画的都是同一段时间
```

关键点在第三步：**是一次请求带着一个时间窗，发给所有面板**，不是每个面板各发一次、各带各的时间。

这一点我们用探针抓到了实锤。做法是临时把数据源指向一个"记录型"服务，把 Grafana 后端真正发出的 HTTP 报文抓下来看：

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l03-sniff3.sh"
```

```
--- ① expr 含 $host，不传 scopedVars ---
  POST /api/v1/query
     body = query=up%7Binstance%3D%22%24host%22%7D&time=1788511848.075
                                    ↑ %24 = $，原样发出

--- ③ expr 含 $__rate_interval（内置） ---
  POST /api/v1/query
     body = query=rate%28prometheus_http_requests_total%5B1m0s%5D%29&time=...
                                                          ↑ 已被替换成 1m0s
```

这个抓包同时证明了两件事（后者是 3.2 的核心，先记下）：`$__rate_interval` 这种**内置时间变量在后端替换**，而 `$host` 这种**自定义变量原样透传到了数据源**。

**3）一个关键判据：步长是时间窗口的"影子"**

Grafana 会自动计算查询步长（step），规则是"让数据点数量不超过 maxDataPoints"。所以：

**窗口越大 → 步长越大。**

我们把它标定出来（第四幕实验 A 的标定表）：

| 请求窗口 | calculatedMinStep |
|---|---|
| 5m | 1s |
| 10m | 1s |
| 1h | 5s |
| 6h | 20s |
| 24h | 60s |

有了这张表，**步长就成了一个探针**：看到步长，就能反推后端实际用了多大的窗口。第二幕那个 `timeFrom` 实验，正是靠它判定的。

#### 示例演示

建一个含 3 个面板的 dashboard，验证它们共享时间：

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l03-timequery.sh"
```

```
=== 一次 HTTP 请求里三个查询的 executedQueryString ===
  refId=A  step=300000
  refId=B  step=300000
  refId=C  step=300000
```

三个 refId，同一个步长——因为它们拿到的是同一个时间窗。

#### 常见误区

**误区 1：以为面板级的"Relative time"能缩小查询范围**

就是第二幕那个坑。它只裁剪显示，不改取数窗口。要真缩小范围，要么改 dashboard 的时间选择器，要么在 PromQL 里写死范围。

**误区 2：以为每个面板各查各的时间**

不是。时间窗是 dashboard 统一下发的。所谓"面板级时间覆写"是个显示层概念。

**误区 3：以为 Grafana 会把 `now-6h` 原样发给 Prometheus**

不会。前端会先把相对时间解析成**绝对毫秒**再下发。所以你在 Prometheus 的查询日志里看到的永远是数字时间戳，不是 `now-6h`。

#### 一句话记住

**时间选择器在考卷上，不在题目上——所有题共用同一个钟；面板上的"相对时间"只是建议用时，不是真的给这道题加钟。**

---

### 知识点 3.2：变量入门——`$host` 从哪来、怎么注入查询

#### 一句话定义

变量是 Dashboard 级的一个**命名占位符**，它的候选值由一条查询（或其他来源）动态产生，在**渲染时**被替换进面板的 PromQL 里。

#### 直觉建立

把变量想成**遥控器上的"输入源"按钮**：

- 电视（面板）本身不关心信号来自机顶盒还是游戏机，它只管显示
- 你按下"HDMI 1"，电视就切换到机顶盒的画面
- **你换的是输入，不是换电视**

对应到 Grafana：

- 面板里的 PromQL 写 `$host`，就像电视上的"HDMI 1"这个插孔标签
- 你在下拉框选 `grafana-node2:9100`，就像把机顶盒插到那个口上
- 面板还是那个面板，**一个都没复制**

> ⚠️ **类比的失效边界**：遥控器切换输入，电视内部的电路确实会切到另一路物理信号；但 Grafana 的变量替换是**纯文本替换**——它把 `$host` 这几个字符替换成你选的字符串，然后把替换后的整条 PromQL 发给 Prometheus。
> **Prometheus 从头到尾不知道"变量"这回事。** 这个区别很重要：意味着**替换出来的东西必须是合法的 PromQL**，否则报错会出现在 PromQL 解析层，而不是"变量层"。多值场景（下面误区 2）是这里最容易翻车的地方。

#### 核心原理

**1）变量的三个组成部分**

一个变量 = **名字 + 取值来源 + 当前值**

```json
{
  "name": "host",
  "type": "query",
  "query": "label_values(up{job=\"node\"}, instance)",
  "current": { "text": "grafana-node2:9100", "value": "grafana-node2:9100" },
  "options": [
    { "text": "grafana-node2:9100", "value": "grafana-node2:9100", "selected": true },
    { "text": "grafana-node3:9100", "value": "grafana-node3:9100", "selected": false },
    { "text": "grafana-node:9100",  "value": "grafana-node:9100",  "selected": false }
  ]
}
```

- `name`：在 PromQL 里写成 `$host` 或 `[[host]]`
- `query`：候选值从哪来。`label_values(up{job="node"}, instance)` 的意思是"取 `up{job="node"}` 这个查询结果的 `instance` 标签的所有取值"
- `current`：当前选中哪个

**2）候选值到底从哪来——实测**

`label_values(...)` 不是 PromQL，它是 **Grafana 给数据源插件定义的一套"元数据查询语法"**。它不会被发给 Prometheus。真实的取值来源是 Prometheus 的标签体系：

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l03-exp32.sh"
```

```
【实验 1】变量候选值从哪来：Prometheus 的 instance 标签值
   - grafana-node2:9100
   - grafana-node3:9100
   - grafana-node:9100
  共 3 个 → 这就是 $host 下拉框的选项来源
```

这 3 个值，正是本课的 3 台 node-exporter：

| 容器 | hostname | instance 标签 |
|---|---|---|
| `grafana-node` | `0c3ef738bf68` | `grafana-node:9100` |
| `grafana-node2` | `node-alpha` | `grafana-node2:9100` |
| `grafana-node3` | `node-beta` | `grafana-node3:9100` |

> 📌 **环境说明（重要）**：课 2 交付时环境里**只有 1 台** `grafana-node`（所以课 2 的图只有一条曲线）。本课为了讲"N 台机器"，新增了 `grafana-node2` 和 `grafana-node3`——脚本是 `playground/l03-nodes-up.sh`，它会起两个容器并改写 `prometheus.yml`。
> 如果你隔天重跑本课，**不需要再执行一遍**（容器已存在、配置已改）。若环境被重建，第四幕开头有完整的重建步骤。
> 另外注意：`grafana-node` 的 hostname 显示为一串容器 ID（`0c3ef738bf68`）而不是 `node-xxx`——因为它启动时没有指定 `--hostname`，Docker 默认用容器 ID 前段作为主机名。**这不影响任何实验**（Prometheus 用 `instance` 标签而非 hostname 区分机器），只是三台机器的 `nodename` 看起来不整齐。

**3）注入：替换发生在哪一刻**

这是本课最反直觉、也最有价值的一个发现。

我们用探针抓到了 Grafana 后端真正发给数据源的报文（见 3.1 的抓包），对照结果：

| 变量类型 | 例子 | 后端发出时 |
|---|---|---|
| **内置时间变量** | `$__rate_interval` | ✅ 已替换成 `1m0s` |
| **自定义 dashboard 变量** | `$host` | ❌ 原样发出 `$host` |

也就是说：

> **自定义变量的替换不在 Grafana 后端主查询路径上完成。**
> 后端拿到的是还带着 `$host` 字样的表达式——这也是为什么**直接调 `/api/ds/query` 这个裸接口时，传 `scopedVars` 不会生效**（我们试过放在 query 里、放在顶层 payload 里，都不生效，`$host` 原样到达数据源）。

那到底是谁替换的？答案是**前端渲染层**：浏览器加载 dashboard 时，前端先解析变量、把 `$host` 替换进 PromQL，再把替换后的表达式交给后端去查。

**这条结论的直接推论**（也是排障时最有用的判据）：

1. 面板 JSON 里存的**永远是 `$host` 字面量**，不是替换后的值——我们读回来确认过：`面板 expr = up{instance="$host"}`。
2. 如果你用 API 直接查（脚本、告警规则、Provisioning 预览），**变量不会被替换**，你会拿到 0 条数据。
3. 第 2 点有实测支撑：

```
【实验 2】反证：$host 不替换 → 0 点；替换后 → 有数据
  expr = up{instance="$host"}                   → 帧数=1 点数=0
  expr = up{instance="grafana-node2:9100"}      → 帧数=1 点数=1
```

**这就是"直接调 API 查不出数据"的根因**——不是数据源坏了，是没人替你做替换。

#### 示例演示

建一个带 `$host` 变量的 dashboard：

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l03-exp32.sh"
```

```
【实验 4】变量写进 dashboard JSON 的哪个字段
  保存 HTTP = 200
  dashboard 顶层键: ['id', 'panels', 'schemaVersion', 'templating', 'time', 'title', 'uid', 'version']
  变量 host 定义在 templating.list[0]
    name=host type=query query=label_values(up{job="node"}, instance)
    current={"selected": true, "text": "grafana-node2:9100", "value": "grafana-node2:9100"}
  面板 expr = up{instance="$host"}
  → expr 里仍是 $host 字面量！替换发生在渲染时，不是存储时
```

在 UI 上的操作路径是：Dashboard settings（齿轮图标）→ Variables → New variable

| 字段 | 填什么 |
|---|---|
| Variable type | **Query** |
| Name | `host`（在 PromQL 里就是 `$host`） |
| Data source | 选你的 Prometheus |
| Query | `label_values(up{job="node"}, instance)` |
| Refresh | **On dashboard load**（推荐） |

然后在面板的 PromQL 里写 `up{instance="$host"}`。

#### 常见误区

**误区 1：以为 `$host` 在后端被替换**

不是。见上文实测——自定义变量由**前端**替换，内置时间变量才在后端替换。混用两者去排障会南辕北辙。

**误区 2：多值 / All 场景用 `=` 而不是 `=~`**

这是最经典的一个错误，而且**不报错，只是静默返回 0 条数据**。

当用户勾选多台、或使用 All 时，Grafana 会把 `$host` 展开成 `host1|host2|host3`（用竖线连接）。于是：

- 写成 `up{instance="$host"}` → 展开后是 `up{instance="host1|host2|host3"}` → **精确匹配一个不存在的 instance** → 0 条
- 写成 `up{instance=~"$host"}` → 展开后是 `up{instance=~"host1|host2|host3"}` → **正则匹配，三个都能匹配上** → 3 条

实测：

```
【实验 3】多值 All 的正确写法：正则匹配 =~
  三台全选 up{instance=~"grafana-node2:9100|grafana-n..."} → 帧数=3 点数=3
  错误写法（用 = 不用 =~）                                  → 帧数=1 点数=0  ← 0 点，写错就没数据
```

**口诀：单个值用 `=`，可能多值一律用 `=~`。**

**误区 3：以为变量值会自动更新**

`Refresh` 默认可能是 `Never`。新机器上线后，下拉框里没有它——因为候选值没重新查。生产环境建议设成 **On dashboard load**，或对时效性要求高的设 **On time range change**。

#### 一句话记住

**变量是前端的文本替换器：`$host` 存进 JSON，渲染时才变成真值，Prometheus 从没见过"变量"这东西；多值场景必须用 `=~`，用 `=` 会静默返回 0 条。**

---

### 知识点 3.3：Row 与折叠、面板复用与 JSON Model 初见

#### 一句话定义

Row 是一种**特殊类型的面板**（`type: "row"`），用来给其他面板分组并支持折叠；面板复用（Repeat）让**一个模板面板按变量的每个值复制出 N 份**；而这一切在 JSON Model 里都只是数据。

#### 直觉建立

把 Dashboard 想成**一个书柜**：

- **Row** = 一层隔板，把书分成"技术类""文学类"
- **折叠** = 把这一层的书推进去、只露出隔板标签
- **Repeat** = 一套模板标签，按作者数量自动复制出对应份数，而不是手工抄 N 份

> ⚠️ **类比的失效边界**：书柜的隔板是物理实体，书放在隔板上；但 Grafana 的 Row **本身就是一个 panel**，只是 `type: "row"`。而且折叠时，子面板会被**真的移动位置**——从顶层的 `panels[]` 数组，移到 Row 面板自己的 `panels[]` 里。这不是"视觉上收起来"，是**数据结构的嵌套层级变了**。这一点直接影响你写脚本处理 dashboard JSON。

#### 核心原理

**1）Row 就是一个 panel**

```json
{ "id": 20, "type": "row", "title": "第二行：分主机明细",
  "collapsed": false, "gridPos": { "h": 1, "w": 24, "x": 0, "y": 5 },
  "panels": [] }
```

**2）折叠是"移动"，不是"隐藏"**

实测（第四幕实验 C）：

```
【实验 2】Row 折叠的真实含义：collapsed=true 时，子面板进 row.panels
    [10] type=row     collapsed=False title='第一行：整体视图'    内含 0 个子面板
    [1]  type=stat    collapsed=None  title='机器总数'
    [20] type=row     collapsed=True  title='第二行：分主机明细'  内含 1 个子面板
         └─ 子面板 [2] '$host 的 CPU'
```

展开时，子面板 `[2]` 和其他面板**平级**地在 `dashboard.panels[]` 里；折叠后，它**被挪进**了 `dashboard.panels[20].panels[]`。

**写脚本处理 dashboard JSON 时，必须同时遍历这两处**，否则折叠的面板会被漏掉。

**3）Repeat：一份模板，N 份渲染**

```json
{ "id": 2, "type": "timeseries", "title": "$host 的 CPU",
  "repeat": "host",              ← 按哪个变量复制
  "repeatDirection": "h",        ← h=横向排列，v=纵向
  "maxPerRow": 2,                ← 每行最多几个
  "targets": [ { "expr": "...instance=\"$host\"..." } ] }
```

关键点：**JSON 里只存了 1 份模板**。复制发生在渲染时，份数 = 变量当前值的个数。

实测（第四幕实验 D）：

```
【A】Repeat 的复制份数 = 变量当前值的个数
  变量 host 当前值 = ['grafana-node:9100', 'grafana-node2:9100', 'grafana-node3:9100']
  → 共 3 个值，Repeat 面板会复制出 3 份
  面板 JSON 里只存了 1 份（repeat='host'），复制发生在渲染时

  验证：把变量值减到 2 个
  变量改为 2 个值后：非 row 面板数=1 row 内子面板=1
  → JSON 里始终是 1 个模板面板，复制份数由渲染时变量值个数决定
```

**这就是"一张图服务 N 台机器"的落点**：新增一台机器，你**什么都不用改**——机器出现在变量的候选值里，Repeat 自动多复制一份。

**4）JSON Model 全景**

```
【实验 3】JSON Model 全景：一个 dashboard 由哪几段构成
  顶层字段：
    id               = 1625560610521088
    panels           = 3 个面板
    schemaVersion    = 41
    templating       = 1 个变量
    time             = {"from": "now-1h", "to": "now"}
    title            = 'L03-Row与复用'
    uid              = 'l03-row'
    version          = 2

  变量定义所在路径：dashboard.templating.list[]
  面板定义所在路径：dashboard.panels[]  （折叠时嵌套在 row.panels[]）
```

| 路径 | 放什么 | 本课对应 |
|---|---|---|
| `dashboard.time` | 时间范围 | 3.1 |
| `dashboard.templating.list[]` | **变量定义** | 3.2 |
| `dashboard.panels[]` | 面板（含 row） | 3.3 |
| `dashboard.panels[i].panels[]` | 折叠 row 的子面板 | 3.3 |
| `dashboard.panels[i].targets[]` | 面板的查询 | 3.2 |
| `dashboard.panels[i].repeat` | 复用配置 | 3.3 |

> 📌 **给课 10 埋个伏笔**：`schemaVersion: 41` 和 `version: 2` 是两个不同的东西——前者是**Grafana 的 schema 版本**（升级时可能变），后者是**这个 dashboard 自己的修订号**（每次保存 +1）。课 10 讲 Provisioning 时会再遇到它们。

#### 示例演示

一次跑完 Row / 折叠 / Repeat / JSON Model：

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l03-exp33.sh"
```

#### 常见误区

**误区 1：以为折叠只是"看着收起来了"**

不是，是数据结构变了（子面板被移进 `row.panels[]`）。写脚本导出/迁移 dashboard 时漏掉这层，折叠的面板会静默丢失。

**误区 2：以为 Repeat 会在 JSON 里存 N 份**

不会。存的永远是 1 份模板。**如果你在 JSON 里看到 N 个几乎一样的面板，那多半是上一课那种"手工复制 N 份"的产物**——那正是 Repeat 要消灭的东西。

**误区 3：给 Repeat 面板写死了具体值**

Repeat 的模板里必须引用变量（`$host`），否则复制出来的 N 份内容完全一样，等于白复制。

#### 一句话记住

**Row 是 `type:"row"` 的面板，折叠会把子面板移进它内部；Repeat 只存一份模板、渲染时按变量值复制 N 份；变量在 `templating.list[]`，面板在 `panels[]`（折叠的在 `row.panels[]`）。**

---

## 第四幕：实操验证

> 本幕的每条命令都在本机（WSL Ubuntu 24.04.4 + Docker 29.4.1）真实跑过。
> 环境：Grafana `grafana-lab`(3001) + Prometheus `grafana-prom`(9201) + 3 台 node-exporter(9101/9102/9103)。

### 实验环境准备（本课新增）

上一课只有 1 台 node-exporter，讲不了"N 台机器"。本课先造出 3 台：

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l03-nodes-up.sh"
```

```
=== 5. 三台机器的 nodename（证明是三台不同的机器） ===
[ {"instance": "grafana-node:9100",  "nodename": "0c3ef738bf68"},
  {"instance": "grafana-node3:9100", "nodename": "node-beta"},
  {"instance": "grafana-node2:9100", "nodename": "node-alpha"} ]

=== 6. 变量将要用到的标签基数 ===
-- count(count by (instance) (node_cpu_seconds_total)) → 3
```

⚠️ 这个脚本改了 `prometheus.yml`（加了 2 个 targets）并 `docker restart grafana-prom`。**原因**：`prometheus.yml` 是 bind mount，改文件不会自动重载，而本环境的 Prometheus 没开 `--web.enable-lifecycle`，所以只能重启。

### 实验 A：时间窗口标定 + `timeFrom` 真假判定

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l03-cal.sh"
```

**结论**：步长是时间窗口的忠实映射（5m→1s，24h→60s）；面板 `timeFrom` 存得进去但**后端查询时不认**，仍按 dashboard 窗口计算。

### 实验 B：时间范围是 Dashboard 级字段

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l03-exp34.sh"
```

```
【B】时间选择器共享性：同一次请求里所有查询拿到同一时间窗
  设置 time.from=now-15m   → 读回 dashboard.time = {'from': 'now-15m', 'to': 'now'}
  设置 time.from=now-6h    → 读回 dashboard.time = {'from': 'now-6h', 'to': 'now'}
  → 时间范围是 dashboard 级字段，不属于任何单个面板
```

### 实验 C：Row 折叠会移动子面板

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l03-exp33.sh"
```

**结论**：`collapsed: true` 时子面板从 `dashboard.panels[]` 移入 `row.panels[]`。

### 实验 D：Repeat 只存一份模板

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l03-exp34.sh"
```

**结论**：变量值从 3 个减到 2 个，JSON 里仍只有 1 个模板面板——复制份数由**渲染时**变量值个数决定。

### 实验 E：探针抓包——看后端真正发出去的报文

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l03-sniff3.sh"
```

这是在 Grafana 和数据源之间放一个"记录型代理"，把真实 HTTP 报文抓下来。结论：`$__rate_interval` → `1m0s`（后端替换），`$host` → 原样（前端替换）。

### 实验 F：变量候选值与多值写法

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l03-exp32.sh"
```

```
【实验 3】多值 All 的正确写法：正则匹配 =~
  三台全选（=~）  → 帧数=3 点数=3
  错误写法（=）   → 帧数=1 点数=0
```

### 实验 G：直查数据库——变量和面板存成什么样

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l03-diag-res2.sh"
```

**这是本课意外挖到的一个存储层变化**（详见第五幕"本课的两个意外发现"）。

---

## 第五幕：体系收束

### 本课三个知识点的收束

| 知识点 | 一句话结论 | 最关键的实测 |
|---|---|---|
| 3.1 时间选择器共享 | 时间在 dashboard 级，所有面板共用；面板 `timeFrom` 只改显示 | 步长标定表 + `timeFrom` 后端不认 |
| 3.2 变量 | 前端文本替换，Prometheus 不认识变量；多值必须 `=~` | 探针抓包：`$host` 原样、`$__rate_interval` 已替换 |
| 3.3 Row / Repeat / JSON | Row 是 `type:"row"` 的面板，折叠会移动子面板；Repeat 只存 1 份模板 | 折叠前后 JSON 结构对比 |

### "一张图服务 N 台机器"的完整链路

```
① 3 台 node-exporter 上报指标
        ↓
② Prometheus 打上 instance 标签（3 个不同值）
        ↓
③ 变量 $host 用 label_values 取出这 3 个值 → 下拉框有 3 个选项
        ↓
④ 面板 PromQL 写 up{instance=~"$host"}   ← 注意是 =~
        ↓
⑤ 前端把 $host 替换成选中值 → 发给 Prometheus
        ↓
⑥ 若面板设了 repeat: "host" → 按当前值个数复制 N 份
        ↓
⑦ 新增第 4 台机器：只要它在 Prometheus 里有数据，
   下拉框自动出现选项，勾选即显示 —— 仪表盘零改动
```

第 ⑦ 步就是本课的落点：**从"手工复制 N 份"到"配置驱动"**。

### 本课的两个意外发现

**发现 1：Grafana 13 把 dashboard 从 `dashboard` 表迁到了 `resource` 表**

课 1 我们靠"查 `grafana.db` 的表清单"来论证"不存时序"。本课在做 3.3 时想直查数据库验证 `timeFrom`，结果发现：

```
dashboard 表行数 = 0
```

但 API 明明能读到 dashboard。全库搜索 `l03-timefrom` 这个字符串后：

```
✅ 命中：表 resource 的字段 value
✅ 命中：表 resource_history 的字段 value
```

`resource` 表的结构是 **Kubernetes 风格**的：

```
group=dashboard.grafana.app | resource=dashboards | ns=default | name=l03-timefrom
```

**这对课 1 结论的影响**：课 1 的**核心论断不受影响**——我们重新跑了一遍时序特征检查：

```
当前总表数 = 92 （课 1 记录 92）
时序特征表命中: 无 → 零命中，课 1『不存时序』论断仍成立 ✅
```

但**具体表述需要更新**：课 1 说"dashboard 存在 `dashboard` 表里"，在 13.2.1 上已经不准确了。课 10（Provisioning）会用到这个知识，届时会再展开。

顺带还发现：`resource_history` 有 7 行，**每次保存留一份历史**——这是 dashboard 能回滚的基础，也是课 10 的伏笔。

**发现 2：Grafana 13 的数据源代理路径按 uid 而非 id**

课 2 用的 `/api/datasources/proxy/{id}/...` 在 13.2.1 上返回 **404**：

```
❌ /api/datasources/proxy/1/api/v1/query              → HTTP 404
✅ /api/datasources/proxy/uid/{uid}/api/v1/query       → 3 个 instance
```

符合 Grafana 近几个版本"全面转向 uid"的大方向（课 2 讲过 uid 不可变，正是同一个趋势）。

**环境坑记录**：本环境还遇到一个 gzip 问题——Prometheus 对带 `Accept-Encoding: gzip` 的请求返回 gzip 响应，而本环境的 Grafana 插件未能正确解压，导致**查询返回空 frame 但不报错**。已通过在数据源加 `Accept-Encoding: identity` 请求头绕开（脚本：`l03-fix-gzip.sh`，幂等）。如果你照着做时遇到"面板无数据但不报错"，可以先查这一项。

### 与前后课的连接

| 连接点 | 说明 |
|---|---|
| ← 课 1（1.2 data plane） | 变量替换出的文本，最终仍走同一条 data plane |
| ← 课 2（2.3 第一个 Panel） | 本课给它加了变量，让它从"看一台"变成"看 N 台" |
| → 课 6（6.1–6.3 变量进阶） | 本课只讲了 Query 类型；Custom / Interval / 链式依赖 / 多值深入在课 6 |
| → 课 9（9.2 时间窗对齐下钻） | **共享时间选择器**是指标→日志下钻能自动对齐的前提 |
| → 课 10（10.3 JSON Model） | 本课的 JSON Model 初见，在课 10 会展开成 Dashboard as Code |

### 三个悬念

1. **变量除了 Query 类型，还有什么？** 如果候选值不是来自数据源，而是你手写的几个固定选项呢？（课 6 的 Custom 类型）
2. **变量之间能互相依赖吗？** 比如选了"机房 A"，第二个下拉框只出现机房 A 的机器。（课 6 的链式依赖）
3. **如果我把 dashboard 的 JSON 存进 Git，别人在 UI 上改了怎么办？** （课 10 的 Provisioning 冲突处理）

---

## 📌 本课速览

**3.1 Dashboard 与 Panel**：时间在 dashboard 级（`dashboard.time`），所有面板共享同一个取数窗口。面板的 `timeFrom` 只影响**显示裁剪**，后端查询仍用 dashboard 窗口——实测：窗口 6h 时 A/B 步长同为 20000ms，而 10m 窗口基准应为 1000ms。

**3.2 变量**：`dashboard.templating.list[]` 里的命名占位符。替换发生在**前端渲染时**，面板 JSON 存的永远是 `$host` 字面量；内置时间变量（`$__rate_interval`）才在后端替换。**多值场景必须用 `=~`**，用 `=` 静默返回 0 条。

**3.3 Row 与复用**：Row 是 `type:"row"` 的面板；折叠会把子面板从 `panels[]` **移进** `row.panels[]`；Repeat 只存 1 份模板，渲染时按变量值个数复制 N 份。

**JSON 路径速查**：变量 → `templating.list[]`；面板 → `panels[]`；折叠的子面板 → `panels[i].panels[]`；查询 → `panels[i].targets[]`。

**两个环境事实**：Grafana 13 的 dashboard 存在 `resource` 表（不是 `dashboard` 表）；数据源代理路径是 `/api/datasources/proxy/uid/{uid}/`。

---

## 🔍 本课评审结论

> 评审方式：主 agent 内联（pedagogy + learner 双视角，子 agent 未创建，独立性受限）
> 评审日期：2026-09-04 ｜ **P0 = 0**

| 维度 | 判定 | 证据 |
|---|---|---|
| 五幕结构 | ✅ | 起源→冲突→揭示→验证→收束齐全 |
| 六要素完整性 | ✅ | 脚本核验 3.1/3.2/3.3 各 6 项齐全 |
| 命令真实性 | ✅ | 第四幕 7 个实验全部真跑，脚本均存在 |
| 数字自洽 | ✅ | 步长标定表与 `timeFrom` 判定口径一致 |
| 类比失效边界 | ✅ | 三个知识点各有 ⚠️ 边界块，3.1/3.2 的边界均有实测支撑 |

**评审中判定为脚本缺陷、未改文档的问题（3 项）**：

1. 探针日志写在了容器内的 `/tmp`，而检查读的是宿主机 `/tmp`（路径不共享）→ 改用 bind mount 共享目录后正常。
2. 测试脚本命名为 `bisect.py`，与 Python 标准库 `bisect` 模块冲突导致循环导入 → 重命名后正常。
3. 转发探针未处理 gzip，导致转发后 500 → 解压后再转发即正常。

**评审发现并已修的真缺陷（P1×3）**：

1. 初稿 `timeFrom` 结论仅基于单一接口，证据不足 → 补充"手法 A/B/C"三重取证（API 读回 + 后端查询 + 数据库直查），确认"存得进去但不被查询层消费"。
2. 正文未说明 3 台 node-exporter 的来源，读者隔天重跑会困惑 → 已补环境说明块（含"课 2 结束时只有 1 台"这一前提，以及 `grafana-node` 的 hostname 为何是容器 ID）。
3. 实验环境 Prometheus 未开 lifecycle、改配置需重启 → 已在第四幕显式标注原因。

**结构校验发现并已修的死链（5 条）**：返回根目录的 4 条链接写成 `../../`（两级），在 `lessons/` 目录下应为 `../../../`（三级）；课 4 链接写成 `../2-查得到/`（一级），应为 `../../2-查得到/`（两级）。已全部修正，复验 0 死链。
> 这与课 2 翻的是同一个坑——`lessons/` 距仓库根是三层，写链接时容易少算一级。

**校验脚本自身的缺陷（1 项，已修）**：B3 检查用 `if grep -q '三级写法'` 判空逻辑，未匹配时也报 ✅，导致与 B2 的死链报告自相矛盾。已改为显式判定存在性 + 单独检测两级误写。
> 若不修，下次会误以为"层级正确"而放行真正的死链。

---

## 🧭 课程导航

**上一课**：[第 2 课：第一个面板：从零到看得见](./lesson-02-第一个面板：从零到看得见.md)
**下一课**：[第 4 课：查询编辑器与数据源协议：一次查询的完整旅程](../../2-查得到/lessons/lesson-04-查询编辑器与数据源协议：一次查询的完整旅程.md)

**返回**：[课程目录](../../../02-课程目录.md) ｜ [阶段概览](../overview.md) ｜ [学习路径总览](../../../01-学习路径总览.md) ｜ [学习档案](../../../00-学习档案.md)

---

## 🚀 下一批接力提示词

```
继续学 Grafana。我的学习档案在 grafana/00-学习档案.md，
刚学完阶段 1《看得见》的课 3《变量与 Dashboard 组织：一张图服务 N 台机器》
知识点 3.1（Dashboard 与 Panel 的关系：时间选择器是共享的）、
3.2（变量入门：$host 从哪来、怎么注入查询）、
3.3（Row 与折叠、面板复用与 JSON Model 初见），
请按大纲继续讲解课 4《查询编辑器与数据源协议：一次查询的完整旅程》的知识点
4.1（查询编辑器三态：Code / Builder / Explain）、
4.2（一次查询的完整旅程：前端 → 后端代理 → 数据源）、
4.3（状态码与真实错误的分离：HTTP 400 里的 status 502）。
```
