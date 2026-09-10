# engine（Docker Docs · 共 87 条）

> 范围：/engine/ · 生成日期：2026-09-10
> 排除 `engine/release-notes`（27 条）；Swarm 部分（25 条）与课程「课 14 生态位」相关但非主线，集中在本表末尾

## 容器运行

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 查 `docker run` 的行为与全部参数说明 | [Running containers](https://docs.docker.com/engine/containers/run/) | #exit-status | run、启动、退出码 | [docker container run 参考](https://docs.docker.com/reference/cli/docker/container/run/) |
| 看容器退出码含义（125/126/127/137/143） | [Running containers · Exit status](https://docs.docker.com/engine/containers/run/) | #exit-status | 退出码、exit code | |
| 讲内存/CPU 限制怎么设、cgroup 怎么生效 | [Resource constraints](https://docs.docker.com/engine/containers/resource_constraints/) | | 资源限制、cgroup、内存、CPU | [docker stats](https://docs.docker.com/reference/cli/docker/container/stats/) |
| 看容器运行时能采到哪些指标 | [Runtime metrics](https://docs.docker.com/engine/containers/runmetrics/) | | 指标、metrics、cgroup | [Prometheus 采集](https://docs.docker.com/engine/daemon/prometheus/) |
| 讲容器开机自启 / 重启策略 | [Start containers automatically](https://docs.docker.com/engine/containers/start-containers-automatically/) | | 自启、restart policy | [docker container run --restart](https://docs.docker.com/reference/cli/docker/container/run/) |
| 讲一个容器跑多个进程（要不要这么做） | [Run multiple processes in a container](https://docs.docker.com/engine/containers/multi-service_container/) | | 多进程、supervisor | |
| 容器里怎么用 GPU | [GPU access](https://docs.docker.com/engine/containers/gpu/) | | GPU、CUDA | [Compose 里用 GPU](https://docs.docker.com/compose/how-tos/gpu-support/) |

## 存储与卷

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 看存储总览（三种挂载怎么选） | [存储总览](https://docs.docker.com/engine/storage/) | | 存储、挂载、总览 | |
| 讲卷的创建/挂载/生命周期/备份 | [Volumes](https://docs.docker.com/engine/storage/volumes/) | | volume、具名卷、持久化 | [docker volume CLI](https://docs.docker.com/reference/cli/docker/volume/) |
| 讲 bind mount 与 volume 的区别和坑 | [Bind mounts](https://docs.docker.com/engine/storage/bind-mounts/) | | bind、挂载、宿主机目录 | [Volumes](https://docs.docker.com/engine/storage/volumes/) |
| 讲 tmpfs 挂载（内存盘） | [tmpfs mounts](https://docs.docker.com/engine/storage/tmpfs/) | | tmpfs、内存、临时 | |
| 讲镜像挂载（OCI image mount） | [Image mounts](https://docs.docker.com/engine/storage/image-mounts/) | | image mount | |
| 选存储驱动（overlay2 等） | [Select a storage driver](https://docs.docker.com/engine/storage/drivers/select-storage-driver/) | | 存储驱动、选型 | [docker info 看驱动](https://docs.docker.com/reference/cli/docker/system/info/) |
| 讲 OverlayFS 驱动原理 | [OverlayFS storage driver](https://docs.docker.com/engine/storage/drivers/overlayfs-driver/) | | overlay2、联合文件系统 | |
| 查 BTRFS / ZFS / VFS / windowsfilter 驱动 | [BTRFS](https://docs.docker.com/engine/storage/drivers/btrfs-driver/) / [ZFS](https://docs.docker.com/engine/storage/drivers/zfs-driver/) / [VFS](https://docs.docker.com/engine/storage/drivers/vfs-driver/) / [windowsfilter](https://docs.docker.com/engine/storage/drivers/windowsfilter-driver/) | | 存储驱动 | |
| 查 device-mapper（已废弃） | [Device Mapper (deprecated)](https://docs.docker.com/engine/storage/drivers/device-mapper-driver/) | | device mapper | |
| 讲 containerd 镜像存储（新特性） | [containerd image store](https://docs.docker.com/engine/storage/containerd/) | | containerd、镜像存储 | |

## 网络

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 看网络总览与驱动选型 | [网络总览](https://docs.docker.com/engine/network/) | | 网络、驱动、总览 | |
| 讲 bridge 网络与自定义 bridge、DNS 发现 | [Bridge network driver](https://docs.docker.com/engine/network/drivers/bridge/) | | bridge、自定义网络、DNS | [docker network CLI](https://docs.docker.com/reference/cli/docker/network/) |
| 讲 host 网络（与宿主机共享栈） | [Host network driver](https://docs.docker.com/engine/network/drivers/host/) | | host、网络 | |
| 讲 overlay 网络（跨主机） | [Overlay network driver](https://docs.docker.com/engine/network/drivers/overlay/) | | overlay、跨主机 | [Swarm 网络](https://docs.docker.com/engine/swarm/networking/) |
| 讲 macvlan / ipvlan（容器像物理机） | [Macvlan](https://docs.docker.com/engine/network/drivers/macvlan/) / [IPvlan](https://docs.docker.com/engine/network/drivers/ipvlan/) | | macvlan、ipvlan | |
| 讲 none 驱动（完全隔离） | [None network driver](https://docs.docker.com/engine/network/drivers/none/) | | none、隔离 | |
| 讲 `-p` 端口发布与 `-P` 的区别 | [Port publishing and mapping](https://docs.docker.com/engine/network/port-publishing/) | | 端口、发布、-p、-P | |
| 讲 Docker 与 iptables 的关系 | [Docker with iptables](https://docs.docker.com/engine/network/firewall-iptables/) | | iptables、防火墙 | [包过滤与防火墙](https://docs.docker.com/engine/network/packet-filtering-firewalls/) |
| 讲 Docker 与 nftables | [Docker with nftables](https://docs.docker.com/engine/network/firewall-nftables/) | | nftables | |
| 讲包过滤与防火墙整体机制 | [Packet filtering and firewalls](https://docs.docker.com/engine/network/packet-filtering-firewalls/) | | 防火墙、包过滤 | |
| 讲容器里怎么装 CA 证书 | [Use CA certificates](https://docs.docker.com/engine/network/ca-certs/) | | CA、证书 | |
| 查 legacy link（已过时） | [Legacy container links](https://docs.docker.com/engine/network/links/) | | link、legacy | |

## 日志

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 讲怎么配日志驱动、max-size/max-file | [Configure logging drivers](https://docs.docker.com/engine/logging/configure/) | | 日志驱动、轮转、日志膨胀 | [docker logs](https://docs.docker.com/reference/cli/docker/container/logs/) |
| 讲 json-file 驱动（默认） | [JSON File logging driver](https://docs.docker.com/engine/logging/drivers/json-file/) | | json-file、默认日志 | |
| 讲 local 日志驱动（会自动轮转） | [Local file logging driver](https://docs.docker.com/engine/logging/drivers/local/) | | local、轮转 | |
| 查 journald / syslog / fluentd 驱动 | [journald](https://docs.docker.com/engine/logging/drivers/journald/) / [syslog](https://docs.docker.com/engine/logging/drivers/syslog/) / [fluentd](https://docs.docker.com/engine/logging/drivers/fluentd/) | | 日志驱动 | |
| 查云厂商日志驱动（awslogs/gcplogs/splunk/gelf/etwlogs） | [awslogs](https://docs.docker.com/engine/logging/drivers/awslogs/) / [gcplogs](https://docs.docker.com/engine/logging/drivers/gcplogs/) / [splunk](https://docs.docker.com/engine/logging/drivers/splunk/) / [gelf](https://docs.docker.com/engine/logging/drivers/gelf/) / [etwlogs](https://docs.docker.com/engine/logging/drivers/etwlogs/) | | 日志驱动、云 | |
| 讲用了远端日志后还能不能 docker logs | [Dual logging](https://docs.docker.com/engine/logging/dual-logging/) | | 双写、docker logs | |
| 讲日志 tag / 输出格式自定义 | [Customize log driver output](https://docs.docker.com/engine/logging/log_tags/) | | 日志格式、tag | [CLI 格式化](https://docs.docker.com/engine/cli/formatting/) |
| 讲日志驱动插件 | [Logging driver plugins](https://docs.docker.com/engine/logging/plugins/) | | 插件 | |

## 安全

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 看引擎安全总览 | [Docker 安全](https://docs.docker.com/engine/security/) | | 安全、加固 | |
| 讲 rootless 模式（守护进程不用 root） | [Rootless mode](https://docs.docker.com/engine/security/rootless/) | | rootless、无根 | [rootless 排障](https://docs.docker.com/engine/security/rootless/troubleshoot/) |
| 查 rootless 的坑与已知限制 | [Rootless troubleshooting](https://docs.docker.com/engine/security/rootless/troubleshoot/) | | rootless、排障 | |
| 讲 rootless 下 UID/GID 怎么映射 | [UID/GID mapping](https://docs.docker.com/engine/security/rootless/uid-gid-mapping/) | | uid、gid、映射 | [userns-remap](https://docs.docker.com/engine/security/userns-remap/) |
| 讲 rootless 使用技巧 | [Rootless tips](https://docs.docker.com/engine/security/rootless/tips/) | | rootless 技巧 | |
| 讲 userns-remap（用户命名空间隔离） | [Isolate containers with a user namespace](https://docs.docker.com/engine/security/userns-remap/) | | userns、隔离 | |
| 讲 seccomp 配置文件与系统调用收敛 | [Seccomp security profiles](https://docs.docker.com/engine/security/seccomp/) | | seccomp、系统调用 | |
| 讲 AppArmor 配置 | [AppArmor security profiles](https://docs.docker.com/engine/security/apparmor/) | | apparmor | |
| 讲 docker.sock 为什么危险、怎么保护 | [Protect the Docker daemon socket](https://docs.docker.com/engine/security/protect-access/) | | socket、2375、TLS | |
| 讲用证书做仓库客户端校验 | [Verify repository client with certificates](https://docs.docker.com/engine/security/certificates/) | | 证书、仓库 | |
| 查 Docker 修过哪些漏洞（安全 non-events） | [Docker security non-events](https://docs.docker.com/engine/security/non-events/) | | 漏洞、CVE | |
| 讲杀毒软件与 Docker 共存 | [Antivirus software and Docker](https://docs.docker.com/engine/security/antivirus/) | | 杀软 | |
| 查内容信任 / Notary（镜像签名） | [Content trust](https://docs.docker.com/engine/security/trust/) | | 签名、信任、Notary | [管理密钥](https://docs.docker.com/engine/security/trust/trust_key_mng/) |
| 查内容信任的密钥管理与委托 | [Manage keys](https://docs.docker.com/engine/security/trust/trust_key_mng/) / [Delegations](https://docs.docker.com/engine/security/trust/trust_delegation/) | | 密钥、委托 | |

## 守护进程与安装

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 查守护进程 dockerd 配置与启动 | [dockerd 参考](https://docs.docker.com/reference/cli/dockerd/) | | dockerd、daemon.json | [Start the daemon](https://docs.docker.com/engine/daemon/start/) |
| 讲怎么手动启动守护进程 | [Start the daemon](https://docs.docker.com/engine/daemon/start/) | | 启动、daemon | |
| 讲 daemon.json 远程访问怎么开（含风险） | [Remote access](https://docs.docker.com/engine/daemon/remote-access/) | | 远程、2375、风险 | [Protect daemon socket](https://docs.docker.com/engine/security/protect-access/) |
| 讲 live restore（重启 daemon 不杀容器） | [Live restore](https://docs.docker.com/engine/daemon/live-restore/) | | live restore、不中断 | |
| 看守护进程日志、强制 stack trace | [Read the daemon logs](https://docs.docker.com/engine/daemon/logs/) | | 日志、排障、SIGUSR1 | |
| 守护进程排障 | [Troubleshooting the daemon](https://docs.docker.com/engine/daemon/troubleshoot/) | | 排障 | |
| 讲守护进程用 Prometheus 暴露指标 | [Collect metrics with Prometheus](https://docs.docker.com/engine/daemon/prometheus/) | | prometheus、指标 | |
| 讲守护进程走代理 | [Daemon proxy](https://docs.docker.com/engine/daemon/proxy/) | | 代理、proxy | [CLI 代理](https://docs.docker.com/engine/cli/proxy/) |
| 讲 daemon 开 IPv6 | [Use IPv6 networking](https://docs.docker.com/engine/daemon/ipv6/) | | ipv6 | |
| 讲换运行时（containerd / 其它 runc 替代） | [Alternative container runtimes](https://docs.docker.com/engine/daemon/alternative-runtimes/) | | runtime、runc、containerd | |
| 讲引擎内嵌 containerd（实验特性） | [Embedded containerd](https://docs.docker.com/engine/daemon/embedded-containerd/) | | containerd | |
| 找各发行版安装步骤 | [Install（总览）](https://docs.docker.com/engine/install/) / [Ubuntu](https://docs.docker.com/engine/install/ubuntu/) / [Debian](https://docs.docker.com/engine/install/debian/) / [CentOS](https://docs.docker.com/engine/install/centos/) / [RHEL](https://docs.docker.com/engine/install/rhel/) / [Fedora](https://docs.docker.com/engine/install/fedora/) | | 安装 | [二进制安装](https://docs.docker.com/engine/install/binaries/) |
| 讲 Linux 安装后的收尾（免 sudo 等） | [Linux post-installation](https://docs.docker.com/engine/install/linux-postinstall/) | | 免 sudo、post-install | |
| 查树莓派 / 二进制安装 | [Raspberry Pi OS](https://docs.docker.com/engine/install/raspberry-pi-os/) / [binaries](https://docs.docker.com/engine/install/binaries/) | | 安装 | |

## CLI 通用能力

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 讲 `--format` 与 Go template 输出 | [Format command and log output](https://docs.docker.com/engine/cli/formatting/) | | 格式化、--format、模板 | |
| 讲 `-f` / `--filter` 过滤写法 | [Filter commands](https://docs.docker.com/engine/cli/filter/) | | 过滤、filter | |
| 讲 shell 命令补全怎么配 | [Command completion](https://docs.docker.com/engine/cli/completion/) | | 补全、completion | |
| 讲 CLI 走代理 | [CLI proxy](https://docs.docker.com/engine/cli/proxy/) | | 代理 | |
| 查 CLI 的 OpenTelemetry 支持 | [OpenTelemetry for CLI](https://docs.docker.com/engine/cli/otel/) | | otel、遥测 | |

## 资源治理

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 讲磁盘清理：prune 家族与 `system df` | [Prune unused objects](https://docs.docker.com/engine/manage-resources/pruning/) | | prune、清理、磁盘 | [docker system df](https://docs.docker.com/reference/cli/docker/system/df/) |
| 讲 label 给对象打元数据 | [Docker object labels](https://docs.docker.com/engine/manage-resources/labels/) | | label、元数据 | |
| 讲 context 管理多个 daemon | [Docker contexts](https://docs.docker.com/engine/manage-resources/contexts/) | | context、多主机 | [docker context CLI](https://docs.docker.com/reference/cli/docker/context/) |

## 扩展（插件）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 看插件体系总览 | [Docker Engine plugins](https://docs.docker.com/engine/extend/legacy_plugins/) | | 插件 | |
| 查插件 API / 开发 | [Plugin API](https://docs.docker.com/engine/extend/plugin_api/) / [Plugin config](https://docs.docker.com/engine/extend/config/) | | 插件开发 | |
| 查授权 / 卷 / 网络插件 | [授权](https://docs.docker.com/engine/extend/plugins_authorization/) / [卷](https://docs.docker.com/engine/extend/plugins_volume/) / [网络](https://docs.docker.com/engine/extend/plugins_network/) | | 插件 | |

## Swarm（课 14 用：生态位对比）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 看 Swarm 模式关键概念 | [Swarm key concepts](https://docs.docker.com/engine/swarm/key-concepts/) | | swarm、概念 | |
| 讲 Swarm 与 k8s 的定位差异 | [Swarm mode](https://docs.docker.com/engine/swarm/swarm-mode/) | | swarm、编排 | |
| 看 Swarm 教程（建群→部署→伸缩→滚动更新） | [Swarm tutorial](https://docs.docker.com/engine/swarm/swarm-tutorial/) | | 教程 | [创建 swarm](https://docs.docker.com/engine/swarm/swarm-tutorial/create-swarm/) |
| 讲 service / task / node 怎么工作 | [How services work](https://docs.docker.com/engine/swarm/how-swarm-mode-works/services/) / [Nodes](https://docs.docker.com/engine/swarm/how-swarm-mode-works/nodes/) | | service、node | |
| 讲 Raft 共识与 manager 高可用 | [Raft consensus](https://docs.docker.com/engine/swarm/raft/) | | raft、高可用 | |
| 讲 routing mesh / ingress | [Routing mesh](https://docs.docker.com/engine/swarm/ingress/) | | ingress、routing mesh | |
| 讲 Swarm 里的 secret / config | [Secrets](https://docs.docker.com/engine/swarm/secrets/) / [Configs](https://docs.docker.com/engine/swarm/configs/) | | secret、config | |
| 讲 stack 部署 | [Deploy a stack](https://docs.docker.com/engine/swarm/stack-deploy/) | | stack | |
| 查 Swarm 运维（节点管理、锁、PKI） | [Manage nodes](https://docs.docker.com/engine/swarm/manage-nodes/) / [Locking](https://docs.docker.com/engine/swarm/swarm_manager_locking/) / [PKI](https://docs.docker.com/engine/swarm/how-swarm-mode-works/pki/) | | 运维 | |

## 其它

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 查已废弃特性清单 | [Deprecated features](https://docs.docker.com/engine/deprecated/) | | 废弃、deprecated | |
| 查引擎发布说明 | [Engine release notes](https://docs.docker.com/engine/release-notes/) | | 发布说明 | |
