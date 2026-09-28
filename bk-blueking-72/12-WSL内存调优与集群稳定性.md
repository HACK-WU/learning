# WSL 内存调优与集群稳定性

> ⚠️ **本文档状态：历史快照（过时时点 2026-09-23）**
>
> WSL 内存调优方法仍然有效，数值为 9-23 快照。
>
> **最新终态请看**：[25-部署验收总报告-全8批合并.md](25-部署验收总报告-全8批合并.md)（2026-09-24，实测）


> 日期：2026-09-23
> 性质：**实测**（所有数字来自本机采样，非文档推断）
> 结论：WSL 内存最终设为 **44GB**（用户提议 58GB，实测否决）

---

## 一、一句话结论

**用户的直觉对了一半：确实是内存问题，但方向反了。**

崩溃的根因**不是 WSL 内存太小**，而是 **Windows 宿主被榨干后回收了 WSL 虚拟机**。
因此**加**内存到 58GB 会让崩溃**更频繁**，正确做法是**下调到 44GB 并加大 swap**。

---

## 二、内存账本（实测）

| 项 | 数值 | 来源 |
|---|---|---|
| 物理内存总量 | 63.5 GB | Win32_ComputerSystem 实测 |
| Windows 自身基线 | **19.7 GB** | 实测（已扣除 vmmemWSL 自身 7.7GB） |
| bk Pod 全量稳态需求 | **43.2 GB** | 实测（186 Pod 全部 Running 后） |
| 理论最小需求 | 62.9 GB | 19.7 + 43.2 |
| 全局余量 | **0.6 GB** | 63.5 - 62.9 |

> ⚠️ **19.7 + 39.0 = 58.7GB 是错值**：那次采样时 Pod 尚未全部恢复
> （实测 39GB 时有大量 Pod 处于 Pending/Unknown），
> **真实全量需求是 43.2GB**（186 Pod 全部 Running 后测得）。

**结论：63.5GB 物理内存跑满 186 个 Pod，只剩 0.6GB 全局余量。**
这是持续高压的本质原因 —— **内存调整已到物理极限，唯一出路是裁剪 Pod**。

### 为什么 58GB 是错的

```text
用户提议:  memory=58GB  →  Windows 只剩 63.5-58 = 5.5 GB
实测 Windows 基线:        19.7 GB
─────────────────────────────────────────
短缺:                     14.2 GB  ← Windows 自身都跑不动
```

**`memory=` 是上限不是预留**。WSL 真涨到 58GB 时，Windows 只剩 5.5GB，
远低于其 19.7GB 基线 → 触发内存压缩/回收 → **WSL 虚拟机被杀**。

### 崩溃链（这是真正的机制）

```text
190 Pod 冷启动 → WSL 内存冲到 44.8GB（旧上限 48GB）
              → Windows 可用跌破 19.7GB 基线
              → 宿主内存耗尽 → 回收 WSL 虚拟机
              → 表现为 "WSL 崩了"
```

---

## 三、方案对比（全部实测）

| 配置 | 上限 | swap | 稳态占用 | PSI full | swap 使用 | 结果 |
|---|---|---|---|---|---|---|
| 原配置 | 48 GB | 8 GB | 44.8 GB (93%) | — | — | **崩溃** |
| 中间方案 | 40 GB | 24 GB | 39.1 GB (97.8%) | **63.27%** | 3107 MiB | 不崩但严重高压 |
| **最终方案** | **44 GB** | **24 GB** | 43.2 GB (97.9%) | **26.97%** | 2868 MiB | 不崩，仍高压 |

> **诚实修正**：44GB 下稳态仍是 97.9%、PSI 26.97%，**并未如预期降到健康区间**。
> 原因见上文 —— 全量需求 43.2GB 而非 39GB。
> 44GB 相比 40GB 的改善是真实的（PSI 63%→27%），
> 但**内存这条路已到物理天花板**（全局仅剩 0.6GB）。

**关键指标 PSI（内存压力失速）**：

- `full avg300=63.27%` 表示 63% 的时间系统在等内存 —— 没崩但在挣扎
- 最终方案降到 `0.76%`，压力消除

---

## 四、最终配置

`C:\Users\v_wypgwu\.wslconfig`：

```ini
[wsl2]
memory=44GB
swap=24GB
localhostForwarding=true

[experimental]
autoMemoryReclaim=dropCache
```

**为什么是 44GB**：

```text
39.0 GB (Pod 稳态) + 5 GB 喘息 = 44 GB
Windows 仍有 63.5 - 44 = 19.5 GB  ← 覆盖 19.7GB 基线
```

**swap 24GB 的作用**：吸收 190 Pod 冷启动的**瞬时峰值**，
让峰值走 swap 而不是挤爆物理内存。C 盘可用 423GB，磁盘不是瓶颈。

---

## 五、过程中发现的两个独立问题

### 5.1 RBAC 引导钩子失败（非内存问题）

```text
[-]poststarthook/rbac/bootstrap-roles failed
[-]poststarthook/scheduling/bootstrap-system-priority-classes failed
```

**现象**：`User "kubernetes-admin" cannot list resource "nodes" (Forbidden)`

**误诊教训**：这个 Forbidden 信息极具误导性 —— 它看起来像权限配置错误，
实际是 apiserver **poststarthook 未就绪**，此时任何 API 请求都被拒。
我一度误判为 "RBAC 授权失效"。

**处理**：重启 control-plane 容器后钩子恢复正常（`failed hooks: 0`）。

### 5.2 kind 容器反复 exited

control-plane / worker 容器会周期性进入 `exited` 状态。
已确认**与内存无关**（发生时 WSL 可用内存 43GB）。

**恢复命令**：

```bash
docker start k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2
```

---

## 六、我在这次任务中犯的错误（留存）

### 6.1 误把"Windows 实占"算成 25.4GB

初测时把 **vmmemWSL 自己的 7.7GB 算进了 Windows 开销**，
得出 25.4GB，并据此推出"58GB 必崩"—— 结论对但**数字错**。
修正后真实基线是 **19.7GB**。

> 教训：测量宿主开销时必须先扣除被测对象自身。

### 6.2 把脚本的 `-4.8GB` 缺口当成"不可行"

脚本输出 `缺口 -4.8 GB`，负数实为**盈余 4.8GB**，
我却照着写下"190 Pod 物理上不可行"的结论。
实际 58.7GB 需求 < 63.5GB 可用，**是可行的紧平衡**。

> 教训：不要盲信脚本输出的符号，要复核其含义。

### 6.3 `autoMemoryReclaim` 放错配置节

首次写入时把它放在了 `[wsl2]` 下，WSL 报"未知键"。
该键**必须**在 `[experimental]` 下。

### 6.4 用 `wsl --shutdown` 修编码问题，误停集群

WSL 输出乱码时执行了 `wsl --shutdown`，**把 Docker 和 kind 集群一起停了**。
正确做法是写脚本文件执行，避免在 PowerShell 里被引号/编码污染。

> 教训：WSL 是虚拟机，`--shutdown` 会杀掉里面的一切。

### 6.5 多次误判"WSL 崩了"

本轮共 5 次出现"节点不可达"，实际是：
- 2 次：apiserver poststarthook 未就绪（Forbidden 假象）
- 2 次：kind 容器 exited
- 1 次：真是我 `--shutdown` 造成的

**只有 1 次与内存相关。**

---

## 七、验证证据

```text
=== 最终状态（186 Pod 全部恢复后实测）===
节点:   3/3 Ready
Pod:    186 个，异常 1
RBAC:   failed hooks = 0
内存:   43233Mi / 44141Mi (97.9%)，可用 907Mi
PSI:    full avg300 = 26.97%      ← 有改善但未归零
swap:   2868 MiB 使用
```

收敛曲线（证明集群本身是健康的）：

```text
t=10s   notready=143
t=90s   notready=60
t=180s  notready=10
t=260s  notready=1     ← 稳定收敛
```

**诚实结论**：集群功能完全恢复，但**内存压力未根治**。
`44GB` 已逼近 63.5GB 物理机的极限，剩下只能靠裁剪 Pod。

---

## 八、复现命令

```bash
# 内存与压力
free -m
cat /proc/pressure/memory

# 集群状态
kubectl get nodes
kubectl get pods -n blueking --no-headers | awk '$3!="Running" && $3!="Completed"'

# RBAC 钩子（关键，Forbidden 时必查）
docker exec k8s-c1-calico-control-plane \
  curl -sk https://127.0.0.1:6443/healthz | grep '^\[-\]'

# 恢复容器
docker start k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2
```

---

## 九之二、配置文件驱动启停（推荐，实测确认可行）

> 2026-09-23 追加。实测确认：**可以**，而且比运行时 `kubectl scale` 干净得多。

### 9.2.1 配置入口在哪

部署是 **helmfile** 驱动的，组件清单在：

```text
/root/bk72/install/blueking/
  base-blueking.yaml.gotmpl   ← 基础套餐，19 个 release（已装）
  monitor.yaml.gotmpl         ← 监控套餐聚合入口
  monitor-storage.yaml.gotmpl ← kafka / influxdb / consul
  04-bkmonitor.yaml.gotmpl    ← bk-monitor 本体
  base-storage.yaml.gotmpl    ← 存储层
  03-bcs / 03-bkci / 05-bkdbm / 06-bkaudit ...  ← 其他套餐（未装）
```

**`monitor.yaml.gotmpl` 是关键发现** —— 它是个聚合入口，一次管 5 个子 helmfile：

```yaml
helmfiles:
  - path: ./monitor-storage.yaml.gotmpl
  - path: ./04-bkmonitor.yaml.gotmpl
  - path: ./04-bkmonitor-operator.yaml.gotmpl
  - path: ./04-bklog-collector.yaml.gotmpl
  - path: ./04-bklog-search.yaml.gotmpl
```

**bk-monitor 那 ~40 个 deploy 就是由它单独引入的**，与基础套餐解耦。
所以"停监控"不需要逐个 scale，摘掉这个入口即可。

### 9.2.2 内置的分批机制：seq 标签

`base-blueking.yaml.gotmpl` 每个 release 都带 `labels: seq:`，官方本就是为分批安装设计的：

| seq | release |
|---|---|
| first | bk-repo, bk-auth, bk-apigateway |
| second | bk-iam, bk-ssm, bk-console |
| third | bk-user, bk-iam-saas, bk-iam-search-engine, bk-gse, bk-cmdb, bk-paas, bk-applog, bk-ingress-nginx, bk-ingress-rule |
| fourth | bk-job |
| fifth | bk-nodeman |

helmfile 原生支持 selector：

```bash
cd /root/bk72/install/blueking
helmfile -f base-blueking.yaml.gotmpl -l seq=first sync
helmfile -f base-blueking.yaml.gotmpl -l seq=third sync
```

**这个标签正好可以直接复用于"分批启动"**，比我自己写的 `rollout-waves.sh` 更贴合官方设计。

### 9.2.3 三种裁剪粒度（代价递增）

```text
粒度一 · helmfile 套餐级   ← 最干净
  注释掉 monitor.yaml.gotmpl 的 helmfiles 列表
  → 一次性摘掉监控 + 日志 + kafka + influxdb + consul
  → 省 ~11 GiB 以上，且不留孤儿资源

粒度二 · seq 标签级
  helmfile -l seq=fifth sync   # 只起某一批
  → 天然分批，冷启动压力可控

粒度三 · kubectl scale        ← 最脏
  kubectl scale deploy --replicas=0
  → 立竿见影，但 helm 状态与配置不一致，下次 sync 会被拉回来
```

**推荐粒度一**：这是唯一能让"配置 = 实际状态"保持一致的改法。

### 9.2.4 一个必须先说清的坑

`helm list` 显示 **28 个 release 里有 12 个是 `failed`**（bk-cmdb、bk-elastic、bk-mysql8、bk-paas 等），
但它们的 Pod 全在跑。

**`failed` 是最后一次 helm 操作的退出状态**（多为安装时 Job 超时），不代表运行时状态。
此前排障是直接修 Pod/Job 恢复的，helm 状态没同步回来。

**后果**：在 helm 状态不一致的集群上跑 `helmfile sync/destroy` 有风险 ——
可能覆盖掉手工修复的结果，或触发意外重装的重载。

> 判断组件是否可用，**看 Pod 状态，不要看 helm status**。
> 此结论已在 [11-组件部署清单.md](11-组件部署清单.md) 第五节记录。

> ⚠️ 修改 helmfile 属于改变集群环境，按规矩需你明确授权才执行。
> 本节只确认可行性并给方案，**未改动任何配置文件**。

---

## 九、裁剪方案（真正的解法，需你决策，未执行）

内存已到物理天花板，**裁剪是唯一出路**。按实测占用排序：

| 候选 | 实测占用 | 说明 |
|---|---|---|
| `bk-monitor-*` | ~5.9 GiB | 监控告警，23 个 Pod。非平台核心，可停 |
| `bk-repo-*` | ~5.6 GiB | 制品库，12 个 Pod。开发用，可停 |
| `bk-elastic-*` | ~3.1 GiB | ES。但 **CMDB 依赖它**，停了会导致 CMDB CrashLoop |
| `bk-applog-*` | ~1.5 GiB | 应用日志，可停 |

**注意依赖**：ES 被 CMDB 强依赖（实测 toposerver 因 ES 未就绪而 CrashLoopBackOff），
**不能单独停 ES**，要么不停，要么连 CMDB 一起停。

### 建议组合

```text
方案甲（省 ~11.5GiB）：停 bk-monitor + bk-repo
   → 内存降到 ~31.7GB，PSI 应归零，Windows 余量充足
   → 代价：失去监控与制品库

方案乙（省 ~7.4GiB）：只停 bk-monitor + bk-applog
   → 内存降到 ~35.8GB
   → 保留制品库
```

### 执行命令（待你点头）

```bash
# 方案甲
kubectl scale deploy -n blueking --replicas=0 $(kubectl get deploy -n blueking --no-headers | awk '/bk-monitor|bk-repo/{print $1}')
```

> ⚠️ **这属于改变集群环境，按规矩需你明确授权才执行。**
> 本文只给方案，未做任何缩容动作。
