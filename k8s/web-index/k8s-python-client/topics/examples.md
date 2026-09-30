# examples（Kubernetes Python Client · 共 42 条）

> 范围：`examples/` 目录（官方可运行示例）· 生成日期：2026-09-21
> 全部为仓库真实文件（浅克隆 master，HEAD `aa8f73b` 核实存在）。运行方式：`python -m examples.<文件名>`

## 配置与连接

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 从本机 kubeconfig 连集群（集群外） | [out_of_cluster_config.py](https://github.com/kubernetes-client/python/blob/master/examples/out_of_cluster_config.py) | | load_kube_config、kubeconfig、集群外 | [pick_kube_config_context.py](https://github.com/kubernetes-client/python/blob/master/examples/pick_kube_config_context.py) |
| 在 Pod 内用 ServiceAccount token 连 API | [in_cluster_config.py](https://github.com/kubernetes-client/python/blob/master/examples/in_cluster_config.py) | | load_incluster_config、SA token、Pod 内 | [remote_cluster.py](https://github.com/kubernetes-client/python/blob/master/examples/remote_cluster.py) |
| 切到 kubeconfig 里某个指定 context | [pick_kube_config_context.py](https://github.com/kubernetes-client/python/blob/master/examples/pick_kube_config_context.py) | | context 切换、多集群 | [multiple_clusters.py](https://github.com/kubernetes-client/python/blob/master/examples/multiple_clusters.py) |
| 同时操作多个集群（多 ApiClient 并存） | [multiple_clusters.py](https://github.com/kubernetes-client/python/blob/master/examples/multiple_clusters.py) | | 多集群、并发、多 ApiClient | |
| 用非默认方式连远端集群（自定义 host/token） | [remote_cluster.py](https://github.com/kubernetes-client/python/blob/master/examples/remote_cluster.py) | | 远端集群、Configuration 直配 | |
| 打开调试日志看客户端实际发了什么 HTTP 请求 | [enable_debug_logging.py](https://github.com/kubernetes-client/python/blob/master/examples/enable_debug_logging.py) | | 调试日志、排障、HTTP 报文 | [devel/debug_logging.md](https://github.com/kubernetes-client/python/blob/master/devel/debug_logging.md) |

## 工作负载 CRUD

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 创建 Deployment（最小可用） | [deployment_create.py](https://github.com/kubernetes-client/python/blob/master/examples/deployment_create.py) | | Deployment、创建、V1Deployment | [deployment_crud.py](https://github.com/kubernetes-client/python/blob/master/examples/deployment_crud.py) |
| 完整走一遍 Deployment 增删改查 | [deployment_crud.py](https://github.com/kubernetes-client/python/blob/master/examples/deployment_crud.py) | | CRUD、Deployment、replace、delete | |
| 操作 Job（创建/查询/清理） | [job_crud.py](https://github.com/kubernetes-client/python/blob/master/examples/job_crud.py) | | Job、批处理、CRUD | [cronjob_crud.py](https://github.com/kubernetes-client/python/blob/master/examples/cronjob_crud.py) |
| 操作 CronJob | [cronjob_crud.py](https://github.com/kubernetes-client/python/blob/master/examples/cronjob_crud.py) | | CronJob、定时任务 | |
| 创建 Ingress | [ingress_create.py](https://github.com/kubernetes-client/python/blob/master/examples/ingress_create.py) | | Ingress、路由、创建 | |
| 给 Deployment 打/删注解 | [annotate_deployment.py](https://github.com/kubernetes-client/python/blob/master/examples/annotate_deployment.py) | | 注解、annotate、patch | |
| 读取节点标签、Pod 配置等列表信息 | [node_labels.py](https://github.com/kubernetes-client/python/blob/master/examples/node_labels.py) | | Node、标签、label | [pod_config_list.py](https://github.com/kubernetes-client/python/blob/master/examples/pod_config_list.py) |
| 列出 Pod 及其配置 | [pod_config_list.py](https://github.com/kubernetes-client/python/blob/master/examples/pod_config_list.py) | | Pod、列表、list | |
| 对 DaemonSet 做滚动更新 | [rollout-daemonset.py](https://github.com/kubernetes-client/python/blob/master/examples/rollout-daemonset.py) | | DaemonSet、滚动更新、rollout | [rollout-statefulset.py](https://github.com/kubernetes-client/python/blob/master/examples/rollout-statefulset.py) |
| 对 StatefulSet 做滚动更新 | [rollout-statefulset.py](https://github.com/kubernetes-client/python/blob/master/examples/rollout-statefulset.py) | | StatefulSet、滚动更新 | |

## patch 与 apply

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| patch 一个 ConfigMap（含 content_type 写法） | [patch_namespaced_config_map.py](https://github.com/kubernetes-client/python/blob/master/examples/patch_namespaced_config_map.py) | | patch、ConfigMap、content_type | [devel/patch_types.md](https://github.com/kubernetes-client/python/blob/master/devel/patch_types.md) |
| 用 dict 做 server-side apply | [apply_from_dict.py](https://github.com/kubernetes-client/python/blob/master/examples/apply_from_dict.py) | | server-side apply、apply、dict、field_manager | [apply_from_single_file.py](https://github.com/kubernetes-client/python/blob/master/examples/apply_from_single_file.py) |
| 从单个 YAML 文件 apply | [apply_from_single_file.py](https://github.com/kubernetes-client/python/blob/master/examples/apply_from_single_file.py) | | apply、YAML、文件 | [apply_from_directory.py](https://github.com/kubernetes-client/python/blob/master/examples/apply_from_directory.py) |
| 批量 apply 整个目录的 YAML | [apply_from_directory.py](https://github.com/kubernetes-client/python/blob/master/examples/apply_from_directory.py) | | apply、目录、批量 | |
| 看 apply 用的 YAML 样例子目录 | [examples/yaml_dir/](https://github.com/kubernetes-client/python/tree/master/examples/yaml_dir) | | YAML 样例、apply 素材 | |
| 处理 GEP-2257 的 duration 字段格式 | [duration-gep2257.py](https://github.com/kubernetes-client/python/blob/master/examples/duration-gep2257.py) | | duration、GEP-2257、时间格式 | |

## watch 与 informer

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| watch 某个 namespace 下的 Pod | [watch/pod_namespace_watch.py](https://github.com/kubernetes-client/python/blob/master/examples/watch/pod_namespace_watch.py) | | watch、stream、Pod | [README 的 watch 示例](https://github.com/kubernetes-client/python#readme) |
| watch 断连后怎么恢复（410 Gone / resource_version） | [watch/watch_recovery.py](https://github.com/kubernetes-client/python/blob/master/examples/watch/watch_recovery.py) | | 410 Gone、resource_version、断点续传、恢复 | |
| 搞清 `timeout_seconds` 与 `_request_timeout` 的区别 | [watch/timeout-settings.md](https://github.com/kubernetes-client/python/blob/master/examples/watch/timeout-settings.md) | | 超时、服务端超时、客户端超时、网络中断 | |
| 用 informer 模式做本地缓存与增量同步 | [informer_example.py](https://github.com/kubernetes-client/python/blob/master/examples/informer_example.py) | | informer、缓存、增量同步、list-watch | |

## 运行时 I/O（日志 / exec / 端口转发）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 读 Pod 日志（阻塞式流式） | [pod_logs.py](https://github.com/kubernetes-client/python/blob/master/examples/pod_logs.py) | | 日志、log、stream、阻塞 | [pod_logs_non_blocking.py](https://github.com/kubernetes-client/python/blob/master/examples/pod_logs_non_blocking.py) |
| 非阻塞读日志 + 优雅退出 | [pod_logs_non_blocking.py](https://github.com/kubernetes-client/python/blob/master/examples/pod_logs_non_blocking.py) | | 日志、非阻塞、优雅退出 | |
| 在 Pod 里执行命令（exec） | [pod_exec.py](https://github.com/kubernetes-client/python/blob/master/examples/pod_exec.py) | | exec、执行命令、stream、websocket | |
| 做端口转发（port-forward） | [pod_portforward.py](https://github.com/kubernetes-client/python/blob/master/examples/pod_portforward.py) | | port-forward、端口转发、socket | |

## 自定义资源与动态客户端

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 操作 namespace 级自定义资源（CustomObjectsApi） | [namespaced_custom_object.py](https://github.com/kubernetes-client/python/blob/master/examples/namespaced_custom_object.py) | | CRD、自定义资源、CustomObjectsApi | [cluster_scoped_custom_object.py](https://github.com/kubernetes-client/python/blob/master/examples/cluster_scoped_custom_object.py) |
| 操作集群级自定义资源 | [cluster_scoped_custom_object.py](https://github.com/kubernetes-client/python/blob/master/examples/cluster_scoped_custom_object.py) | | CRD、集群级、CustomObjectsApi | |
| 用 DynamicClient 操作任意资源（无需生成模型） | [dynamic-client/configmap.py](https://github.com/kubernetes-client/python/blob/master/examples/dynamic-client/configmap.py) | | dynamic、DynamicClient、动态客户端 | [dynamic-client 目录](https://github.com/kubernetes-client/python/tree/master/examples/dynamic-client) |
| 用 DynamicClient 操作 Deployment（含滚动重启） | [dynamic-client/deployment_rolling_restart.py](https://github.com/kubernetes-client/python/blob/master/examples/dynamic-client/deployment_rolling_restart.py) | | dynamic、滚动重启、restart | |
| 用 DynamicClient 操作 namespace 级 CR | [dynamic-client/namespaced_custom_resource.py](https://github.com/kubernetes-client/python/blob/master/examples/dynamic-client/namespaced_custom_resource.py) | | dynamic、CR、自定义资源 | |
| 用 DynamicClient 操作集群级 CR | [dynamic-client/cluster_scoped_custom_resource.py](https://github.com/kubernetes-client/python/blob/master/examples/dynamic-client/cluster_scoped_custom_resource.py) | | dynamic、CR、集群级 | |
| 用 DynamicClient 操作 Node / Service / RC | [dynamic-client/node.py](https://github.com/kubernetes-client/python/blob/master/examples/dynamic-client/node.py) | | dynamic、Node、Service、RC | [service.py](https://github.com/kubernetes-client/python/blob/master/examples/dynamic-client/service.py)、[replication_controller.py](https://github.com/kubernetes-client/python/blob/master/examples/dynamic-client/replication_controller.py) |
| 给动态客户端设请求超时（避免网络中断后永久挂起） | [dynamic-client/request_timeout.py](https://github.com/kubernetes-client/python/blob/master/examples/dynamic-client/request_timeout.py) | | 超时、request_timeout、挂起 | [timeout-settings.md](https://github.com/kubernetes-client/python/blob/master/examples/watch/timeout-settings.md) |
| 设置 Accept 头（指定返回的 apiVersion 格式） | [dynamic-client/accept_header.py](https://github.com/kubernetes-client/python/blob/master/examples/dynamic-client/accept_header.py) | | Accept 头、apiVersion、序列化 | |

## 其他

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 发现集群支持哪些 API（api_groups / 资源列表） | [api_discovery.py](https://github.com/kubernetes-client/python/blob/master/examples/api_discovery.py) | | API 发现、discovery、api_groups | |
| 读 metrics（需 metrics-server） | [metrics_example.py](https://github.com/kubernetes-client/python/blob/master/examples/metrics_example.py) | | metrics、指标、metrics-server | |
| 看 examples 目录总说明与运行前置条件 | [examples/README.md](https://github.com/kubernetes-client/python/blob/master/examples/README.md) | | 示例说明、运行方式、前置条件 | |
| 看 notebooks 示例目录 | [examples/notebooks/](https://github.com/kubernetes-client/python/tree/master/examples/notebooks) | | notebook、Jupyter | |
