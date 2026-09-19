# 课 16 · 结课会诊地图：从症状到动作

> 阶段 5 · 综合会诊 · 结课收束课
> 这节课不再引入新子系统，而是把前 15 课压成一套可复用的诊断顺序：先定范围，再取证据，最后选择带回滚出口的动作。

📖 **文档核对留痕（核查于 2026-09）**：本课是汇总与决策课，不新增独立事实基线。命令语义与边界沿用前课已核对的 [man7.org 精简索引](../../../web-index/man7.org/index.md)；cgroup v2、Docker 资源限制和系统调用页面均回指原课官方文档。下文的阈值和选型是诊断启发式，不是对所有负载成立的硬规则。

## 本课在故事主线中的情节定位

周五晚，order-service 再次出现 P99 上升、load 变高、CPU 接近 100%、buff/cache 很大、fd 持续增长。你不再把五个数字拼成一个结论，而是问：**哪个对象在等什么？这条证据能排除什么？动作会把代价转移到哪里？**

课程故事在这里闭环：

机器有多大马力 → 数据在哪里 → 谁在排队 → 数据如何进出 → 症状如何变成动作

## 🎯 本课目标

- 用一张“症状 → 机制 → 证据 → 动作”的地图索引全部 48 个知识点
- 用四张决策卡讨论线程池 / 并发度、同步 / 异步、零拷贝、GPU，并说出适用条件和改选出口
- 把“看起来像性能问题”的现象拆成 CPU、调度、内存、文件、网络和应用设计几条证据链
- 知道下一步深入性能工程、eBPF 观测或内核机制的入口

## 📌 知识点导航

| 知识点 | 本课产出 |
|---|---|
| [16.1 全景会诊地图](#161-全景会诊地图) | 48 行症状 → 机制 → 先查 → 动作索引 |
| [16.2 四张设计决策卡](#162-四张设计决策卡) | 四张带临界条件和改选出口的卡 |
| [16.3 后续学习地图](#163-后续学习地图) | 三条路线、课程联动和阅读定位 |

---

# 第一幕：一条告警，五个方向

## 1.1 场景引入：告警里没有“真凶”三个字

这些现象可以同时出现，却不一定来自同一个原因：

- CPU 100% 可能是业务计算、系统调用、忙等，也可能是盯错了父进程
- load 高可能是 CPU 队列，也可能是不可中断 I/O 等待
- buff/cache 大可能是正常 Page Cache，也可能伴随回收压力
- fd 多可能是稳定长连接，也可能是生命周期泄漏
- P99 高可能是线程排队、锁竞争、I/O 等待或下游连接池耗尽

> **症状是入口，不是结论。**

## 1.2 认知冲突：先调参数可能把问题变糟

| 直觉动作 | 可能暂时改善 | 新增账单 |
|---|---|---|
| 扩线程池 | 隐藏 I/O 等待 | 上下文切换、栈 / RSS、锁竞争 |
| 调高 fd 上限 | 延后 EMFILE | 泄漏继续，内核对象继续涨 |
| 清 Page Cache | free 看起来更空 | 后续读变慢，破坏热数据 |
| 改成异步 | 少量线程承载更多等待 | 状态机、取消、背压、错误传播 |
| 上零拷贝 | 大文件纯转发少搬一次 | 短写、EAGAIN、协议加工 |
| 上 GPU | 大批量并行计算可能更快 | 传输、排队、驱动和发布成本 |

### 一句话本质 + 处境对照

> **一句话本质：性能会诊不是找一个“最优参数”，而是用证据把瓶颈定位到正确的资源或路径，再选择代价更小的动作。**

| 没学会会诊 | 学完本课 |
|---|---|
| “CPU 100%，线程加倍。” | “先找 PID / TID，拆 user / system，再看 run queue 和切换。” |
| “内存满了，清 cache。” | “先分 RSS、Page Cache、Dirty、cgroup limit，再看是否真的有压力。” |
| “连接多，改异步。” | “先看连接数 × I/O 密度、handler 是否阻塞、fd / 内存和下游是否有余量。” |

---

# 第二幕：同一个指标，可能通向不同机制

## 2.1 四个常见误判

1. **把相关性当因果**：load、CPU、延迟一起升高，只说明时间上相关；还要知道等待对象和变化窗口。
2. **只看全局，不看对象**：全局 CPU 80% 不等于服务进程 80%；父进程低也不等于 worker 空闲。
3. **把上限当健康指标**：fd 上限高、cgroup limit 高、线程数多，都不等于工作集和生命周期健康。
4. **把工具名当方法**：top、free、lsof 只是入口；问题应该决定工具，而不是工具名决定结论。

## 2.2 会诊四步

```text
症状
  ↓ 1. 定义范围：主机 / 容器 / 进程 / 线程 / fd / 文件
现象
  ↓ 2. 选窗口：瞬时值、累计计数，还是增长趋势
证据
  ↓ 3. 对照机制：CPU、调度、内存、文件、网络、应用
动作
  ↓ 4. 先止血，再修复；一次只改一类变量并复测
```

最小证据卡：

| 字段 | 示例 |
|---|---|
| 症状 | P99 从 80 ms 升到 900 ms |
| 范围 | order-service 容器，过去 10 分钟 |
| 对象 | PID / TID / fd / cgroup |
| 变化 | us / sy / wa、run queue、fd 是否单调 |
| 假设 | 热点计算、下游等待、fd 泄漏 |
| 第一动作 | 采样 30 秒，保存原始输出，不先重启 |

---

# 第三幕：把 48 个知识点折叠成一张地图

## 3.1 一眼全局图

![Linux 操作系统基础课程收束地图](/Users/wuyongping/Desktop/learning/operating-system/stages/5-综合会诊/assets/course-closing-map.svg)

上方五个阶段是知识路径；下方四张卡是设计分叉。红色文字专门标出“什么时候改选另一个”。图和表都是索引，不是自动诊断器。

## 16.1 全景会诊地图

### 48 个知识点索引式会诊地图

读每行时按四个动作走：**现象 → 可能机制 → 先查什么 → 调什么 / 回看什么**。

### 阶段 1 · 算力的来源

| 知识点 | 可能机制 | 先查什么 | 动作 / 回看 |
|---|---|---|---|
| 1.1 CPU 的最小行动循环：取指-译码-执行 | 指令流、分支、数据依赖决定吞吐 | 热点与采样 profile | 回看课 1；先优化算法 / 数据访问 |
| 1.2 从源代码到指令：你的代码怎么“上机” | 编译、解释、JIT、运行时边界不同 | 构建产物、启动参数、profile | 回看课 1；确认测的是哪份产物 |
| 1.3 实验环境里的“Linux”到底是谁 | macOS、Docker VM 内核、Ubuntu 用户态分层 | uname、镜像和容器范围 | 回看课 1；先确认实验边界 |
| 2.1 物理核、逻辑核与超线程 | 逻辑 CPU 不等于同样数量的物理核 | nproc、lscpu、CPU 配额 | 回看课 2；并发上限以实测为准 |
| 2.2 多核怎么共享内存：SMP 与 NUMA | 共享内存也可能有本地 / 远端代价 | CPU 拓扑、内存节点、绑核 | 回看课 2；做亲和性 / 布局对照 |
| 2.3 并行度上限：Amdahl 定律直觉 | 串行段、同步和调度开销限制加速 | 串行 profile、锁、扩展性曲线 | 回看课 2；不要把线程数等同核数 |
| 3.1 两种芯片哲学：CPU 少而强，GPU 多而简 | 执行单元组织方式不同，吞吐与单任务延迟取舍不同 | 任务形状、批量、设备利用率 | 回看课 3；先判断数据并行度 |
| 3.2 什么活适合 GPU，什么活搬过去反而慢 | 传输、排队和分支可能吃掉并行收益 | 端到端耗时、批量、传输时间 | 回看课 3；用目标设备做对照基准 |
| 3.3 后端服务的 GPU 决策卡 | 服务请求的延迟、批量和运维边界决定是否值得 | 请求粒度、SLA、驱动与发布链 | 回看课 3；回看 16.2-D，满足条件才上 GPU |

### 阶段 2 · 存储金字塔

| 知识点 | 可能机制 | 先查什么 | 动作 / 回看 |
|---|---|---|---|
| 4.1 存储金字塔与速度鸿沟 | 离 CPU 越远，延迟 / 带宽账不同 | profile、cache miss、I/O | 回看课 4；优先改变访问模式 |
| 4.2 cache line 与局部性原理 | 连续访问受益，随机追逐放大等待 | 数组 / 链表、访问模式 | 回看课 4；重排数据，不只加线程 |
| 4.3 缓存一致性与伪共享 | 共享 cache line 产生失效流量 | 共享字段、扩展性 | 回看课 4；拆分高频写字段 |
| 5.1 虚拟地址空间与页表 | 地址转换、权限和隔离依赖页表 | /proc/PID/maps、VSZ、RSS | 回看课 5；分开地址预留与驻留 |
| 5.2 缺页中断与按需加载 | 首次访问或页面不在内存要填充 / 调入 | fault、延迟、映射类型 | 回看课 5；预热前先验证收益 |
| 5.3 内存不足的两种死法：换页与 OOM | 回收 / 换页变慢，或 limit 触发杀进程 | vmstat、free、memory.events | 回看课 5；先减峰值再谈加 limit |
| 6.1 Page Cache：内核替你记的文件小抄 | 文件数据可能被缓存，读写路径不等于直接访问磁盘 | free、meminfo、重复读对照 | 回看课 6；先判断 cache 是否可回收 |
| 6.2 buffer 与脏页回写 | 写入先进入缓存，Dirty 需要按策略回写 | Dirty、writeback、sync 前后对照 | 回看课 6；关注回写压力，不把 cache 当泄漏 |
| 6.3 free -h 解读实战 | total / used / available / cache 不是同一笔账 | free -h、meminfo、时间窗口 | 回看课 6；结合 RSS、Dirty 和 cgroup 读 |

### 阶段 3 · 进程与调度

| 知识点 | 可能机制 | 先查什么 | 动作 / 回看 |
|---|---|---|---|
| 7.1 进程：资源的独立包房 | 地址空间、fd 表和资源边界按进程组织 | ps、/proc、进程树 | 回看课 7；确认父子归属 |
| 7.2 线程：共享正厅的服务员 | 共享进程资源，但有独立栈和调度身份 | ps -L、task、TID CPU | 回看课 7；定位到线程 |
| 7.3 进程 vs 线程选型的第一性原理 | 共享、隔离、创建成本、故障域权衡 | 数据共享和故障传播 | 回看课 7；按边界选模型 |
| 8.1 时间片与 CFS 直觉 | runnable 实体竞争执行资源 | vmstat r、schedstat、pidstat | 回看课 8；先减少无效 runnable |
| 8.2 上下文切换的票价 | 切换损失局部性并产生调度成本 | vmstat cs、pidstat -w、线程数 | 回看课 8；降低无效线程 / 唤醒 |
| 8.3 用户态、内核态与系统调用 | user 与 system 都是 CPU 账 | top us/sy、strace、profile | 回看课 8；批量化或修 syscall 热点 |
| 9.1 load 是“排队 + 在办”的人数，不是 CPU 使用率 | runnable 和部分不可中断等待进入统计 | /proc/loadavg、vmstat r/b | 回看课 9；先分 CPU 队列与 I/O 等待 |
| 9.2 load 高、CPU 闲的两种真相 | D 状态、I/O 或 VM / 容器边界造成背离 | ps 状态、wchan、iostat | 回看课 9；找等待对象 |
| 9.3 并发 vs 并行：理解异步前的最后一块地基 | 同时处理不等于同时执行 | 连接数、执行资源、事件循环 | 回看课 9；进入本课 16.2-B |

### 阶段 4 · IO 与异步

| 知识点 | 可能机制 | 先查什么 | 动作 / 回看 |
|---|---|---|---|
| 10.1 fd：进程的窗口编号 | fd 指向文件、socket、pipe 等对象 | /proc/PID/fd、lsof、限制值 | 回看课 10；看类型和趋势 |
| 10.2 一切皆文件：VFS 的统一接口 | 接口统一，底层等待语义不统一 | lsof 类型、syscall、socket 状态 | 回看课 10；不要把所有 fd 等价 |
| 10.3 句柄上限与泄漏 | 上限被触碰或 close 路径缺失 | prlimit、file-nr、fd 趋势 | 回看课 10；止血调上限，根治生命周期 |
| 11.1 两个维度到底在说什么（四象限） | 阻塞 / 非阻塞与同步 / 异步是两轴 | 返回值、线程状态、完成通知 | 回看课 11；先按两轴描述事实 |
| 11.2 阻塞时线程与 CPU 各自在哪 | 阻塞线程睡眠，CPU 可运行别的任务；忙等相反 | ps、wchan、top、strace | 回看课 11；分合理等待与忙等 |
| 11.3 异步的代价与适用边界 | 少占等待线程，但增加状态和错误路径 | 连接数、I/O 等待、循环阻塞 | 回看课 11；看 16.2-B |
| 12.1 select / poll / epoll：三代登记处 | 遍历、就绪通知与内核状态不同 | fd 数、就绪密度、事件循环 CPU | 回看课 12；fd 多不等于必选 epoll |
| 12.2 epoll 三件套与事件循环 | ctl 管理兴趣列表，wait 取就绪事件 | syscall、profile、EAGAIN | 回看课 12；核对 LT / ET 与短读写 |
| 12.3 Reactor 直觉：你天天在用的东西 | 分发器给 handler，handler 仍可能阻塞 | handler 耗时、循环延迟 | 回看课 12；重活移出事件循环 |
| 13.1 一次文件下载，数据搬了几次家 | 用户态、内核、socket、DMA 有搬运路径 | strace、吞吐、CPU、方向 | 回看课 13；先画路径 |
| 13.2 mmap 与 sendfile：省一次是一次 | 少部分用户态搬运，但语义不同 | 返回值、短写、页 fault | 回看课 13；纯转发测 sendfile |
| 13.3 值不值得上：零拷贝的决策边界 | 大块、纯转发更能摊薄复杂度 | 数据大小、加工比例、CPU | 回看课 13；看 16.2-C |

### 阶段 5 · 综合会诊

| 知识点 | 可能机制 | 先查什么 | 动作 / 回看 |
|---|---|---|---|
| 14.1 一组指标一个工具 | 对象、窗口、单位不同 | top、vmstat、free、iostat、lsof、ss | 回看课 14；先写问题 |
| 14.2 读数的口径陷阱 | 全局 / 容器 / 进程、瞬时 / 累计易混 | 窗口、PID 范围、字段定义 | 回看课 14；保留原始口径 |
| 14.3 压力复现实验 | 无可重复刺激就难建因果 | stress-ng、fd、内存和事件 | 回看课 14；小范围、可回收 |
| 15.1 病例一：CPU 100% 的定位链 | 热点可能在子进程 / 线程、user / system | PID / TID、pidstat、strace、队列 | 回看课 15；先找真正消耗者 |
| 15.2 病例二：Too many open files | EMFILE 是上限结果，不等于内核坏 | prlimit、fd 类型、lsof、趋势 | 回看课 15；修 close / 超时 / 池化 |
| 15.3 病例三：内存失踪 | RSS、Page Cache、Dirty、limit 是不同账本 | free、status、events、inspect | 回看课 15；不要直接清 cache |
| 16.1 全景会诊地图 | 复杂问题先定位子系统再下钻 | 本表 + 证据卡 | 从最小证据开始 |
| 16.2 四张设计决策卡 | 选型是约束、测量、代价的比较 | 四卡和小基准 | 先实验，再承担复杂度 |
| 16.3 后续学习地图 | 基础后需选一条纵深路线 | 性能 / eBPF / 内核 | 按问题和时间预算选 |

### 16.1 的六要素收束

**一句话定义**：全景会诊地图把现象、机制、证据和动作连成索引，不把每个指标映射成唯一答案。
**直觉与边界**：它像医院分诊台，先分科再安排检查；Linux 问题常跨子系统，一条症状可能要同时挂多个“科室”。
**核心原理**：对象、窗口、单位必须对齐——主机 / 容器 / 进程 / 线程 / fd；瞬时 / 累计 / 趋势；百分比 / 页 / 字节 / 次数 / 毫秒。
**示例**：课 15 的真实证据链是匿名内存 96 MiB → RssAnon 约 100 MiB，读取 64 MiB 文件 → Cached 约增长 64 MiB，128 MiB cgroup → 退出码 137 且 OOMKilled=true。
**常见误区**：把 buff/cache 当进程占用、把 VSZ 当物理驻留、把 lsof 行数当唯一 fd 数、把 load 当 CPU 百分比、把一次复现写成普遍阈值。
**一句话记住**：先定对象、窗口和单位，再沿机制链选工具。
**官方文档**：[proc_pid_status(5)](https://man7.org/linux/man-pages/man5/proc_pid_status.5.html)、[proc_meminfo(5)](https://man7.org/linux/man-pages/man5/proc_meminfo.5.html)、[proc_loadavg(5)](https://man7.org/linux/man-pages/man5/proc_loadavg.5.html)、[cgroup v2](https://docs.kernel.org/admin-guide/cgroup-v2.html)、[Docker 资源约束](https://docs.docker.com/engine/containers/resource_constraints/)。

---

# 第四幕：四张卡，把知识变成设计选择

## 16.2 四张设计决策卡

### 决策卡的共同模板

**一句话定义**：决策卡是带有适用条件、反例、证据和改选出口的小型选型协议。
**直觉与边界**：像登山装备卡，天气、坡度和负重不同，装备不同；软件约束也会随流量、数据大小和下游状态变化。
**核心原理**：

```text
工作负载是什么？
  → 哪个资源是瓶颈？
  → 复杂度和搬运成本是多少？
  → 先做什么小实验？
  → 什么现象出现时改选另一个？
```

### 16.2-A 决策卡：线程池 / 并发度开多大

| 维度 | 判断 |
|---|---|
| CPU 计算 | 受可用 CPU、串行部分、锁和切换限制 |
| I/O 等待 | 增并发可隐藏等待，但消耗 fd、内存、连接和下游容量 |
| 第一证据 | CPU、run queue、context switch、I/O wait、P99、下游队列一起看 |
| 小实验 | 固定请求量，改变并发度，记录吞吐、P99、CPU、cs、RSS、错误率 |
| 改选出口 | CPU 饱和且 cs / run queue / P99 一起升 → 降并发；CPU 有余量且大量阻塞 → 才考虑增加 |

**直觉与边界**：像餐厅服务员；等厨房时可多接单，但厨房、桌子和收银台仍是瓶颈。
**核心原理**：Amdahl 提醒我们串行段不能被线程消灭；额外线程还会支付切换、锁和 cache 失效。I/O 线程变多也可能只是把排队转移到连接池。
**示例**：接口 70% 等下游、30% 做计算时，起初增并发可能提高吞吐；到 CPU 或下游上限后，吞吐趋平而 P99 和切换继续升。
**常见误区**：线程数固定等于逻辑 CPU；只看吞吐；线程池和连接池同时扩；只增上限不设超时 / 背压。
**一句话记住**：CPU 活多时线程不是越多越好；I/O 多时也要先确认下游和 fd 有余量。
**官方文档**：[sched(7)](https://man7.org/linux/man-pages/man7/sched.7.html)、[pidstat(1)](https://man7.org/linux/man-pages/man1/pidstat.1.html)、[Docker 资源约束](https://docs.docker.com/engine/containers/resource_constraints/)。

### 16.2-B 决策卡：同步还是异步

| 维度 | 更偏同步 | 更偏异步 |
|---|---|---|
| 连接数 | 少到中等 | 很多连接 |
| I/O 密度 | 等待短或可接受线程成本 | 大多数时间在等 I/O |
| CPU 工作 | 请求内 CPU 段明显 | handler 短，重活可移出循环 |
| 代码与运维 | 直线流程、简单错误路径 | 接受状态机、取消、背压和复杂错误传播 |
| 改选出口 | 连接少、CPU 重、异步复杂度超过收益 → 同步 | 线程被 I/O 卡住，或事件循环被阻塞 → 异步或混合 |

**直觉与边界**：像柜台服务与取号回调；异步能让柜台接更多等待者，但回调状态也要被管理。
**核心原理**：同步 / 异步与阻塞 / 非阻塞是两条轴；epoll 只提供 fd 就绪通知，不能保证 handler 不做长计算或阻塞调用。
**示例**：几十个长连接且每次 CPU 计算重，不必为了流行而改异步；大量空闲网络连接的网关，事件驱动可能减少线程成本，但压缩 / 加密仍应有 worker 边界。
**常见误区**：异步一定更快；非阻塞等于不用等待；只数连接不看等待比例；把阻塞数据库调用塞进事件循环。
**一句话记住**：连接多且大多在等 I/O，异步才可能值得；简单、CPU 重、阻塞点复杂时同步更稳。
**官方文档**：[epoll(7)](https://man7.org/linux/man-pages/man7/epoll.7.html)、[epoll_wait(2)](https://man7.org/linux/man-pages/man2/epoll_wait.2.html)、[aio(7)](https://man7.org/linux/man-pages/man7/aio.7.html)。

### 16.2-C 决策卡：要不要零拷贝

| 维度 | 更可能值得 | 改选普通路径 |
|---|---|---|
| 数据路径 | 大文件 → socket，纯转发 | 需要解析、改写、压缩、加密 |
| 数据规模 | 大块、持续、搬运占明显 CPU | 小消息、短请求 |
| 证据 | CPU / syscall 确实是瓶颈 | 网络、磁盘或下游才是瓶颈 |
| 小实验 | 对照 read/write 与 sendfile，测端到端吞吐、CPU、短写 | 若收益小或边界复杂，保留普通拷贝 |
| 改选出口 | 加工比例升、消息变小、搬运不再是瓶颈 → 改回普通路径 | 纯大块转发且搬运占比高 → 进入零拷贝基准 |

**直觉与边界**：像把货物直接从仓库送到装车口；若中间必须质检、改包装，仍要打开货物。
**核心原理**：零拷贝通常是减少用户态参与的搬运，不是完全没有复制；还要处理短写、EAGAIN、文件类型和协议边界。
```text
普通路径：file → kernel buffer → user buffer → socket buffer → NIC
优化候选：file → kernel / socket path → NIC
```
**示例**：课 13 的 16 MiB 对照表明路径和 syscall 组成不同；静态大文件可测 sendfile，解密 / 压缩 / 加水印则不要硬套。
**常见误区**：零拷贝等于没有复制；忽略短写；只看吞吐；把大文件结论套给小包。
**一句话记住**：数据大、路径纯、搬运是瓶颈时才值得。
**官方文档**：[sendfile(2)](https://man7.org/linux/man-pages/man2/sendfile.2.html)、[splice(2)](https://man7.org/linux/man-pages/man2/splice.2.html)、[mmap(2)](https://man7.org/linux/man-pages/man2/mmap.2.html)。

### 16.2-D 决策卡：要不要 GPU

| 维度 | 更可能适合 GPU | 更可能留在 CPU |
|---|---|---|
| 数据形状 | 大量元素做相似操作 | 分支多、指针追逐、不规则 |
| 批量 | 大且持续 | 小请求、强交互、低延迟 |
| 搬运 | 数据可驻留或传输可摊薄 | CPU ↔ 设备传输占主要时间 |
| 软件 | 成熟库、驱动、监控和发布链 | 自维护 kernel，设备和权限不稳定 |
| 改选出口 | 批量变小、分支变多、传输排队超过计算 → CPU | 大批量规则计算持续占满 CPU → 在真实设备上做基准 |

**直觉与边界**：像把一大盆同样的豆子交给很多小工；如果每颗豆子都要不同判断，分工和传递反而更慢。
**核心原理**：GPU 总账包括准备、传输、排队、kernel、同步和回传；kernel 很快不等于请求很快。
**示例**：矩阵、图像批处理、向量相似度可预研 GPU；单条订单规则、分支多的小任务先用 CPU。当前 macOS arm64 + Docker Desktop 没有 CUDA GPU 直通，本课不编造 GPU 实测。
**常见误区**：可并行就一定适合；只测 kernel；忽略驱动、镜像、权限和故障恢复。
**一句话记住**：大批量、同形状、能摊薄搬运的活才优先考虑 GPU。
**官方文档**：[Linux DMA API HOWTO](https://docs.kernel.org/core-api/dma-api-howto.html)、[Docker 资源约束](https://docs.docker.com/engine/containers/resource_constraints/)。

### 四张卡共同的反模式

- 四个开关一起打开，导致无法归因
- 把一次基准的结果写成所有环境的阈值
- 只看吞吐，不看 P99、错误率、内存、fd 和下游
- 只有“怎么改”，没有“什么时候回滚”
- 认为工具更高级，就可以跳过对象、窗口和单位

---

# 第五幕：终局演练与后续路线

## 5.1 终局演练：把“接口变慢”走完一遍

以下数字是**故事演练输入，不是本机实测数字**：P99 80 ms → 900 ms，load 2 → 38，业务容器 CPU 近 100%，buff/cache 六成，fd 约 8 万。

### 先定范围

```bash
docker stats --no-stream order-service
docker top order-service -eo pid,ppid,stat,pcpu,pmem,comm
docker exec order-service sh -lc 'cat /proc/loadavg; grep -E "^(VmRSS|RssAnon|RssFile|VmSwap):" /proc/1/status'
```

### 再拆 CPU、调度和等待

```bash
docker exec order-service sh -lc 'vmstat 1 5'
docker exec order-service sh -lc 'pidstat -u -w -p ALL 1 5'
docker exec order-service sh -lc 'ps -eLo pid,tid,ppid,stat,pcpu,psr,comm --sort=-pcpu | head -20'
```

us 高先看业务计算，sy 高再看 syscall / 网络，wa 高继续看存储 / 网络等待；r 与 cs 同时高时，线程或 runnable 可能已经超过有效并行度。父进程低而子线程高，回到课 15.1 的真正消耗者链路。

### 再拆内存三本账

```bash
docker exec order-service sh -lc 'free -h; grep -E "^(Cached|Buffers|Dirty|MemAvailable|SwapFree):" /proc/meminfo'
docker exec order-service sh -lc 'grep -E "^(VmSize|VmRSS|RssAnon|RssFile|VmSwap):" /proc/1/status'
docker inspect order-service --format 'memory={{.HostConfig.Memory}} oom={{.State.OOMKilled}} exit={{.State.ExitCode}}'
```

再看 cgroup 的 memory.current、memory.max、memory.events。cache 大且 MemAvailable 充足，可能是正常可回收缓存；匿名 RSS 与 current 同步增长并触碰 limit，才更像工作集 / 泄漏；OOM 后保留现场，不用清 cache 掩盖根因。

### 最后拆 fd 与连接

```bash
docker exec order-service sh -lc 'ulimit -n; find /proc/1/fd -mindepth 1 -maxdepth 1 | wc -l'
docker exec order-service sh -lc 'for x in /proc/1/fd/*; do readlink "$x"; done 2>/dev/null | sort | uniq -c | sort -nr | head'
docker exec order-service sh -lc 'ss -s'
```

fd 按分钟单调增长，优先查 close、超时和连接池生命周期；主要是稳定长连接，则 8 万本身不足以证明泄漏。记录类型分布和趋势，再决定止血动作。

### 动作必须带出口

- CPU 热点明确：优化热点、减少无效唤醒，必要时降低并发
- I/O 等待明确：查下游容量、连接池、磁盘 / 网络队列
- fd 泄漏明确：先限流 / 单实例止血，再修 close、超时、池化
- cgroup OOM 明确：降低峰值和工作集；调 limit 只是容量决策
- 纯大文件转发明确：进入零拷贝基准；需要加工则不强套
- 批量并行且有 GPU：在真实目标设备做端到端基准；当前环境不假测

## 5.2 小测：用证据回答，而不是用口号回答

1. load 高、CPU 不高：先查 vmstat 的 r / b、进程状态、wchan、I/O 和观测范围，不能直接说 CPU 不够。
2. buff/cache 大：看 MemAvailable、Cached、Dirty、RSS、RssAnon、RssFile 和 cgroup events，不能直接清。
3. 线程 32 → 128，吞吐不升而 P99 / cs 升：先回到拐点附近，检查 CPU、锁和下游排队。
4. 支持 epoll 不等于全异步：epoll 只处理就绪通知，handler 仍可能做 CPU 重活或阻塞调用。
5. 普通 read/write 可能更好：消息小、需要加工、或搬运不是瓶颈时，零拷贝复杂度不值得。
6. GPU kernel 快但端到端慢：把准备、传输、排队、同步和回传纳入总账。
7. fd 上限调高后错误消失：只完成止血，仍需查增长趋势和关闭路径。

## 16.3 后续学习地图

### 三条后续学习地图

### 路线一：性能工程

回答“哪里慢、慢了多少、改动是否有效”。顺序是：基准与 SLO → CPU / 内存 / I/O / 锁 / 网络分层剖析 → perf、采样 profile、火焰图 → 可回滚、可复测的优化。起点是课 14–15 的观测和病例链。

### 路线二：eBPF 观测

回答“内核里到底发生了什么”。顺序是：tracepoint / kprobe / uprobes → bpftrace / BCC → 关联 PID / TID / cgroup → verifier、权限、版本、开销和回滚。工具更强，不代表问题定义可以更含糊。

### 路线三：内核机制

回答“页表、调度器、VFS、块层和网络栈为什么这样工作”。顺序是：man 页和 kernel.org 接口边界 → 选择 mm / sched / fs / net 一个子系统 → 沿一次 syscall / tracepoint 读源码 → 用实验验证。

### 路线选择表

| 你最常问的问题 | 起步路线 |
|---|---|
| 哪里慢，改完有没有快 | 性能工程 |
| 内核事件和容器行为是什么 | eBPF |
| 为什么会有页 fault、切换、epoll 行为 | 内核机制 |

### 与既有课程联动

| 当前问题 | 回看课程 | 为什么联动 |
|---|---|---|
| 容器被杀、CPU / 内存限额 | docker/ 资源限制与隔离 | cgroup 是容器资源边界底座 |
| Go goroutine 多、网络等待多 | go/ 并发与 netpoller | 对应同步 / 异步选型 |
| PostgreSQL 连接数和内存 | postgresql/ 连接管理 | 线程池不能越过下游账单 |
| 日志只说“变慢” | elasticsearch/elk/ 可观测性 | 保留范围、窗口和事件 |
| HTTP 请求慢 | network/http/ 诊断 | 对齐应用层与系统层时间线 |

### 推荐阅读：只记定位

| 书名 / 资料 | 定位 |
|---|---|
| 《性能之巅》 | 性能指标、工具和系统分析方法 |
| 《Linux/UNIX 系统编程手册》 | 用户态 API、进程、文件、映射和 syscall 边界 |
| 《深入理解 Linux 内核》 | 进程、内存、文件系统机制；注意版本差异 |
| Linux kernel Documentation | 当前内核的 cgroup、DMA、调度和内存资料 |
| man7.org Linux man-pages | 用户态接口与 proc 文件边界 |

### 16.3 的六要素收束

**一句话定义**：后续学习地图把“还想深入什么”转换成路线、入口和练习顺序。
**直觉与边界**：像地铁图，显示换乘方向，不包含每栋建筑；三条路线交叉但不必同时开坑。
**核心原理**：路线由当前最常遇到的问题驱动；“哪里慢”优先性能工程，“内核发生什么”优先 eBPF，“为什么这样”优先内核机制。
**示例**：优化 Go HTTP 服务时，先用 14–15 定位；找不到热点进性能工程，怀疑 syscall / 调度进 eBPF，需要解释机制再读内核。
**误区**：只收集文章、不做实验；三条路线同时开始；把旧版内核书细节当成当前版本不变。
**一句话记住**：路线按问题选，深度靠实验长出来。
**官方文档**：[Linux kernel Documentation](https://docs.kernel.org/)、[eBPF Documentation](https://docs.kernel.org/bpf/index.html)、[man7.org Linux man-pages](https://man7.org/linux/man-pages/)、[课程精简索引](../../../web-index/man7.org/index.md)。

---

# 课程收束：你现在应该能怎么说

> 我先定义范围和时间窗口，再区分 CPU、调度、内存、fd、I/O 和下游等待。CPU 看进程 / 线程、user/system、run queue 和上下文切换；内存分 RSS、Page Cache、Dirty 和 cgroup；句柄看上限、类型分布和趋势。每个假设都用可复现证据验证，先做可回滚止血，再做单变量修复和复测。线程池、异步、零拷贝和 GPU 都不是默认答案，要按工作负载和改选条件选择。

## 本课程 48 个知识点闭环

```text
算力的来源 → CPU / 核心 / Amdahl / GPU
存储金字塔 → cache / 页表 / 缺页 / Page Cache / 脏页
进程与调度 → 进程 / 线程 / 时间片 / 切换 / load
IO 与异步 → fd / VFS / 阻塞 / epoll / Reactor / 零拷贝
综合会诊 → 指标 / 口径 / 压力 / 病例 / 地图 / 决策 / 深入路线
```

> **毕业句：先描述症状，再选择证据；先证实机制，再改变系统；每个优化都要带着代价和回滚出口。**

## 安全与复现提醒

- Docker Desktop 默认不一定开机自启；实验前确认 daemon 可用
- 压力实验只在可回收的 --rm 容器中做，生产系统不要照抄
- drop_caches、调高 fd / 内存 limit、改线程池都可能改变系统行为，先保存基线
- 本课复用课 14–15 的实测证据，不新增独立压力实验；GPU 明确为未实测

---

## 📚 官方文档总览

- [课程官方文档精简索引](../../../web-index/man7.org/index.md)
- [top(1)](https://man7.org/linux/man-pages/man1/top.1.html)、[vmstat(8)](https://man7.org/linux/man-pages/man8/vmstat.8.html)、[free(1)](https://man7.org/linux/man-pages/man1/free.1.html)
- [proc_pid_status(5)](https://man7.org/linux/man-pages/man5/proc_pid_status.5.html)、[proc_meminfo(5)](https://man7.org/linux/man-pages/man5/proc_meminfo.5.html)、[proc_loadavg(5)](https://man7.org/linux/man-pages/man5/proc_loadavg.5.html)
- [getrlimit(2)](https://man7.org/linux/man-pages/man2/getrlimit.2.html)、[proc_pid_fd(5)](https://man7.org/linux/man-pages/man5/proc_pid_fd.5.html)、[epoll(7)](https://man7.org/linux/man-pages/man7/epoll.7.html)
- [mmap(2)](https://man7.org/linux/man-pages/man2/mmap.2.html)、[sendfile(2)](https://man7.org/linux/man-pages/man2/sendfile.2.html)、[splice(2)](https://man7.org/linux/man-pages/man2/splice.2.html)
- [cgroup v2](https://docs.kernel.org/admin-guide/cgroup-v2.html)、[Linux DMA API HOWTO](https://docs.kernel.org/core-api/dma-api-howto.html)、[Docker 资源约束](https://docs.docker.com/engine/containers/resource_constraints/)

---

## 🧭 课程导航：整课收官版

- ✅ 上一课：[课 15《三个经典病例：CPU 打满、句柄爆仓、内存失踪》](lesson-15-三个经典病例CPU打满句柄爆仓内存失踪.md)
- 🏁 本课：课 16《结课会诊地图：从症状到动作》
- 📚 回看入口：
  - [阶段 1 · 算力的来源](../../1-算力的来源/overview.md)
  - [阶段 2 · 存储金字塔](../../2-存储金字塔/overview.md)
  - [阶段 3 · 进程与调度](../../3-进程与调度/overview.md)
  - [阶段 4 · IO 与异步](../../4-IO与异步/overview.md)
  - [阶段 5 · 综合会诊](../overview.md)
- 🚀 下一步：本课程正文到此收官；可进入 Phase 3 结课综合实战项目，或说“考我一下 Linux 操作系统基础”启动知识点对齐。

### 接力提示词

> 继续推进 operating-system：先读 operating-system/00-学习档案.md 和 operating-system/00-评审清单.md，本课程 Phase 2 的 16 课 / 48 知识点已完成。下一步默认进入 Phase 3 结课综合实战项目；若用户要求“考我一下”，进入 Phase 6 知识点对齐。保持 Docker Desktop + Ubuntu 容器环境口径，实测数字注明来源，不把启发式阈值写成内核硬规则。
