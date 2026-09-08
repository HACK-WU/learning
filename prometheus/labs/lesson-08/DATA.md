# 课 8《联邦与全局视图》数据底稿（全部本机实测）

环境：Prometheus v3.14.0、Alertmanager v0.30.0、VictoriaMetrics v1.151.0
容器网络 l8net，宿主机端口 19110~19121

## 环境表

| 容器 | 端口 | 角色 | external_labels |
|---|---|---|---|
| l8-app | - | 数据源 507 条序列 | - |
| l8-leaf-a | 19110 | 叶子（分层联邦下层） | cluster=leaf-a, region=cn-south |
| l8-leaf-b | 19111 | 叶子（分层联邦下层） | cluster=leaf-b, region=cn-north |
| l8-replica-1 | 19112 | HA 副本 1 | cluster=ha-cluster, replica=1 |
| l8-replica-2 | 19113 | HA 副本 2 | cluster=ha-cluster, replica=2 |
| l8-global | 19114 | 全局联邦（honor_labels: true） | cluster=global, tier=global-view |
| l8-global-nh | 19116 | 全局联邦对照（honor_labels 默认 false） | 同上 |
| l8-vm | 19115 | 后端（接收 HA 双写） | dedup.minScrapeInterval=1s |
| l8-vm-norep | 19117 | 后端对照（无 replica） | dedup.minScrapeInterval=5s |
| l8-norep-1 | 19118 | 无 replica 副本 1 | cluster=ha-cluster（**无 replica**） |
| l8-norep-2 | 19119 | 无 replica 副本 2 | cluster=ha-cluster（**无 replica**） |
| l8-am-1 | 19120 | Alertmanager 副本 1 | gossip peer |
| l8-am-2 | 19121 | Alertmanager 副本 2 | gossip peer |
| l8-webhook | - | 通知接收器 | 记录每条通知 |

## 知识点 1：federation

### E0 /federate 端点输出（实测）

```text
# TYPE l8_build_info untyped
l8_build_info{instance="l8-app:8080",job="l8-app",revision="abc1234",version="1.0.0",cluster="leaf-a",region="cn-south"} 1 1788745930513
# TYPE l8_card_balance untyped
l8_card_balance{idx="0000",...,cluster="leaf-a",region="cn-south"} 1154.72 1788745930513
```

- **TYPE 全部为 untyped**（原始 counter/gauge 类型丢失）
- 叶子本地 l8_ 序列数 = 506，federate 返回 = 506（**一一对应，无聚合**）
- 输出带**毫秒时间戳**（第三列）——这是"当前值"的证据

### E1 只传瞬时值（决定性）

连续两次请求，间隔 6 秒：

```text
第 1 次: l8_card_balance{idx="0001",...} 4789.59 1788745930513
第 2 次: l8_card_balance{idx="0001",...} 4767.34 1788745935513
```

值变了、时间戳也变了 → **每次请求返回的是那一刻的当前值**。

### E1b TYPE=untyped 不影响 rate()（决定性）

默认查询（相对时间窗口），两者**经常不相等**：

```text
轮次   叶子rate    全局rate     差值
1      1.2         1.13821      0.06179
2      1.2         1.16767      0.03233
3      1.2         1.14714      0.05286
4      1.2         1.2          0.00000
5      1.2         1.1559       0.04410
```

⚠️ 叶子**恒定为 1.2** 而全局在 1.138~1.2 之间浮动 → 差异来自**求值时刻不同**
（两条命令一前一后，counter 一直在涨），不是联邦本身的问题。

**固定求值时刻后（决定性）**：

```text
端口 19110 在固定时刻 1788747164 的 rate = 1.2
端口 19114 在固定时刻 1788747164 的 rate = 1.2        <- 完全一致
```

**结论：联邦数据的 rate() 与叶子完全一致，untyped 不影响计算。**

方法论：对比两个 Prometheus 的查询结果时，**必须加 `time=` 参数固定求值时刻**，
否则比的是"谁先被查"，不是"谁算得准"。

⚠️ 但要注意：联邦数据能不能算 rate，取决于**联邦抓取间隔是否足够密**。
本例联邦 5s 抓一次，2 分钟窗口内约 24 个样本，所以 rate 能算且准确。

### E2 honor_labels 决定性对照

同一批数据，只改 `honor_labels` 一个开关：

| honor_labels | cluster | job | instance |
|---|---|---|---|
| **true** | leaf-a | **l8-app** | **l8-app:8080** |
| **true** | leaf-b | **l8-app** | **l8-app:8080** |
| **false**（默认） | leaf-a | **federate-leaf-a** | **l8-leaf-a:9090** |
| **false**（默认） | leaf-b | **federate-leaf-b** | **l8-leaf-b:9090** |

两侧总条数都是 1000（500 × 2），但标签完全不同。

**honor_labels=false 时**：叶子的 `job`/`instance` 被**改写**成联邦 target 的 job 名与地址。
你丢失了"数据本来来自哪个实例"这个信息。

### E3 联邦不搬运历史（决定性）

```text
查询 1 小时前 ~ 30 分钟前（全局节点 19114）：命中 0 条
```

全局节点只存**自己抓到的**样本。叶子上的历史不会搬过来。

### E4 样本密度对照

```text
叶子 leaf-a    最近 2 分钟、5s 步长：25 点
全局 联邦       最近 2 分钟、5s 步长：25 点
```

联邦节点按自己的 scrape_interval 采样，**密度取决于联邦的抓取间隔，不是叶子的**。

## 知识点 2：HA 与数据一致性

### E1 两副本各自独立

```text
replica-1: up=1  l8_card_balance=500 条
replica-2: up=1  l8_card_balance=500 条
```

### E2 副本间数据不一致（决定性）

连续 6 次采样 `l8_card_balance{idx="0001"}`，间隔 2s：

```text
#1  replica-1 = 4632.80   replica-2 = 4655.91   差 23.11
#2  replica-1 = 4632.80   replica-2 = 4623.92   差  8.88
#3  replica-1 = 4628.13   replica-2 = 4623.92   差  4.21
#4  replica-1 = 4628.13   replica-2 = 4634.68   差  6.55
#5  replica-1 = 4627.17   replica-2 = 4634.68   差  7.51
#6  replica-1 = 4627.17   replica-2 = 4634.68   差  7.51

平均差值 = 9.63，最大 = 23.11
```

**两条副本抓同一条序列，值永远不相等**——抓取时刻不同（各自按自己的 ticker）。

注意观察规律：值会"卡住"再"跳一下"（4632.80 出现两次，然后跳到 4628.13），
这是各自 scrape_interval 相位不同造成的。

### E3 Prometheus 不去重

```text
replica-1 本地 l8_card_balance = 500 条
```

它只知道自己抓的 500 条，**不知道 replica-2 存在** → 去重不可能在 Prometheus 侧发生。

### E4 后端收到两份（VM 19115，dedup.minScrapeInterval=1s）

```text
count(l8_card_balance)                  = 1000
count by (replica) (l8_card_balance)    = replica=1:500, replica=2:500
count(l8_card_balance{replica="1"})     = 500
count(l8_card_balance{replica="2"})     = 500
```

**dedup 没有合并它们** —— 因为两条序列的 `replica` 标签不同，对 VM 是两条独立序列。

✅ **这是正确且符合预期的行为**。HA 双写的正确做法就是：
**保留 replica 标签，查询时聚合掉**。

### E4b dedup 的真实语义（决定性查证）

VM 的 `/flags` 端点确认：
```text
-dedup.minScrapeInterval="1s"
```

⚠️ VM 的状态端点路径与 Prometheus 不同：
- Prometheus：`/api/v1/status/flags`
- VM：**`/flags`**（Prometheus 那个路径在 VM 上返回非 JSON）

dedup 只在**两条序列标签完全相同**且**时间戳接近**时介入。

### E5 查询时的正确去重写法（19115 上实测）

```text
l8_card_balance{idx="0001"}                        -> 2 条 ['4627.39', '4613.22']
max without(replica) (l8_card_balance{idx="0001"}) -> 1 条 ['4613.22']
avg without(replica) (l8_card_balance{idx="0001"}) -> 1 条 ['4610.305']
```

## 知识点 3：external labels

### E1 附加位置（决定性）

```text
本地查询（叶子 19110）: [__name__, idx, instance, job, zone]     <- 无 cluster/region
federate 出站          : ...,cluster="leaf-a",region="cn-south"  <- 有
```

**external_labels 不影响本地查询，只在出站（federate / remote write）时附加。**

### E2 用错的后果（决定性对照）

| 配置 | 后端条数 | 后果 |
|---|---|---|
| **有 replica**（replica=1/2） | 1000 | 保留两份，查询时可指定副本或聚合 |
| **无 replica**（两副本标签完全相同） | 500 | dedup 合并，**丢失副本信息** |

### E2b 无 replica 时代价（决定性）

后端（无 replica，dedup 合并后）连续 10 次采样同一条序列：

```text
#1  4628.54    #2  4633.73    #3  4633.73    #4  4653.12    #5  4634.08
#6  4634.08    #7  4605.37    #8  4605.37    #9  4638.41    #10 4670.7
```

值在 **4605.37 ~ 4670.70** 之间无规律跳变——因为它一会儿取副本 1 的值，一会儿取副本 2 的值。

对照：有 replica 时，两个副本各自连贯：
```text
#1  replica=1 -> 4676.85   replica=2 -> 4665.11
#2  replica=1 -> 4698.79   replica=2 -> 4675.24
#3  replica=1 -> 4698.79   replica=2 -> 4681.92
```

**结论**：无 replica 时你只能拿到"某个副本"的值，且是哪个不确定。

### E3 与告警的关系

```text
replica-1 的 external_labels = {'cluster': 'ha-cluster', 'replica': '1'}
```

告警规则在**本地**求值 → 本地查询看不到 external_labels → **不会**进入告警标签。
但告警推送到 Alertmanager 时会被附加。

## 回收课 5 伏笔：Alertmanager gossip 去重

### 集群建立

```text
端口 19120: status=ready  peers=2
端口 19121: status=ready  peers=2
```

日志关键行：
```text
msg="Waiting for gossip to settle..." interval=2s
msg="gossip not settled" polls=0 before=0 now=2 elapsed=2.000904712s
msg="gossip settled; proceeding" elapsed=10.003685466s
```

**gossip 建立约需 10~12 秒**（本例）。

### 决定性对照（通知条数）

| 场景 | Alertmanager 配置 | 通知条数 |
|---|---|---|
| **A. gossip 集群**（互指 --cluster.peer） | peers=2 | **1 条** |
| **B. 孤立双副本**（不指定 peer） | peers=1 各 | **2 条** |

**结论**：gossip 确实消除了重复通知（2 → 1）。

### 本实验踩的坑

配置里 webhook URL 写成 `l08-webhook`（遗留容器名，不存在），导致：
```text
err="Post ...: dial tcp: lookup l08-webhook on 127.0.0.11:53: server misbehaving"
notify retry canceled after 2 attempts
```

⚠️ **关键教训**：通知失败时 webhook 收到 0 条。
**"0 条"和"去重成功"看起来一样，但其实完全相反**——
必须先确认通知确实发出过，才能讨论去重。

正确做法：先看 AM 日志有没有 `Notify attempt failed`，再下结论。

## 本课推翻/修正的预设

1. **「federate 输出 untyped 会导致 rate 算不了」→ 未成立**。实测 rate 数值与叶子完全一致（0.8 = 0.8）。
2. **「honor_labels=false 会导致数据丢失/冲突」→ 部分修正**。实测两侧都是 1000 条，
   条数没变，但 `job`/`instance` 被改写成联邦 target —— 丢失的是**溯源信息**，不是数据条数。
3. **「VM 的 dedup 会合并 HA 双写」→ 不成立**（当带 replica 标签时）。
   dedup 只在标签完全相同时介入，而 HA 双写恰恰**应该**带 replica 让它不合并。

## 与课 7 的连接

课 7 讲了 external_labels 在 remote write/read 中的三段式行为（附加→附加到选择器→剥离，
显式指定反而失效）。本课补充第四段：**external_labels 不影响本地查询**。

课 7：remote write 把数据送出去（**写路径**）
课 8：federation 把数据拉过来（**读路径**），HA 双写是**冗余写**
