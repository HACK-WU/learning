# reference（Kubernetes Python Client · 共 19 条）

> 范围：自动生成的 API 参考（`kubernetes/docs/`，共 911 个 md）+ 官方 client-libraries 页 · 生成日期：2026-09-21

## 入口与用法

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 找某个 API 类的方法清单与参数（总入口） | [kubernetes/docs/](https://github.com/kubernetes-client/python/tree/master/kubernetes/docs) | | API 参考、方法清单、参数 | |
| 看全部 API 与 Model 的索引说明 | [kubernetes/README.md](https://github.com/kubernetes-client/python/blob/master/kubernetes/README.md) | | 文档总入口、API 列表、Model 列表 | |
| 了解官方对各语言客户端的定位与支持级别 | [Client Libraries](https://kubernetes.io/docs/reference/using-api/client-libraries/) | | 客户端库、选型、支持级别、社区维护 | |
| 看 v1.34 版本站上的客户端库页（与本机集群同版本） | [v1.34 Client Libraries](https://v1-34.docs.kubernetes.io/docs/reference/using-api/client-libraries/) | | 1.34、客户端库、版本站 | |

## 常用 API 类（按讲义出场顺序）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 查 Pod/Service/ConfigMap 等核心资源的操作方法 | [CoreV1Api.md](https://github.com/kubernetes-client/python/blob/master/kubernetes/docs/CoreV1Api.md) | | CoreV1Api、Pod、Service、ConfigMap、Namespace | |
| 查 Deployment/StatefulSet/DaemonSet/ReplicaSet 的方法 | [AppsV1Api.md](https://github.com/kubernetes-client/python/blob/master/kubernetes/docs/AppsV1Api.md) | | AppsV1Api、Deployment、StatefulSet、DaemonSet | |
| 查 Job/CronJob 的方法 | [BatchV1Api.md](https://github.com/kubernetes-client/python/blob/master/kubernetes/docs/BatchV1Api.md) | | BatchV1Api、Job、CronJob | |
| 查 RBAC（Role/ClusterRole/Binding）的方法 | [RbacAuthorizationV1Api.md](https://github.com/kubernetes-client/python/blob/master/kubernetes/docs/RbacAuthorizationV1Api.md) | | RBAC、Role、ClusterRole、RoleBinding | |
| 查 CRD 与自定义资源（CustomObjectsApi）的方法 | [CustomObjectsApi.md](https://github.com/kubernetes-client/python/blob/master/kubernetes/docs/CustomObjectsApi.md) | | CustomObjectsApi、CRD、自定义资源 | |
| 查 Ingress/NetworkPolicy 等网络资源 | [NetworkingV1Api.md](https://github.com/kubernetes-client/python/blob/master/kubernetes/docs/NetworkingV1Api.md) | | Networking、Ingress、NetworkPolicy、IngressClass | |
| 查 API 发现（api_groups / api_resources） | [ApisApi.md](https://github.com/kubernetes-client/python/blob/master/kubernetes/docs/ApisApi.md) | | discovery、api_groups、api_resources | [api_discovery.py](https://github.com/kubernetes-client/python/blob/master/examples/api_discovery.py) |
| 查版本信息接口 | [VersionApi.md](https://github.com/kubernetes-client/python/blob/master/kubernetes/docs/VersionApi.md) | | 版本、version | |
| 查 HPA v2（autoscaling）的方法 | [AutoscalingV2Api.md](https://github.com/kubernetes-client/python/blob/master/kubernetes/docs/AutoscalingV2Api.md) | | HPA、autoscaling、扩缩容 | |

## 常用模型类（构造对象时查字段）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 构造 Pod 时查 spec 里有哪些字段 | [V1PodSpec.md](https://github.com/kubernetes-client/python/blob/master/kubernetes/docs/V1PodSpec.md) | | PodSpec、字段、容器、卷 | [V1Pod.md](https://github.com/kubernetes-client/python/blob/master/kubernetes/docs/V1Pod.md) |
| 查容器定义（image / ports / resources / probe） | [V1Container.md](https://github.com/kubernetes-client/python/blob/master/kubernetes/docs/V1Container.md) | | Container、镜像、端口、资源、探针 | |
| 查 metadata（labels / annotations / ownerReferences） | [V1ObjectMeta.md](https://github.com/kubernetes-client/python/blob/master/kubernetes/docs/V1ObjectMeta.md) | | metadata、标签、注解、属主引用 | |
| 查错误信息结构（排错时看 status / reason / details） | [V1Status.md](https://github.com/kubernetes-client/python/blob/master/kubernetes/docs/V1Status.md) | | 错误、status、reason、details、ApiException | |
| 查删除选项（propagationPolicy / gracePeriodSeconds） | [V1DeleteOptions.md](https://github.com/kubernetes-client/python/blob/master/kubernetes/docs/V1DeleteOptions.md) | | 删除、级联、propagationPolicy、gracePeriod | |
| 查字段归属记录（server-side apply 冲突排查） | [V1ManagedFieldsEntry.md](https://github.com/kubernetes-client/python/blob/master/kubernetes/docs/V1ManagedFieldsEntry.md) | | managedFields、字段归属、SSA 冲突 | |
