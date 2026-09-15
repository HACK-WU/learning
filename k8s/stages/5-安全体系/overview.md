# 阶段 5：安全体系

> 所属课程：Kubernetes 系统学习 ｜ 故事章节：**谁能对集群做什么** ｜ 上一阶段：[阶段 4《配置 · 存储 · 资源 · 工程化》](../4-配置存储资源工程化/overview.md)

## 🎯 本阶段目标

- 建立 k8s 安全的完整骨架：**谁能访问 API**（认证授权）→ **容器以什么权限运行**（运行时）→ **出了事能不能查到**（审计追溯）
- 能配置最小权限 RBAC，理解 ServiceAccount 默认挂载 token 带来的提权风险
- 能用 Pod 安全标准（PSA）在命名空间层面强制基线，并用 securityContext 加固单个 Pod
- 理解 Secret 的正确加固路径，知道审计日志是事后追溯的唯一凭据

## 📍 学习重点

- **API 安全三段式**：认证（你是谁）→ 授权（你能做什么）→ 准入（这件事能不能这么干）。这三段是理解所有 k8s 安全机制的骨架
- **4C 是安全知识的挂衣钩**：Cloud / Cluster / Container / Code 四层，把本阶段看似零散的机制（RBAC 属 Cluster 层、PSA 与 securityContext 属 Container 层、镜像签名属 Code 层）串成一张图。课 15 开篇先立框架，学生才知道每个机制在防哪一层的攻击
- **RBAC 是白名单模型**：默认拒绝，只授予明确列出的权限。Role 与 ClusterRole 的区别不在「权限大小」而在「作用域」
- **ServiceAccount 的隐式风险**：Pod 默认挂载 SA token，一个只读应用可能因此获得集群操作权限 —— `automountServiceAccountToken: false` 是最容易被忽略的加固项
- **PSP 已被移除**：PodSecurityPolicy 于 v1.25 移除，替代品是 Pod Security Admission（PSA）。本机实测 v1.34 集群 PSA 可用
- **securityContext 决定容器的运行权限**：runAsNonRoot / readOnlyRootFilesystem / capabilities 是运行时加固的三件套
- **Secret 不是加密**：它防「误看」不防「被拿」。真正的加固靠 RBAC + etcd 静态加密 + 外部密钥管理三层叠加
- **审计日志是事后追溯的唯一凭据**：没有审计，入侵发生后就只能靠猜

## ✅ 必须掌握的知识点

| 知识点 | 所属课 | 学完应能 |
|--------|--------|----------|
| 云原生安全 4C 模型 | 课 15 | 说清 Cloud/Cluster/Container/Code 四层各自的安全边界，能把 RBAC、PSA、etcd 加密归位到对应层 |
| API 安全三段式 | 课 15 | 说清认证 / 授权 / 准入各自解决什么问题，以及三者的执行顺序 |
| RBAC | 课 15 | 配置最小权限 Role/ClusterRole 与绑定，能排查「权限不足」类报错 |
| ServiceAccount 与 token 安全 | 课 15 | 说清 SA 的作用与默认挂载风险，会关闭不必要的自动挂载 |
| Pod 安全标准 PSA | 课 16 | 用命名空间标签施加 privileged/baseline/restricted 三档，说清各档约束 |
| securityContext 与 capabilities | 课 16 | 配置 runAsNonRoot / readOnlyRootFilesystem / 丢弃 capabilities |
| 镜像与供应链安全 | 课 16 | 说清镜像来源、签名、漏洞扫描在供应链中的角色 |
| Secret 加固与 etcd 静态加密 | 课 17 | 配置 etcd 加密，说清 Secret 与专业密钥管理方案的边界 |
| 审计日志 | 课 17 | 配置审计策略，能回答「谁在什么时候删了这个资源」 |
| 运行时安全与威胁模型 | 课 17 | 识别常见攻击路径（容器逃逸 / 横向移动 / 提权），理解纵深防御 |

## 🗺️ 本阶段路径图

![阶段 5 路径](./assets/stage-05-security-path.svg)

> SVG 展示三课递进：课 15（谁能访问）→ 课 16（以什么权限跑）→ 课 17（数据怎么保护、出事怎么查）。

## ✅ 课 15 完成情况（2026-09-11）

**讲义**：[lesson-15-RBAC与ServiceAccount.md](lessons/lesson-15-RBAC与ServiceAccount.md)

**阶段状态**：课 15 已完成，下一课为课 16《Pod 安全：PSA 与 securityContext》。

**本课核心结论（除标注项外全部本机实测）**：

1. **API 三道门**：认证（你是谁）→ 授权（你能做什么）→ 准入（能这么干吗），顺序不可颠倒
2. **401 vs 403 精确区分**：**坏 token → 401**；**无 token → 403 且身份是 `system:anonymous`**（推翻"未认证=401"的常见说法）
3. **准入只管写操作**：实测配额满(1/1)时写被拒、读仍成功；准入 Mutating 阶段会**修改对象内容**（自动注入 `kube-api-access-*` 投射卷）
4. **4C 模型**：本课 RBAC/SA 属 **Cluster 层**；课 16 的 PSA/securityContext 属 Container 层
5. **RBAC 是白名单**：**新建 SA 默认零权限**（实测全 `no`）；权限**只加不减**，收窄只能删绑定
6. **Role vs ClusterRole 区别在作用域不在大小**：ClusterRole 也能用 RoleBinding 限在单 ns
7. **排障神器 `kubectl auth can-i --list`**：一眼看清某身份的全部权限
8. **SA token 现代特性**：绑 Pod UID（**删 Pod 即失效**）、不落 Secret（1.24 起不自动生成）、带 aud 受众
9. ⚠️ **token 有效期实测 365 天而非 1 小时**：`expirationSeconds=3607` 是**硬编码魔数**，触发 `--service-account-extend-token-expiration`（**默认 true**）延长到 1 年；同时写 `warnafter`（实测 3607 秒）检测未重载 token 的客户端；**CIS 基准建议关闭该 flag**。`kubectl create token` 仍是严格 3600 秒
10. **加固项 `automountServiceAccountToken: false`**：实测关闭后 `/var/run/secrets` **整个目录不存在**；判断标准是"代码里调不调 k8s API"
11. ⚠️ **清理教训**：`kubectl delete ns` **不会**删除 ClusterRole/ClusterRoleBinding（集群级资源），残留绑定会让将来同名 SA 重新获得全集群权限——**必须单独删**

**镜像踩坑**：`registry.k8s.io/pause` 无 shell；busybox 无 curl 且 wget 不支持 `--ca-certificate` → 用 `kind load docker-image curlimages/curl` 解决。

## ✅ 课 16 完成情况（2026-09-11）

**讲义**：[lesson-16-Pod安全PSA与securityContext.md](lessons/lesson-16-Pod安全PSA与securityContext.md)

**阶段状态**：课 15、16 已完成，下一课为课 17《Secret 加固 · etcd 加密 · 审计》。

**本课核心结论（除标注项外全部本机实测）**：

1. **PSP 已移除**：v1.21 弃用、**v1.25 移除**，实测 `kubectl get psp` 报 `no resource type "psp"`；替代品是 PSA
2. **三档是累积关系**：restricted **继承** baseline 全部要求再叠加四条；不存在"符合 restricted 但不符合 baseline"的 Pod
3. **baseline 挡"碰宿主机"**：实测拦下 privileged / hostPath / hostNetwork / hostPID / add NET_RAW / hostPort 六类，**但裸奔 Pod 仍放行**——**baseline 是地板不是天花板**
4. **restricted 是"全或无"**：逐步加固 p0→p3 **全部被拒**，p4 四件套齐备才通过（不是打分制）
5. **restricted 四件套**：非 root / `allowPrivilegeEscalation: false` / `capabilities.drop: ALL` / `seccompProfile`；`readOnlyRootFilesystem` 是**推荐项非强制项**
6. ⚠️ **Deployment "假成功"陷阱**（本课最实用）：`kubectl apply` 返回 `created` 但 Pod 一个都没有、`READY 0/1`，真相在 `conditions[ReplicaFailure].message`；**CI 里退出码是 0，必须额外查 READY**
7. **改标签只警告不驱逐**：PSA 只在创建时校验，存量不合规 Pod 照常运行
8. **默认容器很"裸"**：`uid=0(root)`、根可写、`CapEff=00000000a80425fb`（**14 项能力**，与官方 baseline 白名单一致）
9. **capabilities 实测**：`drop: ALL` 后 CapEff 归零且 **ping 失效**（permission denied）
10. **`allowPrivilegeEscalation: false` 设 `no_new_privs=1`**（实测 0→1），防 setuid 提权，**与当前是否 root 无关**
11. **特权容器**：`CapEff=000001ffffffffff`、/dev 设备 **182 vs 16**
12. ⚠️ **`runAsNonRoot` 不保证 gid 非 0**：实测只设 `runAsUser` 时 `uid=1000 gid=0(root)`，须显式加 `runAsGroup`
13. **只读根 + emptyDir**：`/` 报 `Read-only file system` 而 `/tmp` 可写——安全与可用性可兼得
14. **镜像供应链**（Code 层）：固定 digest、最小化基础镜像、持续扫描、关键镜像签名

> ⚠️ **一处诚实标注**：尝试用 `crictl inspect` 对比 seccomp 的**行为差异**时，本环境下默认容器与 `RuntimeDefault` 容器**都显示 `profile_type: 1`，无法区分**。本课只实测了"声明差异"，**未实测行为差异**，讲义已如实标注。

## ✅ 课 17 完成情况（2026-09-11，阶段收官）

**讲义**：[lesson-17-Secret加固与etcd加密与审计.md](lessons/lesson-17-Secret加固与etcd加密与审计.md)

**阶段状态**：✅ **阶段 5《安全体系》三课全部完成**（课 15、16、17）。下一阶段为阶段 6《排障 · 运维 · 扩展》课 18《系统化排障：分层定位法》。

**本课核心结论（除标注项外全部本机实测）**：

1. **Secret 是 base64 编码不是加密**：`base64 -d` 一条命令还原明文
2. **etcd 里 Secret 是明文**：etcdctl 直读得到 `k8s` + protobuf，**无 `k8s:enc:` 前缀**
3. **本集群未启用静态加密、也未启用审计**——这两项**默认都是关闭的**
4. **静态加密只防"介质失窃"，不防"权限滥用"**：apiserver 读取时自动解密，有 `get` 权限照样读明文
5. ⚠️ **`identity` 必须放在 providers 最后**：放前面 = 所有数据明文写入，aescbc 形同虚设
6. ⚠️ **开启加密后必须 `replace` 重写存量**，否则老 Secret 仍是明文
7. **KMS v2 是生产推荐**（v1.29 GA；KMS v1 自 v1.28 弃用、v1.29 默认禁用）——密钥在外部 KMS，不与控制面同机
8. **env 注入有三条泄漏路径**：`env`、`/proc/self/environ`、**子进程继承**（实测三处都能拿到明文）
9. **`automountServiceAccountToken: false`** → 容器内 SA token 目录**直接不存在**（默认 token 长 1168 字符）
10. **`defaultMode: 0400`** 实测 `-r--------`（默认 `-rw-r--r--`），须用 `ls -laL` 跟随符号链接
11. ✅ **Secret 卷挂在 tmpfs**（`kubernetes.io~projected`）→ **不落磁盘**（k8s 默认做对的一件事）
12. **`immutable: true`** 拒绝修改，报错 `field is immutable when immutable is set`
13. **审计默认关闭**，且**只配 `--audit-log-path` 不配 `--audit-policy-file` = 不记录任何事件**；Secret 不该用 `RequestResponse`（会把明文写进日志）
14. **威胁模型五条路径**：RBAC 过宽 / 容器内 SA token / env 注入 / etcd 介质 / Git 明文
15. 🎯 **阶段收官洞察——k8s 默认配置"不对称"**：**只有 API 访问（RBAC）默认拒绝，Pod 运行时权限、etcd 加密、审计日志三层都默认放开**

> ⚠️ **三处诚实标注**：
> ① 静态加密**开启后**的效果未实机验证（需重启 apiserver、中断集群，属不可逆环境改动，未获授权未执行；讲义第四幕给了完整步骤）。
> ② Secret 卷挂载"自动更新"**未复现**——实测改完等 **75 秒**容器内仍是旧值（etcd 已更新），**不承诺秒级生效**，生产建议滚动重启。
> ③ etcd 快照取证**失败**（`strings` 搜不到任何 `registry/` 字符串），**未拿它当证据**，改用 etcdctl 直读值证明明文。

## 阶段 5 收官：4C 模型覆盖情况

| 层 | 覆盖内容 | 完成于 |
|---|---|---|
| **Code** | 镜像扫描/签名/SBOM/最小化基础镜像；**Secret 不入 Git**（Sealed Secrets / SOPS / ESO） | 课 16 + 课 17 |
| **Container** | securityContext、capabilities、PSA、**SA token 不挂载** | 课 16 + 课 17 |
| **Cluster** | RBAC、SA、准入；**etcd 静态加密**；**审计日志** | 课 15 + 课 17 |
| **Cloud** | 节点 OS、网络、IAM（本阶段不展开） | — |

## 本阶段产出

- [x] `lessons/lesson-15-RBAC与ServiceAccount.md`（2026-09-11 完成；双视角评审 P0 清零）
- [x] `lessons/lesson-16-Pod安全PSA与securityContext.md`（2026-09-11 完成；双视角评审 P0 清零）
- [x] `lessons/lesson-17-Secret加固与etcd加密与审计.md`（2026-09-11 完成；双视角评审 P0 清零）
- [x] `lessons/lesson-17-Secret加固与etcd加密与审计.md`（2026-09-11 完成；双视角评审 P0 清零）

### 课级入口要素补齐（2026-09-15）

按 topic-teach 最新 skill 的「课级入口要素」硬约束，本阶段课 15-17已全部补齐六项要素（一句话本质 / 处境对照 / 一眼全局图 + 读图指引 / 本课地图 / 📖 文档核对 / 🧭 知识点衔接句），经 `verify.sh` 全量核验 P0=0。

**本阶段新增全局图**：无（课 15-17 已有全局图，本轮补本质 + 处境对照 + 地图 + 衔接句，并补了课 15 缺失的读图指引）

**真实性纪律**：处境对照一律不给编造数字，全部为机制层面对照，无把握处标 ⏳；📖 留痕仅在确认真实引用官方文档后补写。
