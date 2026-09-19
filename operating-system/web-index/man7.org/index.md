# man7.org · Linux man-pages 精简索引

- **站点**：man7.org — Linux man-pages project
- **根 URL**：https://man7.org/linux/man-pages/
- **URL 规律**：`/linux/man-pages/man{节}/{名称}.{节}.html`
- **生成日期**：2026-09（生成时 man-pages 项目版本 6.19；课 5–16 使用页面于 2026-09-17 增补/核对；课 16 无新增页面）
- **用途**：本课程各课「📚 官方文档」的唯一取 URL 入口；表中 URL 均已现场核实可达（HTTP 200）

## 按阶段组织的页面表

| 阶段 | 页面 | URL | 对应课次/知识点 | 我要用它查什么 |
|------|------|-----|----------------|----------------|
| 1 | uname(2) | https://man7.org/linux/man-pages/man2/uname.2.html | 课 1 · 1.3 | uname 系统调用与内核标识字段 |
| 1 | sched(7) | https://man7.org/linux/man-pages/man7/sched.7.html | 课 2 · 2.1（背景）/ 课 8 · 8.1 | 调度策略总览、nice 含义 |
| 2 | mmap(2) | https://man7.org/linux/man-pages/man2/mmap.2.html | 课 5 · 5.1 / 课 13 · 13.2 | 内存映射、MAP_ANONYMOUS |
| 2 | proc(5) | https://man7.org/linux/man-pages/man5/proc.5.html | 课 5 · 5.3 / 课 6 全课 / 课 7 · 7.2 / 课 9 · 9.1 / 课 10 · 10.1 / 课 14 | /proc/meminfo、/proc/loadavg、/proc/[pid]/fd、/proc/[pid]/task 等字段权威定义 |
| 2 | proc_meminfo(5) | https://man7.org/linux/man-pages/man5/proc_meminfo.5.html | 课 6 · 6.1/6.2/6.3 / 课 14 · 14.2 / 课 15 · 15.3 | `Cached`、`Buffers`、`MemAvailable`、`Dirty`、`Writeback` 等字段精确定义 |
| 1 | free(1) | https://man7.org/linux/man-pages/man1/free.1.html | 课 6 · 6.3 / 课 14 · 14.2 / 课 15 · 15.3 | `free` / `available` / `buffers` / `cache` / `buff/cache` 的列口径 |
| 2 | sync(2) | https://man7.org/linux/man-pages/man2/sync.2.html | 课 6 · 6.2 | 全局文件系统缓存同步与 `syncfs` 边界 |
| 2 | fsync(2) | https://man7.org/linux/man-pages/man2/fsync.2.html | 课 6 · 6.2 | 单文件描述符的数据、元数据同步与持久化边界 |
| 2 | proc_pid_status(5) | https://man7.org/linux/man-pages/man5/proc_pid_status.5.html | 课 5 · 5.2 / 课 7 · 7.1/7.2 / 课 15 · 15.1/15.3 | `/proc/[pid]/status` 的 VmSize / VmRSS / VmSwap / Pid / PPid / Tgid / Threads 等字段 |
| 2 | proc_pid_stat(5) | https://man7.org/linux/man-pages/man5/proc_pid_stat.5.html | 课 15 · 15.1 | 进程状态、用户态/内核态 CPU tick、processor、wchan、VSZ/RSS 字段 |
| 2 | proc_sys_vm(5) | https://man7.org/linux/man-pages/man5/proc_sys_vm.5.html | 课 5 · 5.3 | `vm.overcommit_memory`、OOM 相关 sysctl 与 `swappiness` |
| 3 | fork(2) | https://man7.org/linux/man-pages/man2/fork.2.html | 课 7 · 7.1 | fork 复制了什么、返回值语义 |
| 3 | clone(2) | https://man7.org/linux/man-pages/man2/clone.2.html | 课 7 · 7.2 | 线程与进程在 clone flag 上的差别 |
| 3 | pthreads(7) | https://man7.org/linux/man-pages/man7/pthreads.7.html | 课 7 · 7.2 | POSIX 线程总览、共享/独享清单 |
| 3 | nice(2) | https://man7.org/linux/man-pages/man2/nice.2.html | 课 8 · 8.1 | nice 值对调度的影响 |
| 3 | syscalls(2) | https://man7.org/linux/man-pages/man2/syscalls.2.html | 课 8 · 8.3 | 系统调用清单与 man 节组织 |
| 3 | ptrace(2) | https://man7.org/linux/man-pages/man2/ptrace.2.html | 课 8 · 8.3 | strace 依赖的进程跟踪接口 |
| 3 | strace(1) | https://man7.org/linux/man-pages/man1/strace.1.html | 课 15 · 15.1 | 短时跟踪进程系统调用并汇总调用形状 |
| 3 | openat(2) | https://man7.org/linux/man-pages/man2/openat.2.html | 课 8 · 8.3 / 课 10 · 10.1 | 文件与目录打开的系统调用入口 |
| 3 | proc_stat(5) | https://man7.org/linux/man-pages/man5/proc_stat.5.html | 课 8 · 8.2 / 课 9 · 9.1 / 课 14 / 课 15 · 15.1 | `/proc/stat` 的 ctxt、procs_running 与 CPU 时间字段 |
| 3 | vmstat(8) | https://man7.org/linux/man-pages/man8/vmstat.8.html | 课 8 · 8.2 / 课 9 · 9.1 / 课 14 / 课 15 · 15.1 | `r`、`b`、`in`、`cs`、`us`、`sy`、`wa` 字段 |
| 3 | proc_loadavg(5) | https://man7.org/linux/man-pages/man5/proc_loadavg.5.html | 课 9 · 9.1/9.2 / 课 14 · 14.2 | 1/5/15 分钟 load、R/D 任务与当前 runnable/总调度实体 |
| 3 | uptime(1) | https://man7.org/linux/man-pages/man1/uptime.1.html | 课 9 · 9.1 | load average 的展示口径与“不按 CPU 数归一化” |
| 4 | open(2) | https://man7.org/linux/man-pages/man2/open.2.html | 课 10 · 10.1/10.3、课 11 · 11.1 | open/openat/creat、O_NONBLOCK 标志 |
| 4 | dup(2) | https://man7.org/linux/man-pages/man2/dup.2.html | 课 10 · 10.1 | 复制 fd、共享 open file description 与最低可用编号 |
| 4 | socketpair(2) | https://man7.org/linux/man-pages/man2/socketpair.2.html | 课 10 · 10.1/10.2 | 一对连接 socket 返回的两个 fd、EMFILE/ENFILE |
| 4 | pipe(7) | https://man7.org/linux/man-pages/man7/pipe.7.html | 课 10 · 10.2 | 管道与 fd 的关系 |
| 4 | getrlimit(2) | https://man7.org/linux/man-pages/man2/getrlimit.2.html | 课 10 · 10.3 / 课 15 · 15.2 | RLIMIT_NOFILE 资源上限语义 |
| 4 | prlimit(2) | https://man7.org/linux/man-pages/man2/prlimit.2.html | 课 10 · 10.3 / 课 15 · 15.2 | 按进程读写资源上限（当期推荐用法） |
| 4 | proc_pid_fd(5) | https://man7.org/linux/man-pages/man5/proc_pid_fd.5.html | 课 10 · 10.1/10.3 / 课 15 · 15.2 | `/proc/<pid>/fd` 符号链接、pipe/socket/anon_inode 观测 |
| 4 | limits.conf(5) | https://man7.org/linux/man-pages/man5/limits.conf.5.html | 课 10 · 10.3 | 登录会话 soft/hard 资源限制配置格式 |
| 4 | proc_sys_fs(5) | https://man7.org/linux/man-pages/man5/proc_sys_fs.5.html | 课 10 · 10.3 / 课 15 · 15.2 | `file-max`、`file-nr`、`nr_open` 系统级口径 |
| 4 | fcntl(2) | https://man7.org/linux/man-pages/man2/fcntl.2.html | 课 11 · 11.1 | F_GETFL/F_SETFL 与非阻塞切换 |
| 4 | read(2) | https://man7.org/linux/man-pages/man2/read.2.html | 课 11 · 11.1/11.2 | fd 读取、部分读取与非阻塞时的 EAGAIN |
| 4 | write(2) | https://man7.org/linux/man-pages/man2/write.2.html | 课 11 · 11.1/11.2 | fd 写入、部分写入与可能阻塞的对象 |
| 4 | aio(7) | https://man7.org/linux/man-pages/man7/aio.7.html | 课 11 · 11.3 | POSIX 异步 I/O 接口与 Linux 实现边界 |
| 4 | io_uring(7) | https://man7.org/linux/man-pages/man7/io_uring.7.html | 课 11 · 11.3（延伸） | Linux 专属异步 I/O、提交队列与完成队列 |
| 4 | select(2) | https://man7.org/linux/man-pages/man2/select.2.html | 课 12 · 12.1 | select 的 fd_set 与 1024 限制 |
| 4 | poll(2) | https://man7.org/linux/man-pages/man2/poll.2.html | 课 12 · 12.1 | poll 的 pollfd 数组、无 1024 限制 |
| 4 | epoll(7) | https://man7.org/linux/man-pages/man7/epoll.7.html | 课 12 全课 | epoll 总览：create/ctl/wait、LT vs ET |
| 4 | epoll_create1(2) | https://man7.org/linux/man-pages/man2/epoll_create1.2.html | 课 12 · 12.2 | 创建 epoll 实例并返回 epoll fd |
| 4 | epoll_ctl(2) | https://man7.org/linux/man-pages/man2/epoll_ctl.2.html | 课 12 · 12.2 | ADD/MOD/DEL 关注集合中的 fd |
| 4 | epoll_wait(2) | https://man7.org/linux/man-pages/man2/epoll_wait.2.html | 课 12 · 12.2 | 从就绪集合取回事件；无事件时阻塞 |
| 4 | sendfile(2) | https://man7.org/linux/man-pages/man2/sendfile.2.html | 课 13 · 13.2 | sendfile 零拷贝语义与历史限制 |
| 4 | splice(2) | https://man7.org/linux/man-pages/man2/splice.2.html | 课 13 · 13.2（延伸） | 管道中转的零拷贝 |
| 5 | proc(5)（复用） | https://man7.org/linux/man-pages/man5/proc.5.html | 课 14、15 | 指标字段口径的权威出处 |

> 表中 URL 均已逐条核实 200；后续若回补新页面，须现场 fetch 核实后再加行。

## 不在本站的东西

free / top / htop / iostat / pidstat / lsof / ss / lscpu / nproc 等观测工具的 man 页**不属于** man-pages 项目——它们分别在 procps-ng、util-linux、sysstat、lsof 各上游。课内引用以**容器内 `man` 页**为准（先 `apt install man-db manpages`），跨课引用工具行为时注明版本。
