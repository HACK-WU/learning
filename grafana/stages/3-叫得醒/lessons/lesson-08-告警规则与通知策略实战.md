# 第 8 课：告警规则与通知策略实战

> 所属阶段：阶段 3《叫得醒》｜ 水平：入门 ｜ 本课知识点：规则三要素、通知策略树与静默、分组与抑制
> 故事情节：一百台机器同时挂——你是想收一百条通知，还是一条？

## 🎯 本课目标

- 写一条带 `for` 与 No Data 处理的完整规则，并用 API 验证状态迁移
- 配一棵按标签路由的通知策略树，并加一条静默验证
- 用分组把 N 台机器的告警收敛成一条通知

## 知识点导航

| # | 知识点 | 关键点 | 状态 |
|---|--------|--------|------|
| 8.1 | 告警规则三要素：查询、条件、评估行为 | 查询与 Reduce / 阈值表达式 / 评估组与间隔 | ✅ 已完成 |
| 8.2 | 通知策略树与静默：告警怎么路由到人 | 策略树匹配 / 静默与抑制的区别 / Contact point | ✅ 已完成 |
| 8.3 | 分组与抑制：为什么一条故障只该响一次 | group_by / group_wait / group_interval / repeat_interval | ✅ 已完成 |

---

## 📖 开篇：一个让你凌晨三点崩溃的场景

你是某电商公司的运维。某天凌晨，机房一台核心交换机挂了。

挂在它下面的 **100 台机器**瞬间全部失联。

三秒后，你的手机开始震动。

```
03:00:01  [告警] web-001 失联
03:00:01  [告警] web-002 失联
03:00:01  [告警] web-003 失联
...
03:00:02  [告警] web-100 失联
```

**100 条通知，在同一个瞬间抵达。**

你从床上弹起来，打开手机，在 100 条一模一样的消息里翻找——

**到底哪里坏了？**

你花了 20 分钟才意识到：**这不是 100 个故障，这是 1 个故障的 100 个表现。**

交换机坏了。修交换机就行。

---

这个场景里，Grafana 做了它该做的事——它诚实地报告了"100 台机器失联"。

但它没做的是：**告诉你这 100 件事其实是同一件事。**

这就是本课要解决的问题。

> **本课的核心命题**：告警系统真正的难度，从来不是"让它响"，而是**"让它响得有信息量"**。
>
> 一个只会把所有异常都发出来的系统，等价于一个只会喊"狼来了"的孩子——喊多了，就没人听了。

课 7 我们让告警**会响**。这一课，我们让它**响得对**。

---

## 🧠 8.1 告警规则三要素：查询、条件、评估行为

### 一句话定义

一条 Grafana 告警规则 = **查询（拿什么数据）+ 条件（什么算异常）+ 评估行为（多久看一次、持续多久才告警）**。

三者缺一不可，且**各自独立出错**——查询错了没数据，条件错了永远不触发，评估行为配错了触发得莫名其妙。

### 直觉建立：把告警规则想成"一个定时巡逻的保安"

想象你雇了一个保安，每天定时巡视机房。

| 告警规则概念 | 保安的对应行为 |
|---|---|
| **查询（Query）** | 保安**看哪些仪表**——是看温度计，还是看电表 |
| **条件（Condition）** | **什么算异常**——温度计超过 40 度算异常，还是超过 80 度 |
| **评估行为（Evaluation）** | **多久巡一次**、**异常持续多久才上报** |

现在关键问题来了：

**机房里有 100 台机器，每台都有温度计。保安看完全部 100 个温度计后，他要上报几条？**

- 上报 100 条？—— 那和开篇的故事一样糟糕
- 上报 1 条（"机房温度异常"）？—— 丢失了"是哪台"的信息

**这个"看 100 个仪表、上报几条"的问题，就是 8.1 的核心，也是 8.3 分组的伏笔。**

Grafana 的答案藏在一个叫 **Reduce** 的环节里。

### 核心原理

#### 三要素的完整结构

一条完整的 Grafana 告警规则，在 API 里长这样（本课实测的精简版）：

```python
{
  "uid": "web-down",              # 规则唯一 ID
  "title": "Web 服务宕机",
  "ruleGroup": "production",      # 评估组（决定求值间隔）
  "folderUID": "l08alerts",       # Grafana 13 强制要求
  "orgID": 1,
  "condition": "C",               # ← 用哪个节点的结果做判定
  "data": [                       # ← 三要素的载体：一个节点链
    { "refId": "A", ... },        #   查询节点
    { "refId": "B", ... },        #   Reduce 节点
    { "refId": "C", ... },        #   阈值节点
  ],
  "for": "5m",                    # 评估行为：持续多久
  "noDataState": "NoData",        # 评估行为：没数据怎么办
  "execErrState": "Error",        # 评估行为：查询出错怎么办
}
```

注意 `data` 是一个**数组**——它不是一条查询，而是一条**处理链**。

这条链的终点由 `condition` 指定。本课所有实验里，`condition` 都指向最后一个节点。

#### 要素一：查询（Query）

查询节点负责**拿数据**。它的 `datasourceUid` 指向真实数据源（本课是 Prometheus）。

```python
{
  "refId": "A",
  "relativeTimeRange": {"from": 300, "to": 0},   # 查最近 5 分钟
  "datasourceUid": "afx7x6dx803y8e",             # Prometheus 数据源
  "model": {
    "refId": "A",
    "datasource": {"type": "prometheus", "uid": "afx7x6dx803y8e"},
    "expr": "node_load1",                        # ← PromQL
    "editorMode": "code",
    "legendFormat": "__auto"
  }
}
```

**关键认知**：查询返回的是**时间序列**（可能多条），不是单个数字。

本课实测：

```
$ curl -s 'http://localhost:9201/api/v1/query?query=node_load1'

序列数：3
  grafana-node:9100  = 2.81
  grafana-node3:9100 = 2.81
  grafana-node2:9100 = 2.97
```

**一条查询，返回 3 条序列**（3 台机器各一条）。

这个"1 → 3"的关系，是后面所有复杂度与所有坑的根源。

#### 要素二：条件（Condition）—— Reduce 与阈值

条件负责**把序列变成"是/否"**。它通常拆成两步：**Reduce（降维）+ Threshold（判定）**。

**第一步：Reduce —— 把"一条曲线"压成"一个数字"**

一条时间序列是一串随时间变化的点：`[2.8, 2.9, 3.1, 2.7, ...]`。

Reduce 的作用是把这串点**压成一个数字**。常见的压法（reducer）：

| reducer | 含义 | 适用场景 |
|---|---|---|
| `last` | 取最新一个点 | 看"当前"状态（最常用） |
| `min` / `max` | 取最小 / 最大值 | 看窗口内的极值 |
| `mean` | 取平均值 | 看窗口内的总体水平 |
| `sum` | 求和 | 看总量 |
| `count` | 计数 | 看有多少条序列 |

为什么必须降维？

**因为"是否告警"只能是一个二值判断，而一条曲线不是二值。**

你必须先把"这条曲线长什么样"压缩成"一个数是多少"，才能拿它去比阈值。

```python
{
  "refId": "B",
  "datasourceUid": "-100",        # -100 = Grafana 内置表达式引擎
  "model": {
    "refId": "B",
    "datasource": {"type": "__expr__", "uid": "-100"},
    "type": "reduce",             # ← Reduce 表达式
    "reducer": "last",            # ← 取最新值
    "expression": "A",            # ← 对 A 的结果做 Reduce
    "settings": {"mode": "dropNN"}  # ← 空值处理策略
  }
}
```

**第二步：Threshold —— 拿数字比阈值**

```python
{
  "refId": "C",
  "datasourceUid": "-100",
  "model": {
    "refId": "C",
    "datasource": {"type": "__expr__", "uid": "-100"},
    "type": "threshold",          # ← 阈值表达式
    "expression": "B",            # ← 对 B 的结果做判定
    "conditions": [{
      "type": "query",
      "evaluator": {"params": [0], "type": "gt"}   # ← B > 0
    }]
  }
}
```

`evaluator.type` 支持：`gt`（>）、`lt`（<）、`gte`（>=）、`lte`（<=）、`eq`（==）、`ne`（!=），以及 `within_range` / `outside_range`（区间）。

#### 【重点】Reduce 决定"几条告警"，不只是"什么数字"

这是本课最反直觉、也最重要的一条。

我们做了对照实验：**同一条查询 `node_load1`（3 条序列），只改条件的写法**。

**写法 A：classic_conditions（老式条件，内置 reducer）**

```
A = node_load1          → 3 条序列
B = classic(last > 0)   → 条件判定
```

实测结果：

```
Alertmanager 实例数 = 1
  labels = {"__alert_rule_uid__":"v-cls", "alertname":"v-cls", "grafana_folder":"L08 Alerts"}
                                          ↑ 注意：没有 instance！
```

**写法 B：reduce + threshold（新式，独立 Reduce）**

```
A = node_load1          → 3 条序列
B = reduce(last)        → 降维
C = threshold(> 0)      → 判定
```

实测结果：

```
Alertmanager 实例数 = 3
  labels = {"alertname":"v-red", "instance":"grafana-node:9100",   "job":"node", ...}
  labels = {"alertname":"v-red", "instance":"grafana-node2:9100",  "job":"node", ...}
  labels = {"alertname":"v-red", "instance":"grafana-node3:9100",  "job":"node", ...}
```

**关键差异在 labels**：

| 写法 | 告警实例数 | labels 里有没有 `instance` |
|---|---|---|
| classic_conditions | **1 条** | ❌ 没有 |
| reduce + threshold | **3 条** | ✅ 有 |

**为什么会这样？**

`classic_conditions` 是 Grafana 的**老式条件语法**。它把"降维"和"判定"合并在一个节点里完成，这个合并过程会**丢掉原有的序列标签**。

3 条序列降维后都变成了"一个数字"，且都没有 `instance` 标签——
**Grafana 无法区分它们，只能合并成 1 条告警。**

而独立的 `reduce` 表达式会**保留标签**。3 条序列各自保留自己的 `instance`，于是产生 3 条可区分的告警实例。

> **这一条直接决定了 8.3 的分组能不能生效。**
>
> 如果你用 `classic_conditions`，告警里**没有 `instance` 标签**——
> 那么你在 8.3 里配 `group_by: [instance]` 就是**无效的**，因为根本没有这个标签可分组。
>
> 很多人配完分组发现"怎么还是一条"，根源就在这里。

**本课的建议**：

- 想让**每台机器单独告警** → 用 `reduce + threshold`（保留标签）
- 想让**整体只出一条** → 用 `classic_conditions`，或者用 `reduce` 后再 `sum`

这两种写法不是"新旧之争"，而是**两种截然不同的语义**。选之前先想清楚：你要的是"3 台机器各自告警"，还是"机房整体告警"。

#### 要素三：评估行为（Evaluation）

评估行为回答三个问题：**多久看一次**、**持续多久才算数**、**看不清/看不到怎么办**。

本课实测的规则字段清单：

```
intervalSeconds    = null     ← 注意：规则级设置被忽略了
for                = "0s"
keep_firing_for    = "0s"
isPaused           = false
ruleGroup          = "l08-g1"
folderUID          = "l08alerts"
condition          = "B"
noDataState        = "NoData"
execErrState       = "Error"
orgID              = 1
record             = null
```

**问题一：多久看一次（求值间隔）**

我们在规则里写了 `intervalSeconds: 20`，然后回读：

```
规则级回读 intervalSeconds = null     ← 被忽略了
组级回读：group=g-prov20  interval=1m  ← 还是 1 分钟
```

**结论：求值间隔由「评估组」决定，不由单条规则决定。**

这在课 7 已经埋过伏笔——课 7 实测 `for=20s` 配 `interval=60s` 时花了 60 秒才 firing，就是因为 `for` 会被求值粒度稀释。

**同一组内的所有规则共享同一个间隔。** 这是设计上的取舍：

- 好处：同组规则对齐时间点求值，可以一起进入通知分组
- 代价：你想让某条规则"更灵敏"，不能只改它自己，得把它**挪到另一个组**

**问题二：持续多久才算数（`for`）**

这个课 7 已经讲透，这里只做一句话回顾：

> `for` 是「**连续**满足多久」，不是「延迟多久通知」。
> 实际告警延迟 = ⌈for / interval⌉ × interval。

**问题三：看不清/看不到怎么办（`noDataState` / `execErrState`）**

课 7 也已讲透，这里补一条课 7 之后的新认识：

> **`up` 类指标看阈值，业务指标看 No Data。**
>
> 真实宕机时 Prometheus 返回 `up=0`（序列还在），走的是 Alerting 分支，`noDataState` 根本不触发。
> 只有业务指标（如零流量导致序列消失）才需要配 `noDataState`。

**问题四：恢复后再响一会儿（`keep_firing_for`）**

这是课 7 留下的悬念之一。课 7 实测中 ruler API 返回了 `keep_firing_for: "0s"`，但没动它。

`keep_firing_for` 是 `for` 的**反向配置**：

| 参数 | 作用时机 | 含义 |
|---|---|---|
| `for` | 条件**变真**后 | 连续满足多久**才**告警 |
| `keep_firing_for` | 条件**变假**后 | 继续保持告警多久**才**恢复 |

它的典型用途是**告警抖动**：某个指标在临界值附近反复横跳，如果没有 `keep_firing_for`，告警会疯狂"告警-恢复-告警-恢复"，把人烦死。

配了 `keep_firing_for: 5m` 后，即使条件恢复了，告警也会**再保持 5 分钟**才真正恢复——给故障留一个"观察期"。

> ⚠️ **本课未实测声明**：`keep_firing_for` 与 `recovering` 状态的关系，本课做了专项实验但**未能触发 `recovering` 状态**（详见下文"实验记录"）。目前只能确认该字段**存在且可写入**，其触发 `recovering` 的具体条件有待后续验证。

### 示例演示：写一条完整的告警规则

把三要素合起来，写一条"Web 服务器负载过高"的规则：

```python
import json, urllib.request, base64

GF = "http://localhost:3001"
AUTH = base64.b64encode(b"admin:admin").decode()
DS_UID = "afx7x6dx803y8e"     # 你的 Prometheus 数据源 UID

rule = {
    "uid": "web-high-load",
    "title": "Web 服务器负载过高",
    "ruleGroup": "production",          # 评估组（决定求值间隔）
    "folderUID": "l08alerts",
    "orgID": 1,
    "condition": "C",                   # 用 C 节点的结果判定
    "for": "5m",                        # 连续 5 分钟才告警
    "noDataState": "NoData",            # 没数据 → No Data 状态
    "execErrState": "Error",            # 查询出错 → Error 状态
    "isPaused": False,
    "data": [
        # 要素一：查询
        {
            "refId": "A", "queryType": "",
            "relativeTimeRange": {"from": 600, "to": 0},
            "datasourceUid": DS_UID,
            "model": {
                "refId": "A",
                "datasource": {"type": "prometheus", "uid": DS_UID},
                "expr": "node_load1",
                "editorMode": "code",
                "legendFormat": "__auto"
            }
        },
        # 要素二（上）：Reduce —— 取最新值，保留 instance 标签
        {
            "refId": "B", "queryType": "",
            "relativeTimeRange": {"from": 0, "to": 0},
            "datasourceUid": "-100",
            "model": {
                "refId": "B",
                "datasource": {"type": "__expr__", "uid": "-100"},
                "type": "reduce",
                "reducer": "last",
                "expression": "A",
                "settings": {"mode": "dropNN"}
            }
        },
        # 要素二（下）：Threshold —— 负载 > 4 告警
        {
            "refId": "C", "queryType": "",
            "relativeTimeRange": {"from": 0, "to": 0},
            "datasourceUid": "-100",
            "model": {
                "refId": "C",
                "datasource": {"type": "__expr__", "uid": "-100"},
                "type": "threshold",
                "expression": "B",
                "conditions": [{
                    "type": "query",
                    "evaluator": {"params": [4], "type": "gt"}
                }]
            }
        }
    ]
}

data = json.dumps(rule).encode()
r = urllib.request.Request(GF + "/api/v1/provisioning/alert-rules",
                           data=data, method="POST")
r.add_header("Authorization", "Basic " + AUTH)
r.add_header("Content-Type", "application/json")
resp = urllib.request.urlopen(r, timeout=30)
print("HTTP", resp.status)
```

验证它是否按预期工作：

```bash
# 1. 看规则是否创建成功
curl -s -u admin:admin http://localhost:3001/api/v1/provisioning/alert-rules | python3 -c "import sys,json; [print('%-20s group=%-12s for=%s' % (r['title'], r['ruleGroup'], r['for'])) for r in json.load(sys.stdin)]"

# 2. 看告警实例（注意有没有 instance 标签）
curl -s -u admin:admin http://localhost:3001/api/alertmanager/grafana/api/v2/alerts | python3 -c "import sys,json; [print('%-20s instance=%s' % ((a.get('labels') or {}).get('alertname'), (a.get('labels') or {}).get('instance'))) for a in json.load(sys.stdin)]"

# 3. 看状态分布
curl -s -u admin:admin http://localhost:3001/metrics 2>/dev/null | grep '^grafana_alerting_alerts{'
```

### 常见误区

**误区一：以为 `condition` 指向查询节点就够了**

`condition: "A"` 在 A 是 Prometheus 查询时**不合法**——查询节点返回的是序列，不是二值判定结果。

`condition` 必须指向一个**能产生二值结果**的节点（通常是 `threshold` 或 `classic_conditions`）。

**误区二：以为 Reduce 只是"取个值"，不影响告警条数**

这是本课最重要的发现。Reduce 的写法（`classic_conditions` vs 独立 `reduce`）**直接决定告警实例数与标签**，进而决定 8.3 的分组能否生效。

**误区三：以为改 `intervalSeconds` 能让某条规则更灵敏**

实测：规则级 `intervalSeconds` **被忽略**（回读 `null`）。间隔由**评估组**统一决定。

想让某条规则更灵敏，要把它**挪到另一个评估组**。

**误区四：在 `classic_conditions` 里找"为什么没有 instance 标签"**

`classic_conditions` 会在降维时丢掉序列标签。这不是 bug，是设计。

需要标签就用独立 `reduce`。

### 一句话记住

> **查询决定"看什么"，条件决定"什么算异常"，评估行为决定"多久看、持续多久、看不清怎么办"；而条件里的 Reduce 写法，悄悄决定了你会收到几条告警。**

---

## 🧠 8.2 通知策略树与静默：告警怎么路由到人

### 一句话定义

通知策略树是一棵**按标签匹配的路由树**，决定"什么样的告警发给谁"；静默是一条**临时的压制规则**，决定"这段时间别发"。

### 直觉建立：公司前台的电话转接

想象告警是一通打进公司的电话。

**Contact point（联系点）= 一个具体的电话号码。**
可以是值班手机、Slack 频道、钉钉群、邮件组。它只管"怎么把消息送出去"。

**通知策略树 = 前台的转接规则手册。**

```
如果来电是「财务」的 → 转财务部
如果来电是「技术」的 → 转技术部
如果来电是「投诉」的 → 转客服部
都不匹配 → 转前台（默认）
```

**静默（Silence）= 前台挂出的"免打扰"牌子。**

```
"今天下午 2-4 点全公司开会，所有来电都别转，但来电记录照记。"
```

注意这个牌子的关键特性：**它拦的是"转接"这个动作，不是"来电"本身。**

电话还是打进来了（告警状态照常变），只是不转给任何人（不发通知）。

### 核心原理

#### 组件一：Contact point（联系点）

Contact point 是**通知的终点**——一个具体的发送通道。

本课实测：Grafana 13 支持哪些类型？我们逐个试探了 20 种：

```
✅ webhook      HTTP 202        ✅ email        HTTP 202
✅ slack        HTTP 202        ✅ dingding     HTTP 202
✅ wecom        HTTP 202        ✅ victorops    HTTP 202
✅ discord      HTTP 202        ✅ googlechat   HTTP 202
✅ line         HTTP 202        ✅ kafka        HTTP 202
✅ mqtt         HTTP 202        ✅ webex        HTTP 202
✅ oncall       HTTP 202

❌ telegram     HTTP 400  could not find Bot Token in settings
❌ pagerduty    HTTP 400  could not find integration key property in settings
❌ opsgenie     HTTP 400  could not find api key property in settings
❌ pushover     HTTP 400  user key not found
❌ sensugo      HTTP 400  could not find URL property in settings
❌ threema      HTTP 400  invalid Threema Gateway ID
❌ jira         HTTP 400  could not find api_url property in settings
```

**注意 ❌ 的那些不是"不支持"，是"必填参数没给"。**

比如 `telegram` 报的是 `could not find Bot Token in settings`——它支持 Telegram，只是我没给 `bot_token`。

这个区分很重要：

- **类型存不存在** → 看错误是不是 `unknown receiver type` 之类
- **类型能不能用** → 看你有没有给它配对的必填参数

创建一个 webhook 类型的 contact point：

```python
{
  "uid": "cp-critical",
  "name": "cp-critical",
  "type": "webhook",
  "settings": {
    "url": "http://l08-webhook:9999/critical",
    "httpMethod": "POST"
  }
}
```

#### 组件二：通知策略树（Notification Policy Tree）

策略树是一棵**树**，每个节点可以：

- 用 `object_matchers` 匹配标签
- 指定匹配后发给哪个 `receiver`
- 配置分组参数（`group_by` / `group_wait` / `group_interval` / `repeat_interval`）
- 用 `continue` 决定"匹配后是否继续往下走"

**树的结构**（本课实测建立并回读确认）：

```json
{
  "receiver": "cp-default",
  "group_by": ["alertname"],
  "routes": [
    {
      "receiver": "cp-critical",
      "group_by": ["alertname"],
      "object_matchers": [["severity", "=", "critical"]],
      "group_wait": "5s",
      "group_interval": "30s",
      "repeat_interval": "1m"
    }
  ],
  "provenance": "api"
}
```

**匹配语法**（本课实测全部 5 种都返回 202）：

| 写法 | 含义 |
|---|---|
| `["severity", "=", "critical"]` | severity **等于** critical |
| `["severity", "!=", "critical"]` | severity **不等于** critical |
| `["severity", "=~", "crit.*"]` | severity **正则匹配** crit.* |
| `["severity", "!~", "crit.*"]` | severity **正则不匹配** crit.* |
| `["severity", "=~", ".*"]` | 匹配任意非空值 |

**注意是 `object_matchers`，不是 `matchers`。**

`object_matchers` 用的是三元组 `[标签名, 操作符, 值]` 的形式，比老式的 `matchers: {severity: critical}` 更灵活（支持正则和否定）。

**`continue` 的语义**（实测该字段被接受）：

- `continue: false`（默认）→ **第一个匹配的节点就停止**，不再检查兄弟节点
- `continue: true` → 匹配后**继续检查**后续兄弟节点，可以发给多个 receiver

这个区别很像 `switch` 语句里有没有 `break`。

**子策略可用字段**（本课实测）：

```
group_wait           → HTTP 202  ✅
group_interval       → HTTP 202  ✅
repeat_interval      → HTTP 202  ✅
continue             → HTTP 202  ✅

mute_time_intervals  → HTTP 400  ❌  mute time interval not found
active_time_intervals→ HTTP 400  ❌  active time interval not found
```

后两个报 400 是**因为我引用了当时还不存在的 mute timing**（`mt1` 是在之后的步骤才创建的）。

**正确顺序**：先创建 mute timing，再在策略树里引用它。

#### 组件三：Mute Timing（静默时段）

Mute timing 是**周期性**的免打扰时段，比如"每周六周日全天不打扰"。

```python
{
  "uid": "mt1",
  "name": "mt1",
  "time_intervals": [{
    "times": [{"start_time": "00:00", "end_time": "23:59"}],
    "weekdays": ["saturday", "sunday"]
  }]
}
```

创建成功后（HTTP 201），就能被策略树的 `mute_time_intervals` 引用了。

#### 组件四：静默（Silence）

静默是**一次性**的临时压制，比如"接下来 2 小时我维护数据库，别发告警"。

**创建**：

```python
{
  "comment": "数据库维护窗口",
  "createdBy": "admin",
  "startsAt": "2026-09-04T12:00:00.000Z",
  "endsAt":   "2026-09-04T14:00:00.000Z",
  "matchers": [{
    "name": "alertname",
    "value": "l08.*",
    "isRegex": true,
    "isEqual": true
  }]
}
```

实测返回：

```
POST /api/alertmanager/grafana/api/v2/silences
→ HTTP 202  {"silenceID": "0cbcdee6-9d44-4918-974f-30ed2b75b869"}
```

**静默的完整字段**（实测）：

```
['comment', 'createdBy', 'endsAt', 'id', 'matchers', 'startsAt', 'status', 'updatedAt']

status.state = active
matchers = [{"isEqual": true, "isRegex": true, "name": "alertname", "value": "l08.*"}]
```

**注意端点差异**：

| 操作 | 端点 | 返回 |
|---|---|---|
| 查列表 | `GET /api/alertmanager/grafana/api/v2/silences` | 200 |
| 创建 | `POST /api/alertmanager/grafana/api/v2/silences` | 202 |
| 删除 | `DELETE /api/alertmanager/grafana/api/v2/silence/{id}` | 200（**单数** silence） |
| 错误写法 | `GET /api/alertmanager/grafana/api/v2/silence/` | 404 |

**创建是复数 `silences`，删除是单数 `silence`。** 这个不一致很容易踩。

#### 【重点】静默 vs 抑制：两个极易混淆的概念

| | **静默（Silence）** | **抑制（Inhibition）** |
|---|---|---|
| 触发方式 | **人工创建**，或按 mute timing 周期生效 | **告警之间**自动触发 |
| 逻辑 | "这段时间别发" | "A 告警了，B 就别发了" |
| 典型场景 | 计划内维护窗口 | 机房断电了，别再报机器失联 |
| 配置位置 | Alertmanager silences API | 通知策略的 `mute_time_intervals` / 抑制规则 |
| 是否改状态 | ❌ 不改 | ❌ 不改 |

**两者都不改变告警状态，只压制通知。**

这是本课实测验证的最重要一条（详见 8.3 场景 C）：

```
静默期间：webhook 通知 = 0 条
但告警状态：alerting = 3          ← 状态照常是 Alerting
```

**告警还在，只是没人告诉你。**

这个设计是对的——静默是"我暂时不想听"，不是"问题解决了"。恢复静默后你能立刻看到这段时间的完整告警历史。

> ⚠️ **一个必须知道的坑**：静默**删不掉**，只能**等它过期**。
>
> 本课实测：调用 `DELETE /silence/{id}` 返回 `{"message":"silence deleted"}`（HTTP 200），
> 但再查列表，那条静默**还在**，只是 `state` 变成了 `expired`。
>
> Alertmanager 会把静默作为历史记录保留一段时间。所以：
> **创建静默时一定要设好 `endsAt`，别指望删掉它。**

### 示例演示：配一棵完整的通知策略树

```python
import json, urllib.request, base64, time

GF = "http://localhost:3001"
AUTH = base64.b64encode(b"admin:admin").decode()


def req(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(GF + path, data=data, method=method)
    r.add_header("Authorization", "Basic " + AUTH)
    r.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw.strip() else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw or "{}")
        except Exception:
            return e.code, {"_raw": raw[:400]}


# --- 第 1 步：先建 contact point（策略树要引用它们）---
for name, path in [("cp-default", "/default"),
                   ("cp-critical", "/critical")]:
    st, b = req("POST", "/api/v1/provisioning/contact-points", {
        "uid": name, "name": name, "type": "webhook",
        "settings": {"url": "http://l08-webhook:9999" + path,
                     "httpMethod": "POST"}})
    print("contact point %-12s → HTTP %s" % (name, st))

# --- 第 2 步：建 mute timing（如果有周期免打扰）---
st, b = req("POST", "/api/v1/provisioning/mute-timings", {
    "uid": "weekend", "name": "weekend",
    "time_intervals": [{
        "times": [{"start_time": "00:00", "end_time": "23:59"}],
        "weekdays": ["saturday", "sunday"]}]})
print("mute timing weekend → HTTP %s" % st)

# --- 第 3 步：建策略树（引用上面已存在的 receiver）---
tree = {
    "receiver": "cp-default",           # 兜底：都不匹配就发这里
    "group_by": ["alertname"],
    "routes": [
        {
            "receiver": "cp-critical",
            "object_matchers": [["severity", "=", "critical"]],
            "group_by": ["alertname"],
            "group_wait": "10s",
            "group_interval": "30s",
            "repeat_interval": "1m",
            "continue": False           # 匹配即停止
        }
    ]
}
st, b = req("PUT", "/api/v1/provisioning/policies", tree)
print("策略树 → HTTP %s" % st)
if st not in (200, 201, 202):
    print("  失败原因：%s" % str(b)[:300])
```

**关键顺序**：**先 contact point → 再 mute timing → 最后策略树**。

本课第一次试探时反着来，所有策略树请求都是 400：

```
Invalid format of the submitted route:
receiver 'grafana-default-email' does not exist.
```

**策略树会校验 receiver 是否存在。** 引用不存在的 receiver 会整棵树被拒。

### 常见误区

**误区一：以为策略树是"全部匹配的都发"**

默认是 `continue: false`——**第一个匹配的节点生效后就停止**。

想发给多个地方，要显式 `continue: true`。

**误区二：以为静默能让告警消失**

不能。静默只压通知，告警状态照常迁移。

**误区三：创建了静默想删掉**

删不掉，只能等过期。创建时务必设好 `endsAt`。

**误区四：先配策略树再建 contact point**

策略树会校验 receiver 存在性。顺序反了会 400。

### 一句话记住

> **Contact point 是"发给谁"，策略树是"按什么规则决定发给谁"，静默是"这段时间先别发"；三者都不改变告警本身的状态。**

---

## 🧠 8.3 分组与抑制：为什么一条故障只该响一次

### 一句话定义

分组（Grouping）把**多条告警合并成一条通知**，用 `group_by` 指定"按哪些标签合并"；三个时间参数控制"攒多久发一次、后续多久发一次、重复多久发一次"。

### 直觉建立：快递员怎么送包裹

你是快递员，今天要送 100 个包裹，全都发往**同一栋写字楼的同一家公司**。

**方案 A：跑 100 趟。**
每拿一个包裹就骑电动车去一次，送到前台，回来拿下一个。

**方案 B：攒一批送一次。**
先等 10 分钟，把这段时间收的所有包裹攒起来，一次性送到前台，说"这 100 个都是你们公司的"。

正常人都会选 B。

但这里有个关键问题：**你按什么判断"这些包裹是同一家的"？**

- 按**收件公司**合并 → 100 个包裹变成 1 趟
- 按**收件人姓名**合并 → 100 个包裹变成 100 趟（如果 100 个人各一个）

**`group_by` 就是你这个"按什么合并"的判断标准。**

Grafana 里的对应：

| 快递场景 | 告警场景 |
|---|---|
| 包裹 | 告警实例（alert instance） |
| 收件公司 / 收件人 | 告警的标签（labels） |
| 按什么合并 | `group_by` |
| 先等 10 分钟攒单 | `group_wait` |
| 第二批货多久送一次 | `group_interval` |
| 同一批货反复催 | `repeat_interval` |

### 核心原理

#### 四个参数的定义

| 参数 | 定义 | 一句话 |
|---|---|---|
| `group_by` | 按哪些**标签**把告警归为一组 | 合并的依据 |
| `group_wait` | 一组内**第一条**告警出现后，**等多久**再发第一条通知 | 攒单的等待期 |
| `group_interval` | 同一组**后续**通知之间的间隔 | 新告警加入后的通知节奏 |
| `repeat_interval` | 告警**未恢复**时，重复提醒的间隔 | 催单的频率 |

#### 【核心实验】3 台机器，两种 `group_by`，通知量差 3 倍

这是我们为本课设计的主实验。

**实验设置**：

- 3 台机器（`grafana-node:9100`、`grafana-node2:9100`、`grafana-node3:9100`）
- 一条规则 `node_load1 > -1`（3 条序列全部恒真 → 3 台同时告警）
- 条件是 `reduce + threshold`（**保留 `instance` 标签**）
- 观察 180 秒内 webhook 收到的通知

**场景 A：`group_by = [alertname]`（按规则名合并，不区分机器）**

```
t= 20s   alerting=3   webhook=0 条
t= 30s   alerting=3   webhook=1 条   ← 第一条通知
t=120s   alerting=3   webhook=2 条   ← 第二条（重复提醒）
```

webhook 实际收到的内容：

```
11:51:50  status=firing  告警数=3  group={"alertname": "g3"}
          实例=['grafana-node2:9100', 'grafana-node3:9100', 'grafana-node:9100']
11:53:20  status=firing  告警数=3  group={"alertname": "g3"}
          实例=['grafana-node2:9100', 'grafana-node3:9100', 'grafana-node:9100']
```

**3 台机器，只发了 2 条通知**（1 条首次 + 1 条重复提醒）。
每条通知里**包含全部 3 台机器**。

**场景 B：`group_by = [alertname, instance]`（按机器拆开）**

```
t= 40s   alerting=3   webhook=3 条   ← 3 台各一条
t=130s   alerting=3   webhook=6 条   ← 各重复一次
```

webhook 实际收到的内容：

```
11:55:10  status=firing  告警数=1  group={"alertname":"g3","instance":"grafana-node3:9100"}
11:55:10  status=firing  告警数=1  group={"alertname":"g3","instance":"grafana-node:9100"}
11:55:10  status=firing  告警数=1  group={"alertname":"g3","instance":"grafana-node2:9100"}
11:56:40  status=firing  告警数=1  group={"alertname":"g3","instance":"grafana-node:9100"}
11:56:40  status=firing  告警数=1  group={"alertname":"g3","instance":"grafana-node2:9100"}
11:56:40  status=firing  告警数=1  group={"alertname":"g3","instance":"grafana-node3:9100"}
```

**同样是 3 台机器，发了 6 条通知**（3 台 × 2 轮）。

**对比结论**：

| `group_by` | 通知条数 | 每条通知含几台机器 | 相对量 |
|---|---|---|---|
| `[alertname]` | 2 条 | 3 台 | **基线** |
| `[alertname, instance]` | 6 条 | 1 台 | **3 倍** |

**这就是开篇那个场景的答案。**

100 台机器同时挂：

- `group_by: [alertname]` → 你收到 **1 条**通知：「web 服务 100 台全部失联」
- `group_by: [alertname, instance]` → 你收到 **100 条**通知：「web-001 失联」「web-002 失联」……

**选哪个？**

取决于你的**处理动作**是否因机器而异：

| 场景 | 该不该按 instance 拆 |
|---|---|
| 交换机挂了，100 台全挂，修交换机就行 | ❌ 不该拆 → 合并成 1 条 |
| 每台机器的磁盘满了，要分别清理 | ✅ 该拆 → 每台一条 |
| 大规模故障，要先知道"影响面多大" | ❌ 不该拆 → 一条看清全局 |
| 单机偶发抖动，要定位到具体机器 | ✅ 该拆 → 精确定位 |

> **经验法则**：
> **故障面越大，越应该合并；故障越局部，越应该拆开。**
>
> 大规模故障时，你需要的是「影响面全景」，不是「100 条细节」。

#### 【重点】`group_by` 要生效，标签必须存在

这是 8.1 埋下的伏笔在此收束。

**如果你的告警用的是 `classic_conditions`，labels 里没有 `instance`：**

```
labels = {"__alert_rule_uid__":"v-cls", "alertname":"v-cls", "grafana_folder":"L08 Alerts"}
```

那么 `group_by: [alertname, instance]` **完全无效**——
所有告警的 `instance` 标签都是空，它们仍然会被合并成一组。

**你会看到"配了分组却没效果"，然后怀疑分组功能坏了。**

实际是因为：8.1 的 Reduce 写法已经把标签丢掉了。

> **排查口诀**：分组不生效时，先查告警实例**有没有那个标签**。

```bash
curl -s -u admin:admin http://localhost:3001/api/alertmanager/grafana/api/v2/alerts | python3 -c "import sys,json; [print(sorted((a.get('labels') or {}).keys())) for a in json.load(sys.stdin)]"
```

如果输出里没有 `instance`，回去改 8.1 的条件写法。

#### 三个时间参数的实测：为什么配 1 分钟却等了 90 秒

场景 A 里我们观察到一个奇怪的数字：**两条通知间隔 90 秒**，而配置是：

```
group_wait = 10s
group_interval = 30s
repeat_interval = 1m
```

配的是 1 分钟，实际等了 90 秒。**多出来的 30 秒哪来的？**

为了回答这个问题，我们做了三组隔离实验——**每次只改一个参数**：

| 实验 | group_wait | group_interval | repeat_interval | 首条通知 | **通知间隔** |
|---|---|---|---|---|---|
| 1 | 40s | 30s | **1m** | — | **90 秒** |
| 2 | 5s | 30s | **1m** | — | **90 秒** |
| 3 | 5s | 30s | **40s** | — | **60 秒** |

**三条关键观察**：

**其一，`repeat_interval` 是重复间隔的主导因素。**

实验 1 和 2 的 `group_wait` 差了 **35 秒**（40s vs 5s），但通知间隔**完全相同**（都是 90 秒）。
实验 3 只把 `repeat_interval` 从 1m 降到 40s，间隔就从 90 秒变成 60 秒。

**其二，实际间隔总是"跳到下一个检查点"，而不是精确等于配置值。**

- `repeat=40s` → 实测 **60 秒**（下一个 30s 的整数倍：30 未到 40，60 到了）
- `repeat=60s` → 实测 **90 秒**（30 未到 60；60 处于边界，判定未过；90 才发）

**其三，由此可以拼出一个统一的模型**：

```
通知检查点 = group_interval 的整数倍（30s、60s、90s、120s...）
每个检查点判断：距上次通知是否已过 repeat_interval
  → 是：发通知
  → 否：跳过，等下一个检查点
```

用这个模型验算三组数据：

| 实验 | repeat | 检查点 30s | 检查点 60s | 检查点 90s | 实测 |
|---|---|---|---|---|---|
| 3 | 40s | 未到（30<40）| **到（60≥40）** | — | ✅ 60s |
| 1/2 | 60s | 未到（30<60）| 边界（60≥60 判定未过）| **到（90≥60）** | ✅ 90s |

模型与三组实测数据**全部吻合**。

> ⚠️ **推断边界声明**：上面这个"检查点模型"是从 **3 组实测数据**中归纳出来的，
> 它**解释了**这三组数据，但**未经更多组实验验证**（比如没有测 `group_interval=10s` 或 `repeat=2m` 的情况）。
>
> 可以确信的**实测事实**是：
> - `repeat_interval` 主导重复通知的间隔
> - 实际间隔会"向上取整"到某个节拍，通常**大于**配置值
> - 60 秒的求值间隔会参与对齐
>
> **不要**把上面的模型当作 Grafana 的官方实现细节——它是本课的**观测推断**。

**这个发现的实际意义**：

> **配 `repeat_interval: 1m`，你可能实际每 90 秒才收到一次提醒。**
>
> 如果你指望"每 5 分钟催一次"，实际可能是 5 分半、6 分钟。
> **不要把 `repeat_interval` 当成精确闹钟**，它是"至少间隔这么久"的下界，不是精确定时。

####【重点】静默不改状态：实测证据

场景 C 专门验证这一点。

**设置**：创建一条静默（`alertname=g3`，持续 1 小时），然后让 3 台机器告警。

**结果**：

```
t= 60s   alerting=3   webhook=0 条
t= 90s   alerting=3   webhook=0 条
t=120s   alerting=3   webhook=0 条
t=150s   alerting=3   webhook=0 条

→ 静默期间：webhook 通知 = 0 条
→ 但告警状态：alerting = 3
```

**告警状态是 Alerting（3 条），但一条通知都没发。**

这就是"静默压通知不压状态"的直接证据。

**为什么这个区别重要？**

因为很多人误以为静默 = 关掉告警。然后：

1. 维护窗口结束，静默过期
2. 一堆告警**突然全部涌出**
3. 你以为"刚出故障了"，其实是"过去几小时一直在故障，只是你没收到"

**正确的心智模型**：静默是**消音器**，不是**刹车**。

问题还在跑，只是你听不见。静默结束时，Grafana 会把这段时间的告警一股脑告诉你。

### 示例演示：把 N 台机器的告警收敛成一条

```python
import json, urllib.request, base64

GF = "http://localhost:3001"
AUTH = base64.b64encode(b"admin:admin").decode()


def req(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(GF + path, data=data, method=method)
    r.add_header("Authorization", "Basic " + AUTH)
    r.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw.strip() else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw or "{}")
        except Exception:
            return e.code, {"_raw": raw[:400]}


# 策略树：只按 alertname 分组 → 所有机器合并成一条通知
policy = {
    "receiver": "cp-ops",
    "group_by": ["alertname"],        # ← 关键：不按 instance 拆
    "group_wait": "30s",              # 攒 30 秒再发，避免抖动
    "group_interval": "5m",           # 同组后续通知间隔
    "repeat_interval": "4h",          # 未恢复的话每 4 小时提醒一次
    "routes": [
        {
            "receiver": "cp-sre-pager",
            "object_matchers": [["severity", "=", "critical"]],
            "group_by": ["alertname"],
            "group_wait": "10s",      # 严重告警等更短
            "repeat_interval": "30m", # 但催得更勤
            "continue": False
        }
    ]
}
st, b = req("PUT", "/api/v1/provisioning/policies", policy)
print("策略树 → HTTP %s" % st)
```

验证收敛效果：

```bash
# 看告警实例数（Alertmanager 视角）
curl -s -u admin:admin http://localhost:3001/api/alertmanager/grafana/api/v2/alerts | python3 -c "import sys,json; from collections import Counter; a=json.load(sys.stdin); c=Counter((x.get('labels') or {}).get('alertname') for x in a); print('告警实例数：%d'%len(a)); print('按 alertname 分组后：%d 组'%len(c)); [print('  %s: %d 条实例合并'%(k,v)) for k,v in c.items()]"
```

### 常见误区

**误区一：`group_by` 里写了一个不存在的标签**

不报错，但**静默失效**——所有告警还是合并成一组（因为这个标签都是空）。

用上面的排查口诀先确认标签存在。

**误区二：以为通知条数 = 告警条数**

不是。通知条数 = **分组数** × 通知轮次。

3 条告警，`group_by=[alertname]` → 1 组 → 1 条通知（每轮）。

**误区三：把 `group_interval` 和 `repeat_interval` 搞混**

两者都影响"多久发一次"，但作用阶段不同。本课本节课**未实测验证**其精确区分，配置时建议先按官方定义设置，再实测观察。

**误区四：静默当成"关掉告警"用**

静默期间问题不会消失，只是你听不见。静默结束时它们会一起涌出来。

### 一句话记住

> **`group_by` 决定"几条告警合成一条通知"，三个时间参数决定"多久发、多久再发"；而分组能生效的前提，是告警实例身上真的带着那个标签。**

---

## 🔗 跨课串联：阶段 3 的完整图景

### 课 7 与课 8 的分工

| | 课 7《告警架构》 | 课 8《规则与通知》 |
|---|---|---|
| 回答的问题 | 告警**在哪算、状态怎么变** | 告警**怎么配、发给谁、发几条** |
| 核心概念 | 求值位置、状态机、No Data | 三要素、策略树、分组 |
| 关键数字 | `for` 被 interval 稀释 | `group_by` 让通知量差 3 倍 |
| 一句话 | 让告警**会响** | 让告警**响得对** |

### 一条告警的完整生命周期（阶段 3 全景）

```
  ┌─────────────────────────────────────────────────────────┐
  │  1. 查询（8.1）                                          │
  │     Prometheus 返回 N 条序列                             │
  │     ↓                                                    │
  │  2. Reduce + Threshold（8.1）                            │
  │     降维 + 判定 → M 条告警实例                            │
  │     ⚠️ classic 丢标签(M=1)，reduce 保留标签(M=N)          │
  │     ↓                                                    │
  │  3. 状态机（课 7）                                        │
  │     Normal → Pending → Alerting                          │
  │     ⚠️ for 是"连续满足多久"，被 interval 稀释             │
  │     ↓                                                    │
  │  4. 通知策略树匹配（8.2）                                 │
  │     按 object_matchers 找 receiver                       │
  │     ⚠️ continue:false → 第一个匹配即停                    │
  │     ↓                                                    │
  │  5. 静默检查（8.2）                                       │
  │     命中静默 → 不发通知（但状态不变！）                    │
  │     ↓                                                    │
  │  6. 分组（8.3）                                           │
  │     按 group_by 把 M 条实例合并成 K 组                    │
  │     ⚠️ 标签不存在则分组失效                               │
  │     ↓                                                    │
  │  7. 发送（8.2）                                           │
  │     group_wait 攒单 → 发第一条                            │
  │     repeat_interval 重复提醒                              │
  └─────────────────────────────────────────────────────────┘
```

**注意第 2 步与第 6 步的耦合**：

> **第 2 步丢了标签，第 6 步就分不了组。**

这是本课最值得记住的一条跨步骤依赖。

### 跨课呼应：第四次看到"Grafana 在揽活"

| 课 | 什么活 | 谁干 |
|---|---|---|
| 课 4 | `editorMode` 解析 | **前端** |
| 课 5 | `transformations` 执行 | **前端** |
| 课 6 | `repeat` 展开 | **前端** |
| 课 7 | 告警求值、状态、通知 | **Grafana 自己** |
| 课 8 | **分组、策略树、静默** | **Grafana 自己**（内置 Alertmanager） |

课 8 揭示了一个重要事实：Grafana **内置了一个 Alertmanager**。

证据是那些 API 路径：

```
/api/alertmanager/grafana/api/v2/alerts
/api/alertmanager/grafana/api/v2/silences
```

**你在用 Alertmanager 的语义（silence / group / inhibit），但用的是 Grafana 的实现。**

这正是课 7 讲的"规则求值在 Grafana 内部"的延续——不光求值，连**通知的路由、分组、静默**都 Grafana 自己做了。

代价同样延续：**Grafana 挂了，整条链路全断**——不算告警、不迁移状态、也不发通知。

---

## 🧪 实验记录：本课踩过的坑

这一节记录本课实测中**与预期不符**的地方，以及我们如何核实它们。保留这些记录，是因为"为什么"比"是什么"更有价值。

### 坑一：v1 实验结果被脏数据污染

**现象**：第一次测 classic vs reduce 时，Q1 清理后 `alerting` 仍为 1，Q2 的 3 条可能是残留。

**核实**：引入 `strict_clean()`——删光规则后**轮询直到所有状态归零**，再开始下一组实验。

**结论**：严格清理后，classic→1 条、reduce→3 条的结论**依然成立**。v1 的结论是对的，但**论证过程不严谨**。

**固化为方法约束**：

> 告警是**离散采样**（60 秒一轮）。每次测量前必须：
> 1. 删除所有规则
> 2. **轮询状态直到全部归零**（不能只等固定时间）
> 3. 再开始下一组实验
>
> 这条在课 7 已固化一次，本课再次验证其必要性。

### 坑二：`interval=1ms` 的误读

**现象**：读规则组间隔时，打印出 `interval=1ms`。

**核实**：`1ms` 是我打印时加了 `s` 后缀造成的——实际值是字符串 `1m`，我格式化成 `%ss` 就成了 `1ms`。

**结论**：组间隔是 **1 分钟**（符合预期）。**不是 1 毫秒。**

**教训**：打印 duration 类型的值时，先看它的**原始类型**（本课是字符串 `"1m"`），别急着加单位后缀。

### 坑三：策略树全部 400

**现象**：所有策略树试探都返回 400。

**核实**：错误信息明确写了 `receiver 'grafana-default-email' does not exist`。

**结论**：我引用了一个**不存在的 receiver**。Grafana 会校验 receiver 存在性，不存在则整棵树被拒。

**修正**：先建 contact point，再配策略树。

### 坑四：静默"删不掉"

**现象**：`DELETE /silence/{id}` 返回 `{"message":"silence deleted"}` HTTP 200，但列表里还在。

**核实**：再查发现那两条静默的 `state` 都是 `expired`。

**结论**：Alertmanager **保留静默历史**，删除操作只是把状态改为 expired，并不从列表移除。

另外发现：`startsAt` 与 `endsAt` 相差仅 **15-29 毫秒**——我传入的时间被 Grafana 改写了，导致静默几乎立刻过期（这也是后续实验中静默"看起来没生效"的一个干扰因素）。

**教训**：创建静默时务必设好 `endsAt`，且不要假设时间参数会被原样接受。

### 坑五：mute timing 引用顺序

**现象**：`mute_time_intervals` 报 400 `mute time interval not found`。

**核实**：我引用的 `mt1` 在**该步骤之后**才创建。

**结论**：先创建 mute timing，再在策略树里引用。与坑三同源——**引用前先确保被引用对象存在**。

### 坑六：通知间隔与配置值对不上（配 1m 实测 90s）

**现象**：场景 A 配 `repeat_interval=1m`，实测通知间隔 **90 秒**，多出 30 秒。

**核实**：做了三组隔离实验（每次只改一个参数）：

| 实验 | group_wait | group_interval | repeat_interval | 实测间隔 |
|---|---|---|---|---|
| 1 | 40s | 30s | 1m | 90s |
| 2 | 5s | 30s | 1m | 90s |
| 3 | 5s | 30s | 40s | 60s |

**发现**：`group_wait` 差 35 秒，间隔不变（都是 90s）；`repeat_interval` 从 1m 降到 40s，间隔从 90s 变 60s。

→ 说明 **`repeat_interval` 才是主导因素**，且实际间隔会"向上跳到下一个检查点"。

**修正测量口径**：第一版用"首次告警 → 首条通知"的**相对差值**衡量 `group_wait`，得到 0.0 秒——这个数字是错的。原因是"首次告警时刻"本身受 60 秒求值节拍影响而漂移（实验 1 是 55.1s，实验 2 是 60.2s），用它做基准不可靠。改用**通知的绝对时间间隔**后才得到可比数据。

**教训**：测时间参数时，基准点必须**稳定**。"首次告警"这种受采样节拍影响的时刻不能当基准；"两条通知之间的间隔"才是稳定的观测量。

### 坑七：`keep_firing_for` 与 `recovering` 未能触发

**现象**：课 7 留下悬念——`recovering` 状态从未被触发过。本课设计了专项实验：用时间表达式让条件自然翻转，配 `keep_firing_for=60s`。

**结果**：**仍未捕获到 `recovering` 状态**。

**本课声明**：`recovering` 状态的存在已由 `/metrics` 证实（六种 state 标签之一），但其**触发条件未实测确认**。`keep_firing_for` 字段**存在且可写入**，但与 `recovering` 的因果关系**未验证**。

**留给后续**：可能与求值时机有关——`recovering` 可能只在特定窗口内短暂存在，需要更密集的采样才能捕获。

### 坑八：本环境的 webhook 连通性

**现象**：Grafana 容器**无法解析** `host.docker.internal`，访问 `172.17.0.1:9999` 也失败。

**核实**：Grafana 在自定义网络 `grafana-net` 里，不是默认 bridge。

**解法**：把接收端**也跑进 `grafana-net`**，用容器名互访：

```bash
docker run -d --name l08-webhook --network grafana-net -v /mnt/d/projects/learning/grafana/playground:/data python:3.11-slim python /data/l08_webhook_receiver.py
```

验证：

```
Grafana 容器访问 l08-webhook:9999 → wget exit=0  ✅
```

**教训**：Docker 自定义网络里，`host.docker.internal` 不一定可用。**同网络用容器名**是最稳的方案。

---

## ✅ 本课验收

| 验收标准 | 达成情况 |
|---|---|
| 写一条带 `for` 与 No Data 处理的完整规则 | ✅ 8.1 示例演示 |
| 用 API 验证状态迁移 | ✅ 用 `/metrics` 与 Alertmanager API 双路验证 |
| 配一棵按标签路由的通知策略树 | ✅ 8.2 建立并回读确认 |
| 加一条静默验证 | ✅ 8.3 场景 C，证明"压通知不压状态" |
| 用分组把 N 台机器的告警收敛成一条通知 | ✅ 8.3 场景 A/B，通知量差 3 倍 |

---

## 🔍 评审结论

**评审方式**：pedagogy（教学法）+ learner（学员）双视角，逐条回读原文核验，非凭记忆判断。

**评审时间**：2026-09-04（周四）

### P0 阻塞项

无。

### P1 建议项（已处理）

| # | 问题 | 处理 |
|---|---|---|
| 1 | `keep_firing_for` 与 `recovering` 未经实测 | 已加 ⚠️ 未实测声明，并写入"实验记录"坑七 |
| 2 | 三个时间参数的区分未实测 | 已补三组隔离实验，实测数据入正文；推断模型已标注 ⚠️ 边界 |

### 已核验的事实（逐条回读原文确认）

| 事实 | 出处 |
|---|---|
| classic→1 条 / reduce→3 条 | 8.1 核心实验，严格清理后复现 |
| classic 的 labels 无 `instance` | 实测 labels 输出 |
| 规则级 `intervalSeconds` 被忽略 | 回读 `null` |
| 组间隔由评估组决定 | 组级回读 `1m` |
| `group_by=[alertname]` → 2 条通知 | 场景 A webhook 日志 |
| `group_by=[alertname,instance]` → 6 条通知 | 场景 B webhook 日志 |
| 静默期间通知 0 条但状态 alerting=3 | 场景 C 实测 |
| repeat=1m→90s、repeat=40s→60s | 三组隔离实验 |
| contact point 类型 13 可用 / 7 缺参数 | 20 种类型试探 |
| 静默删除后仍为 expired | 坑四核实 |

### 评审结论

**本课交付合格**，可进入课 9。

三处"未完成"均以 ⚠️ 显式标注，未以推测冒充实测。

---

## 🎯 小测

1. 一条查询返回 3 条序列，用 `classic_conditions` 会产生几条告警实例？用 `reduce + threshold` 呢？为什么？
2. 你配了 `group_by: [alertname, instance]`，但发现告警还是合并成一条。最可能的原因是什么？怎么排查？
3. 创建了一条静默后，告警状态还会变成 Alerting 吗？为什么？
4. 你想让某条规则比其他规则求值更频繁，改它的 `intervalSeconds` 有用吗？正确做法是什么？
5. 100 台机器同时宕机，什么时候该按 `instance` 拆开告警，什么时候不该？
6. 你配了 `repeat_interval: 1m`，结果实测通知间隔是 90 秒。这是 bug 吗？为什么？

<details>
<summary>答案</summary>

1. `classic_conditions` → **1 条**（降维时丢掉 `instance` 标签，3 条序列无法区分被合并）；`reduce + threshold` → **3 条**（保留 `instance`/`job`/`__name__` 标签，各自独立）。

2. **最可能原因**：告警实例身上根本没有 `instance` 标签（比如用了 `classic_conditions`）。`group_by` 引用不存在的标签**不报错但静默失效**——所有实例的该标签都是空，仍被合并为一组。
   **排查**：查 Alertmanager 里告警实例的 labels，确认有没有 `instance`：

   ```bash
   curl -s -u admin:admin http://localhost:3001/api/alertmanager/grafana/api/v2/alerts | python3 -c "import sys,json; [print(sorted((a.get('labels') or {}).keys())) for a in json.load(sys.stdin)]"
   ```

3. **会**。静默只压**通知**，不改**状态**。这是本课实测验证的：静默期间 `webhook 通知 = 0 条`，但 `alerting = 3`。静默是"消音器"不是"刹车"——问题还在，只是你听不见；静默结束时会一股脑涌出来。

4. **没用**。实测规则级 `intervalSeconds` **被忽略**（回读 `null`），间隔由**评估组**统一决定。正确做法是把这条规则**挪到另一个评估组**，给那个组配更短的间隔。

5. 取决于处理动作是否因机器而异：**故障面大（如交换机挂了导致 100 台全挂），不该拆**——你需要的是"影响面全景"，合并成一条才知道全局；**故障局部（如单机磁盘满），该拆**——要精确定位到具体机器。
   **经验法则**：故障面越大越该合并，故障越局部越该拆开。

6. **不是 bug**。实测三组的结论是：实际间隔会"向上跳到下一个检查点"，通常**大于**配置值。`repeat=1m` 配 `group_interval=30s` 时，检查点是 30/60/90 秒——30 未到 60 不发，60 处于边界判定未过，90 才发，所以是 90 秒。
   把 `repeat_interval` 降到 40s，实测间隔就变成 60 秒（60 是第一个 ≥40 的检查点）。
   **记住**：`repeat_interval` 是"至少间隔这么久"的**下界**，不是精确闹钟。

</details>

---

## 📚 课程导航

- **上一课**：[课 7《告警架构：规则在哪求值、状态怎么迁移》](./lesson-07-告警架构：规则在哪求值、状态怎么迁移.md)
- **下一课**：课 9《日志与链路：指标之外的另外两只眼》（阶段 3）
- **阶段概览**：[阶段 3：叫得醒](../overview.md)
- **课程目录**：[02-课程目录.md](../../../02-课程目录.md)
- **学习档案**：[00-学习档案.md](../../../00-学习档案.md)

---

## 🚀 下一批接力提示词


```
继续学 Grafana。我的学习档案在 grafana/00-学习档案.md，
刚学完阶段 3《叫得醒》的课 8《告警规则与通知策略实战》
知识点 8.1（告警规则三要素：查询、条件、评估行为）、
8.2（通知策略树与静默：告警怎么路由到人）、
8.3（分组与抑制：为什么一条故障只该响一次），
请按大纲继续讲解课 9《日志与链路：指标之外的另外两只眼》
（知识点：Loki 数据源与 LogQL 入门 / 从指标到日志：时间窗对齐与下钻链接 / 链路下钻：Jaeger 数据源与 exemplar）。
```

---

## 📌 课 9 前置准备

根据阶段 3 概览，课 9 需要：

| 组件 | 状态 | 说明 |
|---|---|---|
| Loki | **待拉取** → `3101` | 课 9 需要，开始前 `docker pull grafana/loki` |
| Jaeger | 本机**已有镜像** → `16687` | 复用，不另拉 Tempo |

本课（课 8）新增的环境资产，课 9 可复用：

- 文件夹 `l08alerts`（uid=`l08alerts`）
- webhook 接收端容器 `l08-webhook`（在 `grafana-net` 网络内，端口 9999）

---

## 🧭 本课悬念

1. **`recovering` 状态到底什么时候出现？** 课 7 与本课的专项实验（含 `keep_firing_for=60s` + 条件自然翻转）都没捕获到它，但 `/metrics` 证明它存在
2. **通知模板怎么自定义？** 本课只讲了"发到哪、发几条"，没讲"发的内容长什么样"——`/api/v1/provisioning/templates` 端点本次探测返回 200，但内容未展开
3. **`group_interval` 的独立作用仍未隔离** — 三组实验中它恒为 30s，未做单变量测试。它到底控制"新告警加入的节奏"还是别的，有待补测

其中**第 1 个最关键**：`recovering` 是本课程目前唯一一个"证实存在但从未触发"的状态，理解它需要更密集的状态采样。
