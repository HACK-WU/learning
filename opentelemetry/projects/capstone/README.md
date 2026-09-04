# 结课综合实战项目：从零搭建可观测栈并定位一次真实故障

> **一句话定义**：把 12 课的知识压进一个可运行的系统里——4 个服务、两层 Collector、三个信号、三种故障，最后用一次完整的定位流程把课 1 的 164 分钟结算清楚。
>
> **与知识课的区别**：课 1–课 12 是「知道」，这个项目是「做到」。所有数字都是本机跑出来的，不是从文档抄的。

---

## 一、你要交付什么

一个从零搭起的可观测栈，加一次可复现的故障定位。具体要求：

| 要求 | 本项目做法 | 覆盖阶段 |
|------|-----------|---------|
| 跨 ≥3 阶段整合 | 采集（阶段1-2）+ 管道（阶段3）+ 落地与成本（阶段4） | 全部 4 个阶段 |
| 可运行工程 | 4 个 Flask 服务 + 2 层 Collector + Jaeger/Prometheus | — |
| 三个信号打通 | trace→Jaeger、metric→Prometheus、log→文件 | 阶段 1、2、3 |
| 验证一次故障定位 | 三种故障各注入一次，逐段计时 | 阶段 4 |

**最终验收**：告警响起后，能在 5 分钟内指着某个服务的某一行说「就是这里」，而不是「大概是数据库吧」。

---

## 二、系统长什么样

### 2.1 业务链路（复刻课 1 的下单场景）

```
用户下单
   │
   ▼
checkout (5060)          入口，记录订单与耗时
   │  POST /pay
   ▼
payment (5061)           支付，记录金额与结果
   │  POST /risk/check
   ▼
risk-control (5062)      风控，N+1 故障注入点
   │  POST /user/profile
   ▼
user-profile (5063)      用户画像，慢 SQL 根因所在
   │
   ▼
MySQL（模拟）            缺索引 → 全表扫描 482 万行
```

这条链不是随便画的。`checkout → payment → risk-control → user-profile` 四层，正是课 1 里那个让运维查了四小时的结构：**每一层都可能是慢的原因，而指标只能告诉你最上面那层慢**。

### 2.2 数据链路（两层 Collector 拓扑）

```
4 个服务（OTel 自动插桩）
   │  OTLP/HTTP
   ▼
capstone-agent      轻量层：补 host.name，转发
   │  OTLP/gRPC
   ▼
capstone-gateway    治理层：限流、脱敏、补环境属性、分流
   │
   ├──→ Jaeger          trace
   ├──→ :8889           metric（Prometheus 主动来 scrape）
   └──→ /var/tmp/...    log（文件）
```

**为什么用两层而不是一层**，理由在课 11：agent 贴着应用部署，只做转发，应用侧不用关心后端是谁；重治理（脱敏、限流、路由）集中在 gateway，改策略不用重启应用。

```
┌──────────────────────────────────────────────────────────┐
│                    应用进程（4 个）                        │
│   checkout / payment / risk-control / user-profile        │
└────────────────────────┬─────────────────────────────────┘
                         │ OTLP/HTTP 4318
┌────────────────────────▼─────────────────────────────────┐
│  capstone-agent  (172.24.0.22)                           │
│  memory_limiter → resource(补 host.name) → batch          │
└────────────────────────┬─────────────────────────────────┘
                         │ OTLP/gRPC 4317
┌────────────────────────▼─────────────────────────────────┐
│  capstone-gateway (172.24.0.21)                          │
│  memory_limiter → resource → batch                       │
│  ├─ traces  → otlp/jaeger  + debug                       │
│  ├─ metrics → prometheus :8889                           │
│  └─ logs    → file /var/tmp/capstone/logs.json           │
└──────────────────────────────────────────────────────────┘
```

---

## 三、跑起来

### 3.1 前置条件（本机实测）

| 组件 | 版本 | 说明 |
|------|------|------|
| WSL Ubuntu | 24.04，内核 6.6.87.2 | Microsoft 定制内核 |
| Docker | 29.4.1 | 后端全跑容器里 |
| Python venv | `/root/otel-course/lab03/.venv` | Python 3.12.13，OTel SDK 1.44.0 |
| Collector | contrib 0.160.0 | 两个容器 |
| Jaeger | v2.20.0 | 复用课 3 的 `jaeger-lab03` |
| Prometheus | v2.53.0 | 新建 `capstone-prom`，宿主端口 46999 |

### 3.2 启动

> **脚本位置说明**：启动脚本位于 `/mnt/d/projects/learning/.probe/`（实验脚本目录，沿用课 6 起的约定），**不在 `projects/capstone/` 内**。项目目录只放源码与配置，脚本单独维护以便跨课复用。

```bash
# 1) 起 Collector 两层 + Prometheus
bash /mnt/d/projects/learning/.probe/p1_stack_up.sh

# 2) 起 4 个服务（默认两层拓扑，故障关闭）
bash /mnt/d/projects/learning/.probe/p2_services_up.sh

# 3) 验证三信号
bash /mnt/d/projects/learning/.probe/p5_verify.sh
```

### 3.3 故障注入

```bash
# 三种故障各跑一次
bash /mnt/d/projects/learning/.probe/p6_scenarios.sh

# 根因判定（叶子 span 的 Self Time）
bash /mnt/d/projects/learning/.probe/p7_rootcause.sh

# N+1 专项（Self Time 聚合视角）
bash /mnt/d/projects/learning/.probe/p8_nplus1.sh

# 收束计时
bash /mnt/d/projects/learning/.probe/p10_run_timing.sh
```

源码在 [src/](./src/)，配置在 [config/](./config/)。

---

## 四、三种故障与定位结果

### 4.1 慢 SQL（`CAP_FAULT=slowsql`）—— 课 1 的真实根因

```
端到端: 4410 ms / 4355 ms（两次独立测量，正常时 140 ms）
最慢叶子 span: user-profile:db.query.user_profile   Self Time = 4225 ms
  db.rows_scanned = 4820000
  db.index_used   = false
```

两次测量分别来自故障注入轮（4410 ms）与收束计时轮（4355 ms），差异来自模拟查询的随机抖动（±100 ms）。文档后文统一引用收束计时轮的数据。

**判定**：`db.index_used=false` + `db.rows_scanned=4820000` → 缺索引导致全表扫描。从「发现慢」到「说出这条 SQL」，机器查询耗时 26 ms。

### 4.2 N+1 查询（`CAP_FAULT=nplus1`）

```
端到端: 2616 ms（正常 140 ms，18.7 倍）
span 总数: 15 → 214（14 倍）
按 Self Time 聚合:
   2518.8 ms  x200   risk-control:db.query.rule
```

**这个故障最值得讲，因为它会躲过常规排查。**

先看两种错误视角为什么错：

```
错误视角①：最慢单个 span = 48.2 ms（payment.charge）
   → 每次 db.query.rule 只有 23 ms，没有一个异常值
   → 结论会指向错误的服务

错误视角②：同名 span 累计 duration 榜首 = POST /checkout 2616 ms
   → 入口 span 的 duration 包含了全部子 span，父子重叠会被重复计入，
     所以入口 span 永远是第一名，而它等于什么都没说

正确视角③：Self Time 聚合 = db.query.rule ×200 累计 2518.8 ms
   → Self Time = 自身 duration − 子 span 占用的时间
   → 剔除重叠后，200 次重复调用才暴露出来，占端到端 96%
```

**为什么这个结论重要**：它不依赖本项目。任何 trace 分析里，只要出现「一个操作被执行了很多次」，单看最慢 span 就会漏判——因为每一次都正常，异常的是次数本身。

### 4.3 连接池耗尽（`CAP_FAULT=pool`）

```
HTTP 502，端到端 3115 ms
最慢叶子 span: payment:payment.charge   Self Time = 3019 ms
  payment.pool_exhausted = true
  error.type             = TimeoutError
```

**判定**：`pool_exhausted=true` → 下游连接池耗尽。注意这里 HTTP 状态是 502，与课 1 的场景一致——**502 是表象，连接池才是根因**。

---

## 五、收束：课 1 的 164 分钟结算

### 5.1 逐段计时（本机实测）

| 步骤 | 机器查询 | 人工判断 | 说明 |
|------|---------|---------|------|
| 1. 哪个服务出问题 | 26 ms | ~30 s | 查 Prometheus P99 |
| 2. 找到慢的那一单 | 7 ms | ~20 s | Jaeger 按 `minDuration` 搜 |
| 3. 定位到慢的那一段 | 0 ms | ~60 s | 叶子 span 的 Self Time |
| 4. 跨服务对齐 | — | **0** | trace_id 天然打通，无需人工 join |
| 5. 读根因属性 | 0 ms | ~30 s | 属性已随 span 带出 |
| **找信息小计** | **33 ms** | **~2.3 min** | |
| 修复 | — | 3 min | **与课 1 相同** |

### 5.2 对照

| | 课 1（三控制台） | 本项目（OTel 之后） |
|---|---|---|
| 告警到知道哪个服务 | 8 min | ~30 s（人工判断，查询本身 26 ms） |
| 找到出问题的请求 | 16 min | ~20 s（人工挑选，查询本身 7 ms） |
| 定位到慢的那一段 | 17 min | ~60 s（人工分析，计算本身 0 ms） |
| **跨服务对齐** | **35 min** | **0** |
| 找到根因 | 80 min | ~30 s（读属性，无查询开销） |
| 修复 | 3 min | 3 min（不变） |
| **合计** | **164 min** | **约 5.3 min** |

上表时间均为**人工完成该步骤的总耗时**（含读结果与做判断），括号内是其中机器查询的耗时。两者不是同一口径，分开列出以免误读。

**找信息环节：156 分钟 → 2.3 分钟，约 68 倍。**

跨服务对齐从 35 分钟变成 0，是这套体系最大的单点收益——课 1 里那 35 分钟花在「把三个控制台的时间戳手工对上」，而现在一条 trace 天然含全部 4 个服务的 span。

### 5.3 必须说清楚的一句话

**不要把「查询快」包装成「故障恢复快」。**

上表里的 33 ms 是机器查询耗时，不是排查耗时。真人排查还需要读结果、做判断、确认不是抖动——这些都算进去后约 2.3 分钟。而**修复 3 分钟不变**，发布流程另计，端到端通常仍是 30–60 分钟。

课 1 的 164 分钟里，找信息 156 分钟（95.1%）、做决策 3 分钟（1.8%）。**可观测性优化的是那个 95%，不是剩下那 3%。**

---

## 六、eBPF 零插桩剖析（第四信号的现实位置）

在不停服务、不改代码的前提下，用 eBPF 抓了一次 CPU 剖析：

```
采样方式: perf CPU_CLOCK 99Hz，全系统采样 8 秒
总样本数: 15,840
Top 1:    python3   792 样本 (5.0%)
其余:     swapper/*（空闲线程）
```

**怎么读这个 5%**：本机是 20 核，8 秒 × 99 Hz × 20 核 ≈ 15,840 次采样机会（与实际总数吻合）。若 CPU 完全打满，单进程理论均值约 5%（1/20）。当时并发 8 路压测，python3 拿到 5.0% —— 说明**单个 Python 进程的 CPU 占用约等于一整个核**，其余 19 核基本空闲（所以 swapper 线程占满剩余份额）。这是一个「CPU 没打满、但单进程已吃满一核」的典型画像。

**这说明了什么，也说明了它现在还做不到什么。**

做到了：零插桩、语言无关、被测进程零 OTel 代码——这正是课 12 讲的 Profiles 第四信号的潜力所在。

没做到：**它只告诉你「python3 这个进程占了 5% CPU」，到不了「哪行代码」**。真正的 Continuous Profiling 需要把内核里的调用栈符号化成函数名，还需要一个能接收 Profiles 的后端。而本机 Collector 0.160.0 没有 profiles pipeline（该信号仍是 **Alpha**，2026-09-04 复核），所以这一步只能停在进程级。

**结论**：Profiles 是「锦上添花」，不是「雪定位根因的必需品」。本次三种故障全部靠 trace + metric 定位到具体属性和具体服务——**不要因为 Profiles 听起来高级就把它放进关键定位链路**。

---

## 七、本项目踩到的坑（每条都实测卡住过）

### 7.1 自动插桩与手工初始化冲突 —— 最隐蔽的一个

```
Overriding of current TracerProvider is not allowed
```

用 `opentelemetry-instrument` 包装启动时，CLI 会**先**建好三个 Provider 再 import 应用代码。此时代码里再调 `set_tracer_provider()`，**不抛异常**，只打印一行警告然后忽略。结果：代码里配的 resource（`deployment.environment.name` 等）全部丢失，而调用方毫无察觉。

**修法**：先探测 Provider 是否已存在，已存在就复用，不存在才自己建。见 [otel_setup.py](./src/common/otel_setup.py)。

```python
auto = isinstance(trace.get_tracer_provider(), SDKTracerProvider)
if auto:
    tp = trace.get_tracer_provider()   # 复用 CLI 建的，绝不重复 set
else:
    tp, mp, lp = _own_providers(...)   # 自己建
```

修完再查 Jaeger，四个服务的 `env=capstone-lab / ns=capstone / ver=1.0.0` 全部正确。

### 7.2 `resource` processor 的 `upsert` 不插入

以为配了就能补属性：

```yaml
- key: deployment.environment.name
  action: upsert     # ← 错
```

`upsert` 只在**键已存在**时覆盖。服务的 resource 里没有这个键，`upsert` 静默不生效（Jaeger 里显示为 null）。无条件写入必须用 `insert`。

### 7.3 指标名会被追加单位后缀

查 `payment_amount_count` 得到 NO DATA，一度以为指标丢了。实际是 OTel→Prometheus 转换时追加了单位：

| OTel 指标名（单位） | Prometheus 名 |
|---|---|
| `payment_amount`（CNY） | `payment_amount_CNY` |
| `user_profile_query_duration_ms`（ms） | `user_profile_query_duration_ms_milliseconds` |

### 7.4 指标默认 60 秒才导出一次

验证时等了 10 秒查不到指标，以为是链路断了。实际 `PeriodicExportingMetricReader` 默认间隔 60 秒（读 `OTEL_METRIC_EXPORT_INTERVAL`）。演示环境设成 5000 才合理——**生产环境不要设这么短**，会增加 Collector 压力。

### 7.5 其它四条

- **`--service_version` 不是合法 CLI 参数**：只有 `--service_name` 和 `--resource_attributes`，版本要走后者。
- **`opentelemetry.sdk._logs` 没有 `get_logger_provider()`**：日志模块只导出 `LoggerProvider`，且顶层 `opentelemetry.logs` 在 1.44.0 下不存在。所以复用模式下拿不到 CLI 建的 logger 句柄，只能自己建一个。
- **模块文件名不能用连字符**：Python 模块名不允许 `risk-control.py`，但 `service.name` 应该用连字符。两者要分开——文件名 `risk_control.py`，`service.name` 通过 CLI 设为 `risk-control`。
- **孤儿 docker-proxy 占端口**：课 12 已记录。本项目 agent 不映射宿主端口，用容器 IP 直连规避。

---

## 八、代码里的生产规模自检

按评审必查项 #28，讲义里凡是「循环处理 N 条」的示例，都要问一句 N 变成 10 万会怎样。

### 8.1 N+1 反例（循环体内有数据库操作）

```python
for i in range(PAGE_SIZE):
    with tracer.start_as_current_span("db.query.rule") as sub:
        _sleep(0.003)          # ← 循环体里有数据库往返
```

N=200 时 0.6 秒；**N=10 万时是 300 秒以上**，单请求直接拖垮服务。这就是为什么它在 200 条时看起来「还行」，上线后却成为雪崩点。

### 8.2 批量正例（循环体内只有内存计算）

```python
with tracer.start_as_current_span("db.query.rules_batch") as sub:
    _sleep(0.05)               # 一次批量查询
# 后续循环只在内存里算，不再碰数据库
```

规则数放大到 10 万，也只是多几次批量分页，不是多 10 万次往返。

### 8.3 异常处理不用裸 `except`

```python
# checkout.py
except Exception as exc:          # 反例：会把「支付失败」变成「下单成功但没扣款」
    ...

# 本项目写法：显式捕获下游失败，并写入 error.type 让 trace 可见
except Exception as exc:
    span.record_exception(exc)
    span.set_attribute("error.type", type(exc).__name__)
    order_counter.add(1, {"checkout.result": "error"})
    return jsonify({...}), 502
```

这里仍捕获宽泛异常，但**把它记进 span 并返回明确失败**，而不是静默跳过。裸 `except: pass` 才是要禁的写法。

---

## 九、与 12 课知识的对应

| 本项目组件 | 对应课程 |
|---|---|
| 三信号采集、自动插桩 | 课 1、2、5 |
| trace_id 跨服务传播 | 课 2、3 |
| Collector 两层拓扑 | 课 10、11 |
| metric（counter / histogram） | 课 6、7 |
| log 与 trace 关联 | 课 8 |
| 语义约定、属性命名 | 课 9 |
| 脱敏、限流、processor 顺序 | 课 10 |
| 采样与成本治理 | 课 11 |
| eBPF / Profiles（Alpha） | 课 12 |
| 收束量化 | 课 12 |

---

## 十、未验证项（诚实披露）

1. **Profiles 端到端**：本机的往返验证只到 pprof 层面，没有真实 Collector 的 profiles pipeline（该信号仍 Alpha）。
2. **日志未进 Jaeger**：Jaeger 不接受日志（`/v1/logs` 返回 404 Unimplemented），本机无 Loki/ES，日志只能落地文件验证。
3. **Native Histograms**：Prometheus 是 v2.53.0，课 7 已标注完整链路未实测。
4. **eBPF 只到进程级**：无法符号化到函数名，原因见第六节。
5. **人工判断耗时是估算**：机器查询耗时是实测的（26ms/7ms/0ms），人工判断的「约 30 秒」是按真实操作节奏估的，**不是秒表掐出来的**。

---

## 十一、复盘：如果重做一次

1. **先跑通再治理**：第一版就把脱敏、限流、两层拓扑全配上，结果排查时分不清是管道问题还是业务问题。应该先用最小管道验证数据能到，再逐层加治理。
2. **指标名一定要先 `curl` 一遍再写查询**：靠猜 `payment_amount_count` 浪费了两轮。
3. **Self Time 应该作为默认视图**：Jaeger 默认按 duration 排序，而 duration 对父子重叠的 span 毫无意义。
4. **故障注入开关要做成显式枚举**：早期版本用布尔变量，三种故障互斥关系不清，容易同时触发两个。

---

## 十二、相关文档

- 项目源码：[src/](./src/)
- 管道配置：[config/](./config/)
- 课程目录：[02-课程目录.md](../../02-课程目录.md)
- 学习档案：[00-学习档案.md](../../00-学习档案.md)
- 课 1（对照基准）：[lesson-01-一次502的四小时.md](../../stages/1-三个控制台的四小时/lessons/lesson-01-一次502的四小时.md)
- 课 12（收束方法论）：[lesson-12-选型决策与收束.md](../../stages/4-生产落地/lessons/lesson-12-选型决策与收束.md)

---

> **下一项**：`final-课程手册.md`（全部课时汇总手册）
