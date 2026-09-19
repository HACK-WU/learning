# 课 15 · 三个经典病例：CPU 打满、句柄爆仓、内存失踪

> 阶段 5 · 综合会诊 ｜知识点 15.1、15.2、15.3 ｜更新于 2026-09-17

## 本课在故事主线中的情节定位

上一课把 `top`、`ps`、`vmstat`、`pidstat`、`lsof`、`iostat`、`free` 摆上值班桌。本课第一次把它们串成完整证据链：面对“CPU 100%”“`Too many open files`”“内存不见了”，先保护服务，再找到真正的对象，最后用单变量实验证明根因。

> 📖 **文档核对留痕**：任务状态、CPU tick、RSS、`RLIMIT_NOFILE`、`/proc/<PID>/fd`、`memory.max`、`memory.events` 与 Docker 容器 OOM 口径已按官方页面核对（核查于 2026-09）。来源：[proc_pid_stat(5)](https://man7.org/linux/man-pages/man5/proc_pid_stat.5.html)、[proc_pid_status(5)](https://man7.org/linux/man-pages/man5/proc_pid_status.5.html)、[getrlimit(2)](https://man7.org/linux/man-pages/man2/getrlimit.2.html)、[prlimit(2)](https://man7.org/linux/man-pages/man2/prlimit.2.html)、[proc_pid_fd(5)](https://man7.org/linux/man-pages/man5/proc_pid_fd.5.html)、[lsof(8)](https://man7.org/linux/man-pages/man8/lsof.8.html)、[top(1)](https://man7.org/linux/man-pages/man1/top.1.html)、[pidstat(1)](https://man7.org/linux/man-pages/man1/pidstat.1.html)、[free(1)](https://man7.org/linux/man-pages/man1/free.1.html)、[/proc/meminfo](https://man7.org/linux/man-pages/man5/proc_meminfo.5.html)、[cgroup v2 内存控制器](https://cdn.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)、[Docker 资源约束](https://docs.docker.com/engine/containers/resource_constraints/)。

## 📌 知识点导航

| 知识点 | 状态 | 学完后的能力 |
|---|---|---|
| 15.1 病例一：CPU 100% 的定位链 | ✅ | 从进程缩到线程/子进程，分清 `us` / `sy` / `wa`，做短时验证 |
| 15.2 病例二：`Too many open files` | ✅ | 查上限、数 fd、按对象分类，区分泄漏与合法峰值 |
| 15.3 病例三：内存失踪 | ✅ | 用 available、RSS、Cached、swap 和 cgroup 区分三种“内存不够” |

## 🎯 本课目标

学完本课你将能：

- 独立走完三条“发现 → 锁定 → 验证 → 止血/修复”排查链；
- 写出每一步“看到什么、判断什么、下一步敲什么”；
- 知道调大资源上限为什么只是缓冲，不能自动等于修复。

## 🛠 实验边界

本课均使用一次性 Docker Linux 容器，不修改宿主机内核参数、`limits.conf` 或 systemd 配置。实测基线：

```text
client=29.4.1 server=29.4.1 os=Docker Desktop arch=aarch64
ubuntu=linux/arm64
```

macOS 是房东，Docker LinuxKit VM 提供共享内核，容器 cgroup 提供资源边界。`top`、`vmstat`、`free` 看到的系统数据可能带有 VM/其他容器噪声；数字用于证明机制，不是跨机器性能基准。

---

# 第一幕：场景引入——凌晨两点的三张告警

`order-service` 的值班面板同时出现：

```text
CPU: 100%
error: Too many open files
memory: 还剩很少
```

新人往往马上做三个动作：加 CPU、调大 `nofile`、加大内存。它们可能暂时缓解，却没有回答“谁在消耗、是否持续、扩大边界会不会让事故更大”。

## 一句话本质

**排障不是寻找最大的红色数字，而是沿“症状 → 对象 → 机制 → 证据 → 动作”缩小范围。**

## 处境对照：三种告警的第一问

| 表面症状 | 不可直接推出 | 第一问 | 第一工具 |
|---|---|---|---|
| CPU 100% | 整机所有核都满、一定是死循环 | 谁在占？进程、线程还是子进程？`us/sy/wa` 哪个高？ | `top` / `ps` / `vmstat` |
| `EMFILE` | 只要调大上限 | 哪个 PID 触顶？占的是文件、socket 还是 pipe？会不会回收？ | `prlimit` / `/proc` / `lsof` |
| 内存少 | 一定是应用泄漏 | available 如何？RSS 谁在涨？cgroup 是否触顶？ | `free` / `status` / cgroup |

> **共同顺序：先止血保护用户，再低侵入观测；先锁定对象，再做短时验证。**

---

# 第二幕：认知冲突——数字全真，结论仍可能全错

## 父进程 0%，子进程可能 100%

服务常有管理父进程和真正工作的线程/子进程。`top -H -p 父PID` 解决的是线程粒度；它不会自动把独立 fork 子进程变成父进程的 CPU。过滤范围错了，就会看到：

```text
父进程：S，0%
子进程：R，100%
```

## “open files”不只包含普通文件

fd 是进程文件描述符表中的整数编号，背后可能是普通文件、目录、socket、pipe、终端、设备或 epoll。`lsof` 展示的 `cwd`、`rtd`、`txt`、`mem` 等行也不等于 fd 编号数量。

## “内存不够”至少有三种形状

| 形状 | 证据 | 可能动作 |
|---|---|---|
| 匿名 RSS 持续涨 | `RssAnon` / RSS 随输入增长 | 降并发、滚动重启、修复无界缓存/引用 |
| Page Cache 暂时涨 | 全局 `Cached` 或 cgroup `file` 增长，RSS 未同步增长 | 观察回收、IO 和回写，不急着杀业务 |
| cgroup 触顶 | `memory.current` 接近 `memory.max`，`oom_kill` 增长 | 降载、隔离 worker、重新设计 limit/swap |

三者用户感受都可能叫“内存少”，但止血动作不同。第 5、6、10、14 课的机制和工具边界在这里汇合。

---

# 第三幕：层层揭示——三条排查链

![三个经典病例的 Linux 会诊地图](/Users/wuyongping/Desktop/learning/operating-system/stages/5-综合会诊/assets/case-triage-map.svg)

> **读图指南**：每条横向链都先确定对象，再分类，再做单变量验证，最右侧是动作方向；底部蓝色带提醒记录范围、窗口、单位。

## 本课地图

| 步骤 | 任务 | 回指 |
|---|---|---|
| 1 | 从系统缩到进程、线程、子进程或 cgroup | 课 7、8、14 |
| 2 | 按 CPU 去向、fd 类型、内存类别分叉 | 课 5、6、8、10、14 |
| 3 | 观察增长与恢复，验证因果 | 课 9、14 |
| 4 | 先止血，后提交永久修复 | 本课 |

🧭 **第 1/3 步**：三条链都不是“看到红色就改配置”，而是先缩小测量范围。

## 15.1 病例一：CPU 100% 的定位链（面试高频）

### 一句话定义

**CPU 100% 的定位链，是从整机快照缩到真实消耗者，再用 `us`、`sy`、`wa` 判断忙在用户态、内核态还是 IO 等待。**

### 直觉与类比边界

像厨房变慢：先看所有灶台，再看哪位厨师，再分辨是在切菜、系统取货，还是站着等食材。边界在于一个服务的“厨师长”可能只管理多个真正干活的线程/子进程。

### 核心原理

先看系统和未过滤的任务：

```bash
top -b -n 1 | head -n 25
ps -eo pid,ppid,stat,psr,pcpu,pmem,comm --sort=-pcpu | head -n 15
```

再分两个方向：

```bash
top -H -p <PID>
ps -L -p <PID> -o pid,tid,stat,psr,pcpu,wchan:24,comm
pidstat -t -p <PID> 1 3
ps --ppid <PID> -o pid,ppid,stat,psr,pcpu,comm
```

前三条偏线程，最后一条看直属子进程。若父 PID 没事，未过滤 `ps` 却发现子 PID 为 `R`、接近 100%，要对真实子 PID 继续分析。

分 CPU 去向：

```bash
vmstat 1 3
pidstat -u -p <PID> 1 3
iostat -y -xz 1 3
```

| 读数 | 倾向 | 下一步 |
|---|---|---|
| `us` 高 | 业务计算、解释器循环、压缩/加密 | 找热点与并发来源 |
| `sy` 高 | 系统调用、网络/文件路径、内核处理 | 短时 `strace -c`，再看 fd/socket |
| `wa` 高 | CPU 空闲但块 IO 未完成 | 看 `vmstat b/wa`、`iostat await`、`D` 状态 |

`wa` 不是某个进程“使用了等待 CPU”，而是系统 CPU 统计；必须和设备与业务延迟一起看。课 8 负责 `us/sy` 与 syscall 边界，课 9 负责 R/D 与 load 边界。

### 示例与实测

两个 CPU worker 的进程树实测：

```text
PID  PPID  STAT  PSR  %CPU  COMMAND
820     1  SL      3   0.0  stress-ng
822   820  R       8 100.0  stress-ng-cpu
823   820  R       5 100.0  stress-ng-cpu
```

对父 PID 过滤时看到 `%CPU=0`；取消过滤后两个 worker 各约 100%。压力程序报告：

```text
stress-ng: cpu 5805 6.00 sec usr 12.00 sys 0.00 bogo ops/s 966.99 real, 483.53 CPU time
```

另一次单进程 `yes` 形状中，`pidstat` 实测 `%usr=28、%system=72、%CPU=100.00`；它提醒我们“CPU 满”还要继续分用户态与内核态。用 `strace -f -c -e write` 观察 `yes`，实测约 18,980 次 write、总计 0.093885s、约 4 usec/call。

### 常见误区

1. 一个任务 100% 不等于所有 CPU 100%，先看逻辑核和全局 idle。
2. `top -H` 看线程，不自动覆盖独立子进程。
3. `sy` 高不等于磁盘，网络与系统调用风暴也会贡献它。
4. 一上来 `kill -9` 可能丢请求或制造重启风暴。
5. 一次快照不能证明长期热点，CPU 需要窗口与趋势。

### 一句话记住

> **CPU 100% 先找真正的消耗 PID，再分 `us/sy/wa`；父进程安静，不等于子进程安静。**

### 📚 官方文档

[proc_pid_stat(5)](https://man7.org/linux/man-pages/man5/proc_pid_stat.5.html)、[top(1)](https://man7.org/linux/man-pages/man1/top.1.html)、[pidstat(1)](https://man7.org/linux/man-pages/man1/pidstat.1.html)、[vmstat(8)](https://man7.org/linux/man-pages/man8/vmstat.8.html)、[strace(1)](https://man7.org/linux/man-pages/man1/strace.1.html)。

🧭 **第 1/3 步完成**：线程和子进程是两个不同的缩小方向。下面看 fd：报错指出类别，却没有指出占用者。

## 15.2 病例二：`Too many open files`

### 一句话定义

**`EMFILE` 表示某个进程达到自己的打开文件描述符上限；必须同时查上限、数量、对象类型和增长趋势。**

### 直觉与类比边界

fd 像前台发出的房卡编号：它不只开客房，也能开电话、仓库、会议室。边界是 fd 只是进程表索引；多个 fd 可以通过 `dup()` 指向同一个底层打开对象。

### 核心原理

先保留原始报错和 PID：

```text
OSError: [Errno 24] Too many open files: '/dev/null'
```

再查上限：

```bash
cat /proc/<PID>/limits | grep -i 'open files'
prlimit --pid <PID> --nofile
cat /proc/sys/fs/file-nr
```

`soft limit` 是当前约束，`hard limit` 是可调到的天花板；`file-nr` 是更广的系统级统计。进程级 `EMFILE` 不等于系统级 `ENFILE`。

数 fd，再分类对象：

```bash
find /proc/<PID>/fd -maxdepth 1 -type l | wc -l
lsof -n -P -p <PID>
lsof -n -P -p <PID> | awk 'NR > 1 {print $5}' | sort | uniq -c | sort -nr
```

| `lsof TYPE` | 线索 |
|---|---|
| `REG` | 普通文件、日志、临时文件 |
| `IPv4` / `IPv6` | socket、连接池、超时和响应回收 |
| `FIFO` / `PIPE` | 子进程通信、日志管道 |
| `CHR` | 终端、设备、标准 IO |
| `anon_inode:[eventpoll]` | epoll 等匿名对象 |

`lsof` 还展示 cwd、rtd、txt、mem 等行，行数不能直接和 fd 上限比较。最后做趋势：

```bash
while true; do
  date '+%H:%M:%S'
  find /proc/<PID>/fd -maxdepth 1 -type l 2>/dev/null | wc -l
  sleep 5
done
```

稳定请求下单调增长、停止输入仍不回落，才更像泄漏；连接池预热和高并发峰值也可能短时变高。

### 示例与实测

把 Python 容器的 soft/hard limit 压到 32，反复打开 `/dev/null`：

```text
limit= (32, 32)
Traceback (most recent call last):
  File "<string>", line 1, in <module>
OSError: [Errno 24] Too many open files: '/dev/null'
```

同类 lsof 实验让 `sleep` 持有 fd 7、8：

```text
pid=10
proc_fd_count=5
COMMAND PID USER  FD   TYPE DEVICE SIZE/OFF NODE NAME
sleep    10 root   0r   CHR  1,3      0t0    5 /dev/null
sleep    10 root   7u   CHR  1,3      0t0    5 /dev/null
sleep    10 root   8u   CHR  1,3      0t0    5 /dev/null
```

5 个 fd 是 `0、1、2、7、8`；lsof 同时显示 cwd、rtd、txt、动态库和 pipe，因此行数会更多。

### 止损与代价

| 动作 | 作用 | 代价 |
|---|---|---|
| 降流/暂停高并发 | 减慢新 fd 产生 | 吞吐下降，需看是否回落 |
| 平滑重启泄漏 worker | 释放旧 fd | 要正确排空请求 |
| 临时调高 soft limit | 给短期峰值留空间 | 泄漏继续时只是推迟爆点 |
| 提高 hard/system limit | 支撑计算过的并发 | 内存、端口、后端连接也有容量 |
| 修复关闭/回收路径 | 消除根因 | 要覆盖超时、重试、取消、异常路径 |

systemd 的 unit 入口通常是 `LimitNOFILE=`；PAM 登录会话和 systemd 服务不是同一继承链。课 10 已讲过持久化边界，本课不把临调当永久配置。

### 常见误区

1. “open files”不只指普通文件，socket、pipe、epoll 都占 fd。
2. `lsof` 行数不等于 fd 数，先数 `/proc/<PID>/fd`。
3. 只查 soft limit 会漏掉 hard limit 和服务启动链。
4. fd 多不必然是泄漏，要看趋势与回收。
5. 句柄耗尽时诊断 shell 的管道/命令替换也可能失败，最好从旁路观察。

### 一句话记住

> **`EMFILE` 先查谁的上限，再查占的是什么，最后查会不会回收；调大上限是缓冲，不是修复。**

### 📚 官方文档

[getrlimit(2)](https://man7.org/linux/man-pages/man2/getrlimit.2.html)、[prlimit(2)](https://man7.org/linux/man-pages/man2/prlimit.2.html)、[proc_pid_fd(5)](https://man7.org/linux/man-pages/man5/proc_pid_fd.5.html)、[proc_sys_fs(5)](https://man7.org/linux/man-pages/man5/proc_sys_fs.5.html)、[lsof(8)](https://man7.org/linux/man-pages/man8/lsof.8.html)。

🧭 **第 2/3 步完成**：fd 报错还要用上限、对象、趋势三把尺子把峰值与泄漏分开。

## 15.3 病例三：内存失踪

### 一句话定义

**内存失踪的定位链，是先看 available 与 cgroup 是否还能分配，再用 RSS、`RssAnon`、`RssFile`、`Cached`、swap/OOM 分辨占用类别。**

### 直觉与类比边界

`RssAnon` 像团队已搬入仓库的货；Page Cache 像管理员暂存的复印件；`memory.max` 像该团队租下的仓位上限。边界是共享页、映射页、内核统计存在不同口径，RSS 不是精确的进程独占内存。

### 核心原理

先看全局可用量和容器边界：

```bash
free -w -h
grep -E '^(MemAvailable|Cached|Buffers|Dirty|Writeback|SwapFree):' /proc/meminfo
cat /sys/fs/cgroup/memory.current
cat /sys/fs/cgroup/memory.max
cat /sys/fs/cgroup/memory.events
```

再找进程：

```bash
ps -eo pid,ppid,stat,%mem,rss,vsz,comm --sort=-rss | head -n 15
grep -E '^(Name|State|VmSize|VmRSS|RssAnon|RssFile|RssShmem|VmSwap):' /proc/<PID>/status
```

| 观察 | 更像什么 | 还要验证 |
|---|---|---|
| `RssAnon` 随请求涨 | 堆、匿名 mmap、栈、应用缓存 | 停止输入后是否停止/回收 |
| `RssFile` 涨 | 文件映射或共享库相关页 | 映射路径、全局 Cached、IO |
| RSS 不涨而 `Cached` 涨 | Page Cache | 回收、脏页、cgroup `file` |
| `VmSwap` 涨且延迟恶化 | 换页 | `vmstat si/so`、工作集和 IO |

`RssFile` 不是全局 Page Cache 的同义词；全局缓存回到 `/proc/meminfo`，容器边界补看 `memory.stat`。一次 RSS 高也不能单独证明泄漏，必须有趋势和“停止输入/回收/重启 worker”的对照。

### 示例一：匿名 RSS

逐页触碰 96 MiB 匿名内存的 Python 进程实测：

```text
allocated=96MiB
pid=9
Name:    python
State:   S (sleeping)
VmSize:  110972 kB
VmRSS:   107096 kB
RssAnon: 102172 kB
RssFile:   4924 kB
VmSwap:      0 kB
```

`RssAnon` 接近触碰过的匿名分配量，证明进程占着驻留内存；但一次采样还不能证明永久泄漏。

可重放命令：

```bash
docker run --rm --platform linux/arm64 --memory=256m --memory-swap=256m python:3.13-slim bash -lc 'python -c "import time; buf=bytearray(96*1024*1024); [buf.__setitem__(i,1) for i in range(0,len(buf),4096)]; time.sleep(8)" & p=$!; sleep 2; echo pid=$p; grep -E "^(Name|State|VmSize|VmRSS|RssAnon|RssFile|VmSwap):" /proc/$p/status; wait $p'
```

### 示例二：Page Cache

写入并读回 64 MiB 文件，`/proc/meminfo` 片段实测：

```text
before
Cached:           613168 kB
Dirty:               276 kB
Writeback:             0 kB
after
Cached:           679244 kB
Dirty:               208 kB
Writeback:         16548 kB
```

`Cached` 增加 `66076 kB`，约为 64 MiB 量级；RSS 没有因此自动归属于某个应用。`Writeback` 非零说明写回可能仍在进行。

可重放命令：

```bash
docker run --rm --platform linux/arm64 --memory=256m --memory-swap=256m python:3.13-slim bash -lc 'echo before; grep -E "^(Cached|Dirty|Writeback):" /proc/meminfo; dd if=/dev/zero of=/tmp/page-cache-demo bs=1M count=64 status=none; dd if=/tmp/page-cache-demo of=/dev/null bs=1M status=none; echo after; grep -E "^(Cached|Dirty|Writeback):" /proc/meminfo'
```

### 示例三：cgroup OOM

128 MiB 内存、同样大小的 swap 配额，令 `dd` 直接成为主进程并写 256 MiB tmpfs。开始的事件为：

```text
134217728
low 0
high 0
max 0
oom 0
oom_kill 0
oom_group_kill 0
```

结束实测：

```text
docker_start_exit=137
status=exited exit=137 oom=true
```

`137 = 128 + 9`，通常表示 `SIGKILL`；`oom=true` 与 cgroup 事件一起证明了容器内局部 OOM。若 shell 才是主进程，可能出现子进程被杀而 shell exit 0，所以实验使用 `exec dd` 保留退出状态。

### 换页与 OOM

| 结局 | 形状 | 线索 |
|---|---|---|
| 换页 | 程序继续但延迟恶化 | `VmSwap`、`vmstat si/so`、IO wait |
| OOM | 回收不够，相关域杀进程 | `memory.events` 的 `oom_kill`、Docker `OOMKilled`、退出 137 |

cgroup v2 的 `memory.max` 是硬限制；Docker 的 `--memory-swap` 是内存+swap 合计额度，和 `--memory` 相等时没有额外 swap。

### 止损与代价

| 形状 | 先止血 | 根因方向 |
|---|---|---|
| `RssAnon` 随流量涨 | 降并发、限流、隔离/重启 worker | 无界缓存、引用未释放、批量任务 |
| `Cached` 涨但 available 健康 | 先观察回收和回写 | IO 模式与工作集 |
| swap 持续增长 | 降载、缩小工作集 | 工作集超过物理内存 |
| `oom_kill` 增长 | 降压、保护依赖、处理被杀 worker | limit、峰值、泄漏、swap 设计 |

### 常见误区

1. 只看 `free` 列，不看 `available`。
2. 把 buff/cache 全算成应用泄漏。
3. RSS 最大就等于独占内存，忽略共享页与趋势。
4. 容器 `free` 显示 GiB，不代表突破不了 128 MiB cgroup。
5. OOM 就先 drop caches；它不能修匿名泄漏，还可能让 IO 变慢。
6. 退出 137 不是唯一证据，要和 `OOMKilled`、cgroup 事件和时间线互证。

### 一句话记住

> **内存失踪先问还能不能分配，再问谁的 RSS 在涨；`Cached`、swap、cgroup OOM 是不同证据链。**

### 📚 官方文档

[proc_pid_status(5)](https://man7.org/linux/man-pages/man5/proc_pid_status.5.html)、[free(1)](https://man7.org/linux/man-pages/man1/free.1.html)、[proc_meminfo(5)](https://man7.org/linux/man-pages/man5/proc_meminfo.5.html)、[cgroup v2 memory controller](https://cdn.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)、[Docker 资源约束](https://docs.docker.com/engine/containers/resource_constraints/)。

🧭 **第 3/3 步完成**：三种“资源不够”已经拆成 CPU 消耗者、fd 对象、内存类别与 cgroup 边界。

---

# 第四幕：实操验证——把告警写成会诊记录

## 4.1 低侵入起手式

```bash
date
uptime
top -b -n 1 | head -n 25
vmstat 1 3
free -w -h
```

然后只走命中的分支：

```mermaid
flowchart TD
    A[收到慢 / 满 / 爆告警] --> B{主要症状}
    B -->|CPU| C[top/ps 找 PID]
    C --> D{线程还是子进程}
    D --> E[pidstat/vmstat 分 us sy wa]
    E --> F[短时 strace 或压力对照]
    B -->|EMFILE| G[limits/prlimit]
    G --> H[/proc/PID/fd + lsof]
    H --> I[对象类型与增长趋势]
    B -->|内存少| J[available + cgroup]
    J --> K[RSS/RssAnon/RssFile]
    K --> L[Cached/swap/memory.events]
    F --> M[记录止血与证据]
    I --> M
    L --> M
```

## 4.2 排障笔记模板

```text
时间：
症状：
影响范围：实例 / 容器组 / VM / 依赖服务

范围：系统 / 进程 / 线程 / 子进程 / cgroup
窗口：快照 / 1 秒采样 / 5 分钟趋势
单位：% / ticks / fd 数 / KiB / queue

发现：原始命令与输出：
锁定：PID/TID/cgroup：
分叉：us/sy/wa；fd TYPE；RssAnon/Cached/OOM：
验证：改变了哪个单变量？恢复后什么回落？
止血：动作、时间、用户影响：
根因假设：
尚未证明：
永久修复：
回滚条件：
```

## 4.3 三个判断练习

**练习 A：父 PID 0%，两个子 PID 100%。**

答案：不是 CPU 没问题，而是过滤范围错。取消过滤，确认子进程归属后对真实 worker 采样。

**练习 B：`lsof` 52 行，`/proc/PID/fd` 43 个。**

答案：不矛盾。前者展开打开对象，后者更接近 fd 数；继续看 TYPE 和趋势。

**练习 C：`free` 显示 GiB，`memory.max=134217728`。**

答案：范围不同。`free` 是 VM/系统视图，`memory.max` 是容器边界；容器可能先 OOM。

---

# 第五幕：体系收束——一张可带走的决策表

| 症状 | 第一证据 | 机制分叉 | 第一动作 | 永久修复 |
|---|---|---|---|---|
| CPU 100% | `top` / `ps` / `vmstat` | 进程/线程/子进程；`us/sy/wa` | 限流、降并发、停止已确认异常 worker | 热点、并发、IO、重试风暴 |
| `EMFILE` | `prlimit` + `/proc` + `lsof` | 上限、合法峰值、泄漏 | 降流、平滑重启、临调 | close/回收、连接池、超时 |
| 内存少 | `available` + cgroup + RSS | 匿名、Page Cache、swap、OOM | 降载、隔离 worker | 工作集、缓存、limit/swap |

共同骨架：

```text
发现异常
  ↓
确认范围：系统 / 进程 / 线程 / 子进程 / cgroup
  ↓
确认窗口：快照 / 采样 / 趋势
  ↓
按机制分类：CPU 去向 / fd 类型 / 内存类别
  ↓
单变量复现，观察回落
  ↓
止血动作 + 证据记录 + 永久修复
```

> **先找对象，再看类别；先做止血，再做证明；先记口径，再改配置。**

## 课后自测

1. 父 PID 的 `%CPU=0`，接口却变慢，第一步是什么？  
   **答案**：取消过窄过滤，用未过滤 `ps/top` 查子进程，再对真实消耗 PID 做线程和采样分析。

2. 为什么 fd 快耗尽时，诊断 shell 自己也可能失败？  
   **答案**：管道、命令替换、目录操作和动态加载都可能需要新 fd；从旁路 shell、supervisor 或宿主机观察。

3. `buff/cache` 很大，是否应该杀 RSS 最大的进程？  
   **答案**：不应该。先看 available、RssAnon/RssFile、Cached、cgroup 和 events，区分可回收缓存与匿名增长。

4. 退出码 137 是否单独证明 OOM？  
   **答案**：不够。137 是常见 SIGKILL 结果，还需和 Docker OOMKilled、cgroup events、时间线互证。

5. 为什么调大资源上限不能自动算修复？  
   **答案**：它可能只推迟爆点；泄漏、无界缓存或热点仍在，爆炸半径可能更大。

## 📋 命令速查卡

| 目的 | 命令 |
|---|---|
| CPU 快照 | `top -b -n 1`、`ps -eo pid,ppid,stat,psr,pcpu,pmem,comm --sort=-pcpu` |
| 线程/子进程 | `top -H -p <PID>`、`ps -L -p <PID> ...`、`ps --ppid <PID> ...` |
| CPU 分叉 | `vmstat 1 3`、`pidstat -u -p <PID> 1 3`、`iostat -y -xz 1 3` |
| syscall | `strace -f -c -p <PID> -e trace=read,write,openat,close` |
| fd 上限/数量 | `cat /proc/<PID>/limits`、`prlimit --pid <PID> --nofile`、`find /proc/<PID>/fd -type l` |
| fd 分类 | `lsof -n -P -p <PID>` |
| 内存系统口径 | `free -w -h`、`grep ... /proc/meminfo` |
| 进程内存类别 | `grep ... /proc/<PID>/status` |
| cgroup 边界 | `cat /sys/fs/cgroup/memory.current /sys/fs/cgroup/memory.max` |
| OOM 事件 | `cat /sys/fs/cgroup/memory.events`、`docker inspect -f '{{.State.OOMKilled}}' <container>` |

## 📚 本课官方文档总表

- 任务与内存：[proc_pid_stat(5)](https://man7.org/linux/man-pages/man5/proc_pid_stat.5.html)、[proc_pid_status(5)](https://man7.org/linux/man-pages/man5/proc_pid_status.5.html)
- CPU 观测：[top(1)](https://man7.org/linux/man-pages/man1/top.1.html)、[pidstat(1)](https://man7.org/linux/man-pages/man1/pidstat.1.html)、[vmstat(8)](https://man7.org/linux/man-pages/man8/vmstat.8.html)
- fd：[getrlimit(2)](https://man7.org/linux/man-pages/man2/getrlimit.2.html)、[prlimit(2)](https://man7.org/linux/man-pages/man2/prlimit.2.html)、[proc_pid_fd(5)](https://man7.org/linux/man-pages/man5/proc_pid_fd.5.html)、[lsof(8)](https://man7.org/linux/man-pages/man8/lsof.8.html)
- 内存/OOM：[free(1)](https://man7.org/linux/man-pages/man1/free.1.html)、[proc_meminfo(5)](https://man7.org/linux/man-pages/man5/proc_meminfo.5.html)、[cgroup v2](https://cdn.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)、[Docker 资源约束](https://docs.docker.com/engine/containers/resource_constraints/)

## 🧭 课程导航

- 上一课：[课 14《观测工具箱：给服务器做体检》](lesson-14-观测工具箱给服务器做体检.md)
- 下一课：[课 16《结课会诊地图：从症状到动作》](lesson-16-结课会诊地图从症状到动作.md)
- 课程目录：[operating-system/02-课程目录.md](../../../02-课程目录.md)

## 🚀 接力提示词

继续学 Linux 操作系统基础。我的学习档案在 operating-system/00-学习档案.md，
刚学完阶段 5《综合会诊》的课 15《三个经典病例：CPU 打满、句柄爆仓、内存失踪》知识点 15.1、15.2、15.3，
请按大纲继续讲解课 16《结课会诊地图：从症状到动作》
（16.1 全景会诊地图 / 16.2 四张设计决策卡 / 16.3 后续学习地图）。

> 本课的核心不是把资源上限调大，而是从对象、类别、趋势和边界证明根因；下一课把整门课收束成可带走的会诊地图与设计决策卡。
