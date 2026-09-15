# concepts（Kubernetes 文档 · 共 177 条）

> 范围：/zh-cn/docs/concepts/ · 生成日期：2026-09-10
> 分区名取自站点 sitemap 的 scope 后第一个路径段（脚本「分区建议」列）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 讲清 k8s 是什么、能做什么 | [概述](https://kubernetes.io/zh-cn/docs/concepts/overview/) | | 概述、是什么、能力 | |
| 找控制面与节点组件清单 | [Kubernetes 组件](https://kubernetes.io/zh-cn/docs/concepts/overview/components/) | | 组件、控制面、kubelet | |
| 讲集群架构总览 | [架构](https://kubernetes.io/zh-cn/docs/concepts/architecture/) | | 架构、整体 | |
| 讲控制面与节点的通信方式 | [控制面到节点通信](https://kubernetes.io/zh-cn/docs/concepts/architecture/control-plane-node-communication/) | | 通信、apiserver、kubelet | |
| 讲节点是什么、怎么管理 | [节点](https://kubernetes.io/zh-cn/docs/concepts/architecture/nodes/) | | 节点、node | |
| 讲控制器与调谐循环 | [控制器](https://kubernetes.io/zh-cn/docs/concepts/architecture/controller/) | | 控制器、调谐、reconcile | |
| 讲租约机制（Lease） | [leases](https://kubernetes.io/zh-cn/docs/concepts/architecture/leases/) | | 租约、心跳、领导选举 | |
| 讲云控制器管理器 | [云控制器管理器](https://kubernetes.io/zh-cn/docs/concepts/architecture/cloud-controller/) | | CCM、云厂商 | |
| 讲自愈能力 | [self-healing](https://kubernetes.io/zh-cn/docs/concepts/architecture/self-healing/) | | 自愈、重启、重建 | |
| 讲 cgroups 与资源隔离基础 | [cgroups](https://kubernetes.io/zh-cn/docs/concepts/architecture/cgroups/) | | cgroup、隔离 | |
| 讲垃圾回收与级联删除 | [垃圾回收](https://kubernetes.io/zh-cn/docs/concepts/architecture/garbage-collection/) | | GC、级联删除、ownerReference | |
| 讲混合版本代理 | [mixed-version-proxy](https://kubernetes.io/zh-cn/docs/concepts/architecture/mixed-version-proxy/) | | 版本、升级 | |
| 理解对象的 spec 与 status | [理解 Kubernetes 对象](https://kubernetes.io/zh-cn/docs/concepts/overview/working-with-objects/kubernetes-objects/) | #object-spec-and-status | spec、status、期望状态 | |
| 查对象的名字与 UID 规则 | [对象名称和 ID](https://kubernetes.io/zh-cn/docs/concepts/overview/working-with-objects/names/) | | 名称、UID、命名 | |
| 查命名空间怎么用 | [名字空间](https://kubernetes.io/zh-cn/docs/concepts/overview/working-with-objects/namespaces/) | | namespace、隔离、分组 | |
| 查标签与选择算符写法 | [标签和选择算符](https://kubernetes.io/zh-cn/docs/concepts/overview/working-with-objects/labels/) | | 标签、selector、匹配 | |
| 查注解的用途 | [注解](https://kubernetes.io/zh-cn/docs/concepts/overview/working-with-objects/annotations/) | | annotation、元数据 | |
| 查字段选择器怎么写 | [字段选择算符](https://kubernetes.io/zh-cn/docs/concepts/overview/working-with-objects/field-selectors/) | | field selector、过滤 | |
| 查推荐通用标签 | [推荐使用的标签](https://kubernetes.io/zh-cn/docs/concepts/overview/working-with-objects/common-labels/) | | 标签、约定 | |
| 讲对象管理三种方式的区别 | [Kubernetes 对象管理](https://kubernetes.io/zh-cn/docs/concepts/overview/working-with-objects/object-management/) | | 命令式、声明式、管理方式 | [declarative-config](https://kubernetes.io/zh-cn/docs/tasks/manage-kubernetes-objects/declarative-config/) |
| 讲属主与从属关系（级联删除依据） | [属主与附属](https://kubernetes.io/zh-cn/docs/concepts/overview/working-with-objects/owners-dependents/) | | owner、属主、级联 | |
| 讲 finalizer 拦删除的机制 | [finalizers](https://kubernetes.io/zh-cn/docs/concepts/overview/working-with-objects/finalizers/) | | finalizer、删除拦截 | |
| 讲存储版本迁移 | [storage-version](https://kubernetes.io/zh-cn/docs/concepts/overview/working-with-objects/storage-version/) | | 存储版本 | |
| 查 kubectl 的定位与用法 | [kubectl](https://kubernetes.io/zh-cn/docs/concepts/overview/kubectl/) | | kubectl、命令行 | |
| 讲 k8s API 的整体概念 | [Kubernetes API](https://kubernetes.io/zh-cn/docs/concepts/overview/kubernetes-api/) | | API、资源、GVK | [api-concepts](https://kubernetes.io/zh-cn/docs/reference/using-api/api-concepts/) |
| 讲工作负载总览 | [工作负载](https://kubernetes.io/zh-cn/docs/concepts/workloads/) | | 工作负载、workload | |
| 讲 Pod 是什么 | [Pod](https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/) | | Pod、最小单元 | |
| 讲 Pod 生命周期与阶段 | [Pod 的生命周期](https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/pod-lifecycle/) | | 生命周期、Pending、Running | |
| 讲 Pod 状况（Conditions） | [pod-condition](https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/pod-condition/) | | condition、Ready | |
| 讲 init 容器 | [Init 容器](https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/init-containers/) | | init、初始化 | |
| 讲边车容器 | [sidecar-containers](https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/sidecar-containers/) | | sidecar、边车 | |
| 讲临时容器（调试用） | [临时容器](https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/ephemeral-containers/) | | 调试、临时容器 | |
| 讲存活/就绪/启动探针 | [probes](https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/probes/) | | 探针、健康检查 | [配置探针](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) |
| 讲 Pod 的 QoS 等级 | [pod-qos](https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/pod-qos/) | | QoS、Guaranteed、Burstable | |
| 讲 Pod 主机名与 DNS | [pod-hostname](https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/pod-hostname/) | | 主机名、hostname | |
| 讲静态 Pod | [静态 Pod](https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/static-pods/) | | 静态 Pod、kubelet | |
| 讲 Pod 中断预算 | [disruptions](https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/disruptions/) | | PDB、中断、驱逐 | |
| 讲用户命名空间隔离 | [user-namespaces](https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/user-namespaces/) | | userns、隔离 | |
| 讲 downward API | [downward-api](https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/downward-api/) | | downward API、暴露信息 | |
| 讲 Pod 高级配置 | [advanced-pod-config](https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/advanced-pod-config/) | | 高级配置 | |
| 讲 Pod 调度组 | [scheduling-group](https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/scheduling-group/) | | 调度组 | |
| 讲控制器总览 | [控制器](https://kubernetes.io/zh-cn/docs/concepts/workloads/controllers/) | | 控制器、Deployment | |
| 讲 Deployment | [Deployment](https://kubernetes.io/zh-cn/docs/concepts/workloads/controllers/deployment/) | | Deployment、副本、滚动更新 | |
| 讲 ReplicaSet | [ReplicaSet](https://kubernetes.io/zh-cn/docs/concepts/workloads/controllers/replicaset/) | | ReplicaSet、副本集 | |
| 讲 ReplicationController（旧） | [replicationcontroller](https://kubernetes.io/zh-cn/docs/concepts/workloads/controllers/replicationcontroller/) | | RC、废弃 | |
| 讲 StatefulSet | [StatefulSet](https://kubernetes.io/zh-cn/docs/concepts/workloads/controllers/statefulset/) | | 有状态、StatefulSet | |
| 讲 DaemonSet | [DaemonSet](https://kubernetes.io/zh-cn/docs/concepts/workloads/controllers/daemonset/) | | DaemonSet、每节点 | |
| 讲 Job | [Job](https://kubernetes.io/zh-cn/docs/concepts/workloads/controllers/job/) | | Job、批处理 | |
| 讲 CronJob | [CronJob](https://kubernetes.io/zh-cn/docs/concepts/workloads/controllers/cron-jobs/) | | 定时、CronJob | |
| 讲 Job 的 TTL 自动清理 | [ttlafterfinished](https://kubernetes.io/zh-cn/docs/concepts/workloads/controllers/ttlafterfinished/) | | TTL、自动清理 | |
| 讲工作负载管理（扩缩容） | [management](https://kubernetes.io/zh-cn/docs/concepts/workloads/management/) | | 管理、扩缩容 | |
| 讲自动扩缩容总览 | [autoscaling](https://kubernetes.io/zh-cn/docs/concepts/workloads/autoscaling/) | | 自动扩缩容 | |
| 讲 HPA 水平扩缩容 | [horizontal-pod-autoscale](https://kubernetes.io/zh-cn/docs/concepts/workloads/autoscaling/horizontal-pod-autoscale/) | | HPA、水平扩容 | |
| 查 Workload API 总览 | [workload-api](https://kubernetes.io/zh-cn/docs/concepts/workloads/workload-api/) | | workload API | |
| 讲干扰预算与优先级 | [disruption-and-priority](https://kubernetes.io/zh-cn/docs/concepts/workloads/workload-api/disruption-and-priority/) | | 干扰、优先级 | |
| 讲工作负载策略 | [policies](https://kubernetes.io/zh-cn/docs/concepts/workloads/workload-api/policies/) | | 策略 | |
| 讲拓扑感知调度（Workload API） | [topology-aware-scheduling](https://kubernetes.io/zh-cn/docs/concepts/workloads/workload-api/topology-aware-scheduling/) | | 拓扑、调度 | |
| 讲 PodGroup API 生命周期 | [podgroup-api/lifecycle](https://kubernetes.io/zh-cn/docs/concepts/workloads/podgroup-api/lifecycle/) | | PodGroup、成组调度 | |
| 查 PodGroup API 总览 | [podgroup-api](https://kubernetes.io/zh-cn/docs/concepts/workloads/podgroup-api/) | | PodGroup | |
| 讲 Service | [Service](https://kubernetes.io/zh-cn/docs/concepts/services-networking/service/) | | Service、服务发现 | |
| 讲 Ingress | [Ingress](https://kubernetes.io/zh-cn/docs/concepts/services-networking/ingress/) | | Ingress、入口 | |
| 讲 Ingress 控制器 | [Ingress 控制器](https://kubernetes.io/zh-cn/docs/concepts/services-networking/ingress-controllers/) | | Ingress 控制器 | |
| 讲 Gateway API | [Gateway](https://kubernetes.io/zh-cn/docs/concepts/services-networking/gateway/) | | Gateway、Ingress 替代 | |
| 讲 DNS 与服务发现 | [DNS](https://kubernetes.io/zh-cn/docs/concepts/services-networking/dns-pod-service/) | | DNS、服务发现 | |
| 讲网络策略 | [网络策略](https://kubernetes.io/zh-cn/docs/concepts/services-networking/network-policies/) | | NetworkPolicy、隔离 | |
| 讲 EndpointSlice | [endpoint-slices](https://kubernetes.io/zh-cn/docs/concepts/services-networking/endpoint-slices/) | | EndpointSlice | |
| 讲双栈 IPv4/IPv6 | [dual-stack](https://kubernetes.io/zh-cn/docs/concepts/services-networking/dual-stack/) | | 双栈、IPv6 | |
| 讲服务流量策略 | [service-traffic-policy](https://kubernetes.io/zh-cn/docs/concepts/services-networking/service-traffic-policy/) | | 流量策略 | |
| 讲拓扑感知路由 | [topology-aware-routing](https://kubernetes.io/zh-cn/docs/concepts/services-networking/topology-aware-routing/) | | 拓扑路由 | |
| 讲 ClusterIP 分配 | [cluster-ip-allocation](https://kubernetes.io/zh-cn/docs/concepts/services-networking/cluster-ip-allocation/) | | ClusterIP | |
| 讲 Windows 网络 | [windows-networking](https://kubernetes.io/zh-cn/docs/concepts/services-networking/windows-networking/) | | Windows | |
| 查网络总览 | [services-networking](https://kubernetes.io/zh-cn/docs/concepts/services-networking/) | | 网络、服务 | |
| 讲卷（Volume） | [卷](https://kubernetes.io/zh-cn/docs/concepts/storage/volumes/) | | Volume、卷 | |
| 讲持久卷 PV | [持久卷](https://kubernetes.io/zh-cn/docs/concepts/storage/persistent-volumes/) | | PV、持久卷 | |
| 讲 StorageClass | [存储类](https://kubernetes.io/zh-cn/docs/concepts/storage/storage-classes/) | | StorageClass | |
| 讲动态制备 | [动态卷制备](https://kubernetes.io/zh-cn/docs/concepts/storage/dynamic-provisioning/) | | 动态制备、PVC | |
| 讲卷快照 | [volume-snapshots](https://kubernetes.io/zh-cn/docs/concepts/storage/volume-snapshots/) | | 快照、备份 | |
| 讲卷快照类 | [volume-snapshot-classes](https://kubernetes.io/zh-cn/docs/concepts/storage/volume-snapshot-classes/) | | 快照类 | |
| 讲投射卷 | [projected-volumes](https://kubernetes.io/zh-cn/docs/concepts/storage/projected-volumes/) | | 投射卷 | |
| 讲临时卷 | [ephemeral-volumes](https://kubernetes.io/zh-cn/docs/concepts/storage/ephemeral-volumes/) | | 临时卷 | |
| 讲临时存储 | [ephemeral-storage](https://kubernetes.io/zh-cn/docs/concepts/storage/ephemeral-storage/) | | 临时存储 | |
| 讲 PVC 数据源 | [volume-pvc-datasource](https://kubernetes.io/zh-cn/docs/concepts/storage/volume-pvc-datasource/) | | 数据源、克隆 | |
| 讲卷填充器 | [volume-populators-and-data-sources](https://kubernetes.io/zh-cn/docs/concepts/storage/volume-populators-and-data-sources/) | | 填充器 | |
| 讲卷属性类 | [volume-attributes-classes](https://kubernetes.io/zh-cn/docs/concepts/storage/volume-attributes-classes/) | | 卷属性 | |
| 讲卷健康监测 | [volume-health-monitoring](https://kubernetes.io/zh-cn/docs/concepts/storage/volume-health-monitoring/) | | 健康监测 | |
| 讲存储容量与限制 | [storage-capacity](https://kubernetes.io/zh-cn/docs/concepts/storage/storage-capacity/) | | 容量 | |
| 讲卷模式与访问限制 | [storage-limits](https://kubernetes.io/zh-cn/docs/concepts/storage/storage-limits/) | | 存储限制 | |
| 讲 Windows 存储 | [windows-storage](https://kubernetes.io/zh-cn/docs/concepts/storage/windows-storage/) | | Windows | |
| 查存储总览 | [storage](https://kubernetes.io/zh-cn/docs/concepts/storage/) | | 存储 | |
| 讲调度器 | [kube-scheduler](https://kubernetes.io/zh-cn/docs/concepts/scheduling-eviction/kube-scheduler/) | | 调度器、调度 | |
| 讲把 Pod 指派给节点 | [assign-pod-node](https://kubernetes.io/zh-cn/docs/concepts/scheduling-eviction/assign-pod-node/) | | 指派、节点选择 | |
| 讲污点与容忍 | [污点和容忍度](https://kubernetes.io/zh-cn/docs/concepts/scheduling-eviction/taint-and-toleration/) | | 污点、容忍 | |
| 讲 Pod 优先级与抢占 | [pod-priority-preemption](https://kubernetes.io/zh-cn/docs/concepts/scheduling-eviction/pod-priority-preemption/) | | 优先级、抢占 | |
| 讲节点压力驱逐 | [node-pressure-eviction](https://kubernetes.io/zh-cn/docs/concepts/scheduling-eviction/node-pressure-eviction/) | | 驱逐、压力 | |
| 讲 API 发起的驱逐 | [api-eviction](https://kubernetes.io/zh-cn/docs/concepts/scheduling-eviction/api-eviction/) | | 驱逐 API | |
| 讲拓扑分布约束 | [topology-spread-constraints](https://kubernetes.io/zh-cn/docs/concepts/scheduling-eviction/topology-spread-constraints/) | | 拓扑、打散 | |
| 讲 Pod 调度就绪 | [pod-scheduling-readiness](https://kubernetes.io/zh-cn/docs/concepts/scheduling-eviction/pod-scheduling-readiness/) | | 调度就绪 | |
| 讲 Pod 开销 | [pod-overhead](https://kubernetes.io/zh-cn/docs/concepts/scheduling-eviction/pod-overhead/) | | 开销、overhead | |
| 讲调度框架 | [scheduling-framework](https://kubernetes.io/zh-cn/docs/concepts/scheduling-eviction/scheduling-framework/) | | 框架、插件 | |
| 讲调度器性能调优 | [scheduler-perf-tuning](https://kubernetes.io/zh-cn/docs/concepts/scheduling-eviction/scheduler-perf-tuning/) | | 性能、调优 | |
| 讲 gang scheduling | [gang-scheduling](https://kubernetes.io/zh-cn/docs/concepts/scheduling-eviction/gang-scheduling/) | | 成组调度 | |
| 讲 PodGroup 调度 | [podgroup-scheduling](https://kubernetes.io/zh-cn/docs/concepts/scheduling-eviction/podgroup-scheduling/) | | PodGroup | |
| 讲工作负载感知抢占 | [workload-aware-preemption](https://kubernetes.io/zh-cn/docs/concepts/scheduling-eviction/workload-aware-preemption/) | | 抢占 | |
| 讲资源装箱 | [resource-bin-packing](https://kubernetes.io/zh-cn/docs/concepts/scheduling-eviction/resource-bin-packing/) | | 装箱、装箱率 | |
| 讲节点声明的特性 | [node-declared-features](https://kubernetes.io/zh-cn/docs/concepts/scheduling-eviction/node-declared-features/) | | 节点特性 | |
| 讲调度与驱逐总览 | [scheduling-eviction](https://kubernetes.io/zh-cn/docs/concepts/scheduling-eviction/) | | 调度、驱逐 | |
| 查安全总览 | [security](https://kubernetes.io/zh-cn/docs/concepts/security/) | | 安全 | |
| 讲云原生安全模型 | [cloud-native-security](https://kubernetes.io/zh-cn/docs/concepts/security/cloud-native-security/) | | 云原生安全、4C | |
| 讲访问控制（认证/鉴权/准入） | [controlling-access](https://kubernetes.io/zh-cn/docs/concepts/security/controlling-access/) | | 认证、鉴权、RBAC | |
| 讲 RBAC 最佳实践 | [rbac-good-practices](https://kubernetes.io/zh-cn/docs/concepts/security/rbac-good-practices/) | | RBAC、权限 | |
| 讲 ServiceAccount | [服务账号](https://kubernetes.io/zh-cn/docs/concepts/security/service-accounts/) | | ServiceAccount | |
| 讲 Pod 安全标准 | [pod-security-standards](https://kubernetes.io/zh-cn/docs/concepts/security/pod-security-standards/) | | PSS、安全标准 | |
| 讲 Pod 安全准入 | [pod-security-admission](https://kubernetes.io/zh-cn/docs/concepts/security/pod-security-admission/) | | PSA、准入 | |
| 讲 PodSecurityPolicy（已废弃） | [pod-security-policy](https://kubernetes.io/zh-cn/docs/concepts/security/pod-security-policy/) | | PSP、废弃 | |
| 讲 Secret 安全实践 | [secrets-good-practices](https://kubernetes.io/zh-cn/docs/concepts/security/secrets-good-practices/) | | Secret、密钥 | |
| 讲多租户 | [multi-tenancy](https://kubernetes.io/zh-cn/docs/concepts/security/multi-tenancy/) | | 多租户 | |
| 讲 API Server 绕过风险 | [api-server-bypass-risks](https://kubernetes.io/zh-cn/docs/concepts/security/api-server-bypass-risks/) | | 绕过风险 | |
| 讲 Linux 内核安全约束 | [linux-kernel-security-constraints](https://kubernetes.io/zh-cn/docs/concepts/security/linux-kernel-security-constraints/) | | 内核安全 | |
| 讲 Linux 安全 | [linux-security](https://kubernetes.io/zh-cn/docs/concepts/security/linux-security/) | | Linux 安全 | |
| 讲 Windows 安全 | [windows-security](https://kubernetes.io/zh-cn/docs/concepts/security/windows-security/) | | Windows | |
| 查安全 checklist | [security-checklist](https://kubernetes.io/zh-cn/docs/concepts/security/security-checklist/) | | 安全清单 | |
| 查应用安全 checklist | [application-security-checklist](https://kubernetes.io/zh-cn/docs/concepts/security/application-security-checklist/) | | 应用安全 | |
| 讲调度器加固 | [hardening-guide/scheduler](https://kubernetes.io/zh-cn/docs/concepts/security/hardening-guide/scheduler/) | | 加固 | |
| 讲认证机制加固 | [hardening-guide/authentication-mechanisms](https://kubernetes.io/zh-cn/docs/concepts/security/hardening-guide/authentication-mechanisms/) | | 认证、加固 | |
| 讲 DRA 加固 | [hardening-guide/dynamic-resource-allocation](https://kubernetes.io/zh-cn/docs/concepts/security/hardening-guide/dynamic-resource-allocation/) | | DRA、加固 | |
| 讲 ConfigMap | [ConfigMap](https://kubernetes.io/zh-cn/docs/concepts/configuration/configmap/) | | ConfigMap、配置 | |
| 讲 Secret | [Secret](https://kubernetes.io/zh-cn/docs/concepts/configuration/secret/) | | Secret、密钥 | |
| 讲容器资源管理 | [manage-resources-containers](https://kubernetes.io/zh-cn/docs/concepts/configuration/manage-resources-containers/) | | requests、limits | |
| 讲 kubeconfig 组织集群访问 | [organize-cluster-access-kubeconfig](https://kubernetes.io/zh-cn/docs/concepts/configuration/organize-cluster-access-kubeconfig/) | | kubeconfig、多集群 | |
| 讲 Windows 资源管理 | [windows-resource-management](https://kubernetes.io/zh-cn/docs/concepts/configuration/windows-resource-management/) | | Windows | |
| 查配置总览 | [configuration](https://kubernetes.io/zh-cn/docs/concepts/configuration/) | | 配置 | |
| 讲 LimitRange | [limit-range](https://kubernetes.io/zh-cn/docs/concepts/policy/limit-range/) | | LimitRange、限额 | |
| 讲资源配额 | [resource-quotas](https://kubernetes.io/zh-cn/docs/concepts/policy/resource-quotas/) | | ResourceQuota、配额 | |
| 讲 PID 限制 | [pid-limiting](https://kubernetes.io/zh-cn/docs/concepts/policy/pid-limiting/) | | PID | |
| 讲节点资源管理器 | [node-resource-managers](https://kubernetes.io/zh-cn/docs/concepts/policy/node-resource-managers/) | | 资源管理器 | |
| 查策略总览 | [policy](https://kubernetes.io/zh-cn/docs/concepts/policy/) | | 策略 | |
| 查集群管理总览 | [cluster-administration](https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/) | | 集群管理 | |
| 讲证书管理 | [certificates](https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/certificates/) | | 证书、TLS | |
| 讲节点关闭处理 | [node-shutdown](https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/node-shutdown/) | | 节点关闭 | |
| 讲节点自动扩缩容 | [node-autoscaling](https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/node-autoscaling/) | | 节点扩容 | |
| 讲集群网络 | [networking](https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/networking/) | | 集群网络 | |
| 讲系统日志 | [system-logs](https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/system-logs/) | | 日志 | |
| 讲日志架构 | [logging](https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/logging/) | | 日志架构 | |
| 讲系统指标 | [system-metrics](https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/system-metrics/) | | 指标 | |
| 讲 kube-state-metrics | [kube-state-metrics](https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/kube-state-metrics/) | | KSM、指标 | |
| 讲系统追踪 | [system-traces](https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/system-traces/) | | 追踪 | |
| 讲可观测性 | [observability](https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/observability/) | | 可观测性 | |
| 讲准入 Webhook 最佳实践 | [admission-webhooks-good-practices](https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/admission-webhooks-good-practices/) | | Webhook、准入 | |
| 讲流控（API 优先级与公平性） | [flow-control](https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/flow-control/) | | 流控、限流 | |
| 讲代理 | [proxies](https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/proxies/) | | 代理 | |
| 讲插件（Addons） | [addons](https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/addons/) | | 插件、DNS | |
| 讲协调的领导选举 | [coordinated-leader-election](https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/coordinated-leader-election/) | | 领导选举 | |
| 讲兼容性版本 | [compatibility-version](https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/compatibility-version/) | | 版本兼容 | |
| 讲 DRA（集群管理视角） | [dra](https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/dra/) | | DRA | |
| 讲容器总览 | [containers](https://kubernetes.io/zh-cn/docs/concepts/containers/) | | 容器 | |
| 讲镜像 | [镜像](https://kubernetes.io/zh-cn/docs/concepts/containers/images/) | | 镜像、拉取 | |
| 讲容器运行时接口 CRI | [cri](https://kubernetes.io/zh-cn/docs/concepts/containers/cri/) | | CRI、运行时 | |
| 讲 RuntimeClass | [runtime-class](https://kubernetes.io/zh-cn/docs/concepts/containers/runtime-class/) | | RuntimeClass | |
| 讲容器环境 | [container-environment](https://kubernetes.io/zh-cn/docs/concepts/containers/container-environment/) | | 环境变量 | |
| 讲容器生命周期钩子 | [container-lifecycle-hooks](https://kubernetes.io/zh-cn/docs/concepts/containers/container-lifecycle-hooks/) | | 钩子、hook | |
| 讲自定义资源 | [custom-resources](https://kubernetes.io/zh-cn/docs/concepts/extend-kubernetes/api-extension/custom-resources/) | | CRD、自定义资源 | |
| 讲 API 聚合层 | [apiserver-aggregation](https://kubernetes.io/zh-cn/docs/concepts/extend-kubernetes/api-extension/apiserver-aggregation/) | | 聚合层 | |
| 查 API 扩展总览 | [api-extension](https://kubernetes.io/zh-cn/docs/concepts/extend-kubernetes/api-extension/) | | API 扩展 | |
| 讲 Operator 模式 | [operator](https://kubernetes.io/zh-cn/docs/concepts/extend-kubernetes/operator/) | | Operator | |
| 讲网络插件 | [network-plugins](https://kubernetes.io/zh-cn/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/) | | CNI、网络插件 | |
| 讲设备插件 | [device-plugins](https://kubernetes.io/zh-cn/docs/concepts/extend-kubernetes/compute-storage-net/device-plugins/) | | 设备插件 | |
| 查计算存储网络扩展总览 | [compute-storage-net](https://kubernetes.io/zh-cn/docs/concepts/extend-kubernetes/compute-storage-net/) | | 扩展 | |
| 查扩展 k8s 总览 | [extend-kubernetes](https://kubernetes.io/zh-cn/docs/concepts/extend-kubernetes/) | | 扩展 | |
| 讲 DRA API | [dra-api](https://kubernetes.io/zh-cn/docs/concepts/resource-management/dynamic-resource-allocation/dra-api/) | | DRA、设备 | |
| 讲 DRA 工作原理 | [how-dra-works](https://kubernetes.io/zh-cn/docs/concepts/resource-management/dynamic-resource-allocation/how-dra-works/) | | DRA | |
| 查 DRA 特性 | [dra-features](https://kubernetes.io/zh-cn/docs/concepts/resource-management/dynamic-resource-allocation/dra-features/) | | DRA | |
| 讲设备污点 | [device-taints](https://kubernetes.io/zh-cn/docs/concepts/resource-management/dynamic-resource-allocation/device-taints/) | | 污点、设备 | |
| 讲 Pod 级资源管理器 | [pod-level-resource-managers](https://kubernetes.io/zh-cn/docs/concepts/resource-management/pod-level-resource-managers/) | | 资源管理 | |
| 讲 Windows 容器总览 | [windows](https://kubernetes.io/zh-cn/docs/concepts/windows/) | | Windows | |
| 讲 Windows 容器介绍 | [windows/intro](https://kubernetes.io/zh-cn/docs/concepts/windows/intro/) | | Windows | |
| 讲 Windows 用户指南 | [windows/user-guide](https://kubernetes.io/zh-cn/docs/concepts/windows/user-guide/) | | Windows | |
| 查 concepts 总入口 | [concepts](https://kubernetes.io/zh-cn/docs/concepts/) | | 概念 | |
| 查 overview 分区入口 | [working-with-objects](https://kubernetes.io/zh-cn/docs/concepts/overview/working-with-objects/) | | 对象操作 | |
