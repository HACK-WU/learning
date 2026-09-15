# 综合实战项目：三层 Web 应用生产化部署

> 所属课程：[Kubernetes 系统学习](../../00-学习档案.md)｜项目类型：技术域 · 多文件工程｜难度：结课级
> 事实核查：全部结论均在本机 kind v1.34.0 单节点集群实测（核查于 2026-09-14），未实测项已显式标注

## 一句话需求

把一个「能跑起来」的三层 Web 应用（Web 前端 + API 后端 + 数据库），改造成「敢上生产」的形态：**配置外置、密钥不落盘明文、数据能持久化、异常能自愈、能按需扩缩、能在维护时不中断、能隔离东西向流量、出了问题查得到**。

## 目标（完成即达成）

1. 三层分离部署，数据库数据**删 Pod 不丢**（PVC 验证）
2. 配置与镜像解耦（ConfigMap），密钥走 Secret 且**非 root 可读范围受控**
3. 全部容器满足 **restricted** PSA 档（非 root / 禁提权 / 丢能力 / seccomp）
4. Web 层能随 CPU 压力**自动扩容**（HPA 实测）
5. 节点维护（drain）时**服务不中断**（PDB 实测）
6. 默认拒绝东西向流量，只放行必要路径（NetworkPolicy 实测）
7. 出问题有迹可循：探针、事件、日志、资源用量四件套齐全

---

## 覆盖知识点地图（跨阶段整合的证据）

| 知识点 | 所属阶段 / 课 | 本项目落点 |
|--------|---------------|-----------|
| 声明式 API 与调谐 | 阶段 1 / 课 2 | 全部用 YAML 声明，`apply` 后靠控制器收敛 |
| 探针三兄弟 | 阶段 1 / 课 3 | readiness/liveness/startup 三探针齐备 |
| 优雅终止 | 阶段 1 / 课 4 | `preStop` + `terminationGracePeriodSeconds` |
| Deployment 滚动更新 | 阶段 2 / 课 5 | `maxSurge`/`maxUnavailable` 配 PDB |
| StatefulSet | 阶段 2 / 课 6 | 数据库用 StatefulSet（稳定标识 + 独享卷） |
| Service 与 CoreDNS | 阶段 3 / 课 7 | 三层各一个 Service，靠服务名互访 |
| Gateway API | 阶段 3 / 课 9 | 外部入口用 HTTPRoute（Ingress 已冻结） |
| NetworkPolicy | 阶段 3 / 课 10 | 默认拒绝 + 三条精确放行 |
| ConfigMap / Secret | 阶段 4 / 课 11 | 配置外置；Secret 权限 `0400` |
| PV / PVC / StorageClass | 阶段 4 / 课 12 | 数据库 PVC，删 Pod 数据仍在 |
| requests / limits / QoS | 阶段 4 / 课 13 | 三层均设资源声明，DB 为 Guaranteed |
| HPA | 阶段 4 / 课 13 | Web 层 HPA 实测扩容 |
| ResourceQuota / LimitRange | 阶段 4 / 课 13 | 命名空间配额兜底 |
| Kustomize | 阶段 4 / 课 14 | base + overlay 管理多环境 |
| RBAC 与 ServiceAccount | 阶段 5 / 课 15 | 应用专属 SA，`automountServiceAccountToken: false` |
| PSA 与 securityContext | 阶段 5 / 课 16 | 全容器 restricted 档四件套 |
| Secret 加固 | 阶段 5 / 课 17 | 非明文落盘、最小可读范围 |
| 分层排障 | 阶段 6 / 课 18 | 验收清单含故障注入与定位 |
| PDB 与节点维护 | 阶段 6 / 课 19 | drain 演练不中断 |

> **跨阶段统计**：阶段 1（3 点）/ 阶段 2（2 点）/ 阶段 3（3 点）/ 阶段 4（5 点）/ 阶段 5（3 点）/ 阶段 6（2 点）——共 **18 个知识点落点，6 个阶段全覆盖**。

## 运行方式

> 全部命令在 WSL Ubuntu 的 `k8s-c1` 集群上执行（kubectl v1.34.0 / kind v0.30.0）。

一键部署（base 环境）：

```bash
kubectl apply -k 实现/base
```

验证与压测：

```bash
bash 实现/verify.sh
```

清理：

```bash
bash 实现/cleanup.sh
```

## 目录说明

```
实现/
├── base/                  # Kustomize base：三层完整清单
│   ├── namespace.yaml     # ns + ResourceQuota + LimitRange
│   ├── database.yaml      # StatefulSet + PVC + headless Service
│   ├── api.yaml           # API 层 Deployment + Service
│   ├── web.yaml           # Web 层 Deployment + Service + HPA + PDB
│   ├── config.yaml        # ConfigMap + Secret
│   ├── rbac.yaml          # ServiceAccount + Role + RoleBinding
│   ├── networkpolicy.yaml # 默认拒绝 + 三条放行
│   └── kustomization.yaml
├── verify.sh              # 一键验收：逐项断言
├── cleanup.sh             # 一键清理
└── loadgen.yaml           # HPA 压测负载
```

---

## 快速上手路径

1. 先读 [设计决策.md](设计决策.md)——理解每个选择背后的权衡（尤其「为什么数据库不用 Deployment」）
2. 再读 [反例对照.md](反例对照.md)——看「能跑但很糟」的版本长什么样
3. 部署后逐项勾选 [验收清单.md](验收清单.md)

## 实测环境

| 项 | 值 |
|----|-----|
| 集群 | kind `k8s-c1` v1.34.0（**单节点**，control-plane 兼工作节点） |
| 节点资源 | 20 核 / 32582808Ki（约 31 Gi）可分配 |
| CNI | kindnet v20250512（**实测执行 NetworkPolicy**） |
| StorageClass | `standard`（rancher.io/local-path，`WaitForFirstConsumer`，`allowVolumeExpansion=false`） |
| 入口 | Gateway API v1.4.1 + Envoy Gateway v1.6.1（GatewayClass `eg` ACCEPTED=True） |
| 监控 | metrics-server v0.9.0（`kubectl top` 可用，HPA 前提） |
| CSI 驱动 | **无**（`kubectl get csidriver` 为空） |

> ⚠️ **单节点局限**：本项目所有「多副本高可用」均为**同一节点上的多副本**，无法验证真正的节点级容灾。`PodAntiAffinity` 在单节点上会导致副本 Pending，故讲义中给出但实战里**不启用**，这一点在 [设计决策.md](设计决策.md) 中显式说明。
