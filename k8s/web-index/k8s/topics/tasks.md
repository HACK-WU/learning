# tasks（Kubernetes 文档 · 共 108 条）

> 范围：/zh-cn/docs/tasks/ · 生成日期：2026-09-10
> 采集自 sitemap 共 212 条，按用户确认口径精简到 60 条：保留主干操作页，剔除 kubeadm 细碎子页、Windows/云厂商专用页与 dockershim 迁移页（已过时效）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 对比 apply 与 create（声明式管理） | [使用配置文件对 Kubernetes 对象进行声明式管理](https://kubernetes.io/zh-cn/docs/tasks/manage-kubernetes-objects/declarative-config/) | | 声明式、apply | [object-management](https://kubernetes.io/zh-cn/docs/concepts/overview/working-with-objects/object-management/) |
| 讲命令式对象管理 | [使用指令式命令管理 Kubernetes 对象](https://kubernetes.io/zh-cn/docs/tasks/manage-kubernetes-objects/imperative-command/) | | 命令式、create、run | |
| 讲命令式配置文件管理 | [imperative-config](https://kubernetes.io/zh-cn/docs/tasks/manage-kubernetes-objects/imperative-config/) | | 命令式、配置文件 | |
| 用 kubectl patch 更新对象 | [使用 kubectl patch 更新 API 对象](https://kubernetes.io/zh-cn/docs/tasks/manage-kubernetes-objects/update-api-object-kubectl-patch/) | | patch、更新 | |
| 用 Kustomize 管理对象 | [使用 Kustomize 对 Kubernetes 对象进行声明式管理](https://kubernetes.io/zh-cn/docs/tasks/manage-kubernetes-objects/kustomization/) | | Kustomize | |
| 查对象管理总览 | [管理 Kubernetes 对象](https://kubernetes.io/zh-cn/docs/tasks/manage-kubernetes-objects/) | | 对象管理 | |
| 装 kubectl（Linux） | [在 Linux 系统中安装并设置 kubectl](https://kubernetes.io/zh-cn/docs/tasks/tools/install-kubectl-linux/) | | kubectl、安装 | |
| 装 kubectl（macOS） | [在 macOS 系统上安装和设置 kubectl](https://kubernetes.io/zh-cn/docs/tasks/tools/install-kubectl-macos/) | | kubectl、安装 | |
| 装 kubectl（Windows） | [在 Windows 上安装 kubectl](https://kubernetes.io/zh-cn/docs/tasks/tools/install-kubectl-windows/) | | kubectl、安装 | |
| 查工具安装总览 | [安装工具](https://kubernetes.io/zh-cn/docs/tasks/tools/) | | 工具 | |
| 给容器设置环境变量 | [为容器设置环境变量](https://kubernetes.io/zh-cn/docs/tasks/inject-data-application/define-environment-variable-container/) | | 环境变量、env | |
| 定义相互依赖的环境变量 | [define-interdependent-environment-variables](https://kubernetes.io/zh-cn/docs/tasks/inject-data-application/define-interdependent-environment-variables/) | | 环境变量 | |
| 从文件注入环境变量 | [define-environment-variable-via-file](https://kubernetes.io/zh-cn/docs/tasks/inject-data-application/define-environment-variable-via-file/) | | 环境变量、文件 | |
| 用环境变量暴露 Pod 信息 | [通过环境变量将 Pod 信息呈现给容器](https://kubernetes.io/zh-cn/docs/tasks/inject-data-application/environment-variable-expose-pod-information/) | | downward API、环境变量 | |
| 用卷暴露 Pod 信息 | [downward-api-volume-expose-pod-information](https://kubernetes.io/zh-cn/docs/tasks/inject-data-application/downward-api-volume-expose-pod-information/) | | downward API、卷 | |
| 给容器设置命令与参数 | [为容器设置启动时要执行的命令和参数](https://kubernetes.io/zh-cn/docs/tasks/inject-data-application/define-command-argument-container/) | | command、args | |
| 安全分发凭证 | [使用 Secret 安全地分发凭证](https://kubernetes.io/zh-cn/docs/tasks/inject-data-application/distribute-credentials-secure/) | | Secret、凭证 | |
| 查数据注入总览 | [给应用注入数据](https://kubernetes.io/zh-cn/docs/tasks/inject-data-application/) | | 注入、配置 | |
| 用 ConfigMap 配置 Pod | [使用 ConfigMap 配置 Pod](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/configure-pod-configmap/) | | ConfigMap | |
| 配置存活/就绪/启动探针 | [配置存活、就绪和启动探针](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) | | 探针、健康检查 | [probes](https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/probes/) |
| 配置 securityContext | [为 Pod 或容器配置安全上下文](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/security-context/) | | securityContext、权限 | |
| 配置 ServiceAccount | [为 Pod 配置服务账号](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/configure-service-account/) | | ServiceAccount | |
| 从私有仓库拉镜像 | [从私有仓库拉取镜像](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/pull-image-private-registry/) | | 镜像、私有仓库 | |
| 给容器分配 CPU 资源 | [为容器和 Pod 分配 CPU 资源](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/assign-cpu-resource/) | | CPU、requests、limits | |
| 给容器分配内存资源 | [为容器和 Pod 分配内存资源](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/assign-memory-resource/) | | 内存、资源 | |
| 分配 Pod 级资源 | [assign-pod-level-resources](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/assign-pod-level-resources/) | | Pod 级资源 | |
| 原地调整 Pod 资源 | [resize-pod-resources](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/resize-pod-resources/) | | 调整资源、原地扩容 | |
| 原地调整容器资源 | [resize-container-resources](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/resize-container-resources/) | | 调整资源 | |
| 配置 Pod 服务质量 | [配置 Pod 的服务质量](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/quality-service-pod/) | | QoS | |
| 把 Pod 指派给节点 | [将 Pod 指派给节点](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/assign-pods-nodes/) | | 节点选择、nodeSelector | |
| 用节点亲和性指派 Pod | [assign-pods-nodes-using-node-affinity](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/assign-pods-nodes-using-node-affinity/) | | 亲和性、affinity | |
| 配置 Pod 初始化 | [配置 Pod 初始化](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/configure-pod-initialization/) | | init、初始化 | |
| 配置生命周期事件处理 | [attach-handler-lifecycle-event](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/attach-handler-lifecycle-event/) | | 生命周期钩子 | |
| 配置卷存储 | [配置卷存储](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/configure-volume-storage/) | | 卷、emptyDir | |
| 配置持久卷存储 | [configure-persistent-volume-storage](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/configure-persistent-volume-storage/) | | PV、PVC | |
| 配置投射卷 | [configure-projected-volume-storage](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/configure-projected-volume-storage/) | | 投射卷 | |
| 共享进程命名空间 | [share-process-namespace](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/share-process-namespace/) | | 进程命名空间 | |
| 用命名空间标签强制安全标准 | [enforce-standards-namespace-labels](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/) | | PSS、命名空间标签 | |
| 用准入控制器强制安全标准 | [enforce-standards-admission-controller](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/enforce-standards-admission-controller/) | | 准入、安全标准 | |
| 从 PSP 迁移 | [migrate-from-psp](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/migrate-from-psp/) | | PSP、迁移 | |
| 查容器配置总览 | [配置 Pod 和容器](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/) | | 配置 | |
| 用 kubectl 管理 Secret | [使用 kubectl 管理 Secret](https://kubernetes.io/zh-cn/docs/tasks/configmap-secret/managing-secret-using-kubectl/) | | Secret、kubectl | |
| 用配置文件管理 Secret | [使用配置文件管理 Secret](https://kubernetes.io/zh-cn/docs/tasks/configmap-secret/managing-secret-using-config-file/) | | Secret | |
| 用 Kustomize 管理 Secret | [使用 Kustomize 管理 Secret](https://kubernetes.io/zh-cn/docs/tasks/configmap-secret/managing-secret-using-kustomize/) | | Secret、Kustomize | |
| 运行无状态应用 Deployment | [使用 Deployment 运行一个无状态应用](https://kubernetes.io/zh-cn/docs/tasks/run-application/run-stateless-application-deployment/) | | Deployment、无状态 | |
| 扩缩 Deployment | [缩放 Deployment](https://kubernetes.io/zh-cn/docs/tasks/run-application/scale-deployment/) | | 扩缩容、scale | |
| 滚动更新 Deployment | [执行滚动更新](https://kubernetes.io/zh-cn/docs/tasks/run-application/update-deployment-rolling/) | | 滚动更新、rollout | |
| 回滚 Deployment | [回滚 Deployment](https://kubernetes.io/zh-cn/docs/tasks/run-application/rollback-deployment/) | | 回滚、undo | |
| 配置 PDB | [配置 Pod 干扰预算](https://kubernetes.io/zh-cn/docs/tasks/run-application/configure-pdb/) | | PDB、干扰预算 | |
| HPA 演练 | [horizontal-pod-autoscale-walkthrough](https://kubernetes.io/zh-cn/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/) | | HPA、演练 | |
| 从 Pod 访问 API | [从 Pod 中访问 Kubernetes API](https://kubernetes.io/zh-cn/docs/tasks/run-application/access-api-from-pod/) | | API、Pod 内访问 | |
| 查运行应用总览 | [运行应用](https://kubernetes.io/zh-cn/docs/tasks/run-application/) | | 运行应用 | |
| 用 Service 访问应用 | [使用 Service 访问集群中的应用](https://kubernetes.io/zh-cn/docs/tasks/access-application-cluster/service-access-application-cluster/) | | Service、访问 | |
| 用 port-forward 访问 | [使用端口转发来访问集群中的应用](https://kubernetes.io/zh-cn/docs/tasks/access-application-cluster/port-forward-access-application-cluster/) | | port-forward | |
| 配置多集群访问 | [配置对多集群的访问](https://kubernetes.io/zh-cn/docs/tasks/access-application-cluster/configure-access-multiple-clusters/) | | 多集群、kubeconfig | |
| 访问集群 | [访问集群](https://kubernetes.io/zh-cn/docs/tasks/access-application-cluster/access-cluster/) | | 访问集群 | |
| 部署 Dashboard | [部署和访问 Kubernetes 仪表板](https://kubernetes.io/zh-cn/docs/tasks/access-application-cluster/web-ui-dashboard/) | | Dashboard、UI | |
| 查访问应用总览 | [访问集群中的应用](https://kubernetes.io/zh-cn/docs/tasks/access-application-cluster/) | | 访问 | |
| 调试 Pod | [调试 Pod](https://kubernetes.io/zh-cn/docs/tasks/debug/debug-application/debug-pods/) | | 调试、排障 | |
| 调试 Service | [调试 Service](https://kubernetes.io/zh-cn/docs/tasks/debug/debug-application/debug-service/) | | 调试、Service | |
| 判断 Pod 失败原因 | [确定 Pod 失败的原因](https://kubernetes.io/zh-cn/docs/tasks/debug/debug-application/determine-reason-pod-failure/) | | 失败原因、排障 | |
| 调试 StatefulSet | [调试 StatefulSet](https://kubernetes.io/zh-cn/docs/tasks/debug/debug-application/debug-statefulset/) | | StatefulSet、调试 | |
| 调试 init 容器 | [调试 Init 容器](https://kubernetes.io/zh-cn/docs/tasks/debug/debug-application/debug-init-containers/) | | init、调试 | |
| 在运行容器中执行 shell | [在运行中的容器里执行 shell](https://kubernetes.io/zh-cn/docs/tasks/debug/debug-application/get-shell-running-container/) | | exec、shell | |
| 调试运行中的 Pod | [调试运行中的 Pod](https://kubernetes.io/zh-cn/docs/tasks/debug/debug-application/debug-running-pod/) | | 调试 | |
| 排查 kubectl 故障 | [troubleshoot-kubectl](https://kubernetes.io/zh-cn/docs/tasks/debug/debug-cluster/troubleshoot-kubectl/) | | kubectl、排障 | |
| 用 crictl 调试节点 | [使用 crictl 对 Kubernetes 节点进行调试](https://kubernetes.io/zh-cn/docs/tasks/debug/debug-cluster/crictl/) | | crictl、节点调试 | |
| 监控节点健康 | [监控节点健康](https://kubernetes.io/zh-cn/docs/tasks/debug/debug-cluster/monitor-node-health/) | | 节点健康 | |
| 查资源指标管道 | [resource-metrics-pipeline](https://kubernetes.io/zh-cn/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/) | | 指标、metrics | |
| 查资源使用监控 | [resource-usage-monitoring](https://kubernetes.io/zh-cn/docs/tasks/debug/debug-cluster/resource-usage-monitoring/) | | 监控 | |
| 用 kubectl node 调试 | [kubectl-node-debug](https://kubernetes.io/zh-cn/docs/tasks/debug/debug-cluster/kubectl-node-debug/) | | 节点调试 | |
| 查审计 | [审计](https://kubernetes.io/zh-cn/docs/tasks/debug/debug-cluster/audit/) | | 审计、audit | |
| 查日志架构 | [日志架构](https://kubernetes.io/zh-cn/docs/tasks/debug/logging/) | | 日志 | |
| 查监控总览 | [监控、日志和调试](https://kubernetes.io/zh-cn/docs/tasks/debug/) | | 排障、调试 | |
| 管理集群中的 TLS | [管理集群中的 TLS 认证](https://kubernetes.io/zh-cn/docs/tasks/tls/managing-tls-in-a-cluster/) | | TLS、证书 | |
| 轮换证书 | [certificate-rotation](https://kubernetes.io/zh-cn/docs/tasks/tls/certificate-rotation/) | | 证书轮换 | |
| 管理集群证书 | [管理集群中的证书](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/certificates/) | | 证书 | |
| 声明网络策略 | [声明网络策略](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/declare-network-policy/) | | NetworkPolicy | |
| 安全排空节点 | [安全地清空一个节点](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/safely-drain-node/) | | drain、排空 | |
| 配置命名空间 CPU 默认与限额 | [cpu-default-namespace](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/manage-resources/cpu-default-namespace/) | | CPU、LimitRange | |
| 配置命名空间内存默认与限额 | [memory-default-namespace](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/manage-resources/memory-default-namespace/) | | 内存、LimitRange | |
| 配置命名空间 CPU 约束 | [cpu-constraint-namespace](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/manage-resources/cpu-constraint-namespace/) | | CPU 约束 | |
| 配置命名空间内存约束 | [memory-constraint-namespace](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/manage-resources/memory-constraint-namespace/) | | 内存约束 | |
| 配置命名空间 CPU/内存配额 | [quota-memory-cpu-namespace](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/manage-resources/quota-memory-cpu-namespace/) | | ResourceQuota | |
| 限制命名空间 Pod 数量 | [quota-pod-namespace](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/manage-resources/quota-pod-namespace/) | | 配额、Pod 数 | |
| 配置 kubelet 配置文件 | [kubelet-config-file](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/kubelet-config-file/) | | kubelet、配置 | |
| 配置 CoreDNS | [coredns](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/coredns/) | | DNS、CoreDNS | |
| DNS 调试 | [dns-debugging-resolution](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/dns-debugging-resolution/) | | DNS、排障 | |
| 配置特性门控 | [configure-feature-gates](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/configure-feature-gates/) | | feature gate | |
| 加密静态数据 | [encrypt-data](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/encrypt-data/) | | 加密、etcd | |
| 配置 KMS Provider | [kms-provider](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/kms-provider/) | | KMS、加密 | |
| 用 kubeadm 装集群 | [使用 kubeadm 创建集群](https://kubernetes.io/zh-cn/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/) | | kubeadm、安装 | [kubeadm](https://kubernetes.io/zh-cn/docs/setup/production-environment/tools/kubeadm/) |
| 装 kubeadm | [安装 kubeadm](https://kubernetes.io/zh-cn/docs/setup/production-environment/tools/kubeadm/install-kubeadm/) | | kubeadm | |
| 排查 kubeadm | [对 kubeadm 进行故障排查](https://kubernetes.io/zh-cn/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/) | | kubeadm、排障 | |
| 用 kubeadm 升级集群 | [kubeadm-upgrade](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/) | | 升级 | |
| 用 kubeadm 管理证书 | [kubeadm-certs](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/) | | 证书 | |
| 查 kubeadm 总览 | [kubeadm](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/kubeadm/) | | kubeadm | |
| 查集群管理总览 | [管理集群](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/) | | 集群管理 | |
| 用配置文件管理资源 | [manage-resources](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/manage-resources/) | | 资源管理 | |
| 自定义 Pod 的 hosts 文件 | [customize-hosts-file-for-pods](https://kubernetes.io/zh-cn/docs/tasks/network/customize-hosts-file-for-pods/) | | hosts | |
| 验证双栈 | [validate-dual-stack](https://kubernetes.io/zh-cn/docs/tasks/network/validate-dual-stack/) | | 双栈、IPv6 | |
| 调度 GPU | [调度 GPU](https://kubernetes.io/zh-cn/docs/tasks/manage-gpus/scheduling-gpus/) | | GPU | |
| 用 CronJob 跑定时任务 | [使用 CronJob 运行自动化任务](https://kubernetes.io/zh-cn/docs/tasks/job/automated-tasks-with-cron-jobs/) | | CronJob、定时 | |
| 查 Job 总览 | [Job](https://kubernetes.io/zh-cn/docs/tasks/job/) | | Job | |
| 创建 DaemonSet | [创建 DaemonSet](https://kubernetes.io/zh-cn/docs/tasks/manage-daemon/create-daemon-set/) | | DaemonSet | |
| 更新 DaemonSet | [update-daemon-set](https://kubernetes.io/zh-cn/docs/tasks/manage-daemon/update-daemon-set/) | | DaemonSet、更新 | |
| 回滚 DaemonSet | [rollback-daemon-set](https://kubernetes.io/zh-cn/docs/tasks/manage-daemon/rollback-daemon-set/) | | DaemonSet、回滚 | |
| 只在部分节点跑 Pod | [pods-some-nodes](https://kubernetes.io/zh-cn/docs/tasks/manage-daemon/pods-some-nodes/) | | DaemonSet、节点选择 | |
| 查 tasks 总入口 | [任务](https://kubernetes.io/zh-cn/docs/tasks/) | | 任务 | |
