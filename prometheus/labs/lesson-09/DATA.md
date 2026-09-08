# 课 9 数据底稿（本机实测，2026-09-07）

> 所有数字均来自本机 Docker 实测。凡未实测的，标注【未实测】。
> 环境：Windows WSL2 + Docker 29.4.1，20 核 / 31GB 内存 / 788G 可用磁盘

## 0. 版本事实核查（阶段要求：时效敏感须过闸门）

| 项目 | 核查到的最新版 | 发布/生效时间 | 来源 |
|------|---------------|--------------|------|
| Thanos | **v0.42.4** | 2026-07-30 | [Thanos changelog](https://thanos.io/v0.25/thanos/changelog.md/)、SourceForge 镜像文件列表 |
| Grafana Mimir | **3.2.0** | 2026-08-19（VERSION bump） | [grafana/mimir](https://github.com/grafana/mimir) 仓库 VERSION 文件 |
| VictoriaMetrics | v1.151.0 | 本机已有镜像 | docker images |
| Prometheus | v3.14.0 | 本机已有镜像 | docker images |

**核查结论**：Mimir 已进入 3.x 主干（3.0 → 3.1.5 → 3.2.0），Thanos 仍在 0.x（v0.42.4）。
两者版本号风格不同，**不能用版本号大小比较成熟度**。

## 1. Thanos 实测（v0.42.4）

### 1.1 部署踩坑（实测，均为版本漂移）

| 写法 | 结果 | 实测报错 |
|------|------|---------|
| `s3forcepathstyle: true` | ✗ 启动失败 | `field s3forcepathstyle not found in type s3.Config` |
| `force_s3_path_style: true` | ✗ 启动失败 | `field force_s3_path_style not found in type s3.Config` |
| **`bucket_lookup_type: path`** | ✓ 正常启动 | — |

判定手法：起真实 store 组件看是否 `not found in type`。
**注**：`thanos tools bucket list` 子命令名不对时会报同一个错，**不可用它判定字段**（会误判为全 ACCEPTED）。

```bash
# 错误示范（会掩盖真实结果）：
docker run --rm $IMG tools bucket list --objstore.config-file=... 2>&1 | head -3
# 输出: thanos: error: expected command but got "list"   <- 与字段无关！

# 正确判定：
timeout 12 /bin/thanos store --objstore.config-file=... 2>&1 | head -20
```

| 参数 | 结果 |
|------|------|
| `--store=rpc:10901` | ✗ `unknown long flag '--store'`（v0.42 已移除） |
| `--endpoint=...` | 可用但标记 **Deprecated** |
| **`--store.sd-files=<file>`** | ✓ 官方推荐（服务发现方式） |

`--endpoint` 帮助文本原文：
```
--endpoint=<endpoint> ...  (Deprecated): Addresses of statically
                           configured Thanos API servers (repeatable).
```

`--store.sd-files` 需要的 YAML 格式（实测有效）：
```yaml
- targets:
  - l9-thanos-sc-1:19090
  - l9-thanos-sc-2:19090
  - l9-thanos-store:19090
```

### 1.2 Store 发现延迟（实测）

启动后 `/api/v1/stores` 返回 `{"status":"success","data":{}}`（空），
**35 秒后**才出现 3 个 store。日志：
```
02:30:42 initial endpoint discovery completed, marking gRPC as ready
02:31:17 adding new sidecar ... address=l9-thanos-sc-1:19090 extLset="{cluster=\"prod-shanghai\", replica=\"p1\"}"
02:31:17 adding new sidecar ... address=l9-thanos-sc-2:19090 extLset="{cluster=\"prod-shanghai\", replica=\"p2\"}"
02:31:17 adding new store  ... address=l9-thanos-store:19090 extLset=
```
**空结果 ≠ 配置错误**，需等待发现周期。

### 1.3 HA 去重决定性对照（回收课 8 挂账项）

两个 Prometheus 副本：`cluster=prod-shanghai` 相同，`replica=p1/p2` 不同。
Q1 = 设 `--query.replica-label=replica`；Q2 = 不设。

| 查询 | Q1（去重开） | Q2（去重关） | 差异 |
|------|-------------|-------------|------|
| `app_requests_total{route="/"}` 明细 | **1 条**，replica 已剥离，value=917 | **2 条**，p1=929 / p2=917 | 2 倍 |
| `count(app_requests_total{route="/"})` | **1** | **2** | 2 倍 |
| `sum(app_requests_total)` | **62162** | **124347** | ≈2 倍 |
| `sum by (route)` route="/" | **959** | **1888** | ≈2 倍 |
| range 查询（5min/step15s） | **3 序列 / 63 点** | **6 序列 / 126 点** | 精确 2 倍 |

**penalty 去重算法选值**：两副本 p1=929、p2=917，去重后取 **917**（p2）。

**与课 8 的关键差异**：课 8 中 Prometheus 自己不去重，需手写 `max/avg without(replica)`；
Thanos 在**查询层自动完成**，配一个 flag 即可。

### 1.4 Thanos 组件资源占用（实测单次采样）

```
l9-thanos-query   CPU=0.21%  MEM=15.04MiB
l9-thanos-store   CPU=0.04%  MEM=13.11MiB
l9-thanos-sc-1    CPU=0.04%  MEM=16.5MiB
```

### 1.5 组件构成（本实验）

Prometheus×2 + sidecar×2 + store-gateway×1 + query×2（含 1 个对照）= 7 容器。
**未部署 compactor**：compactor 每 bucket 必须单例，多实例会损坏 block（【未实测，官方文档结论】）。

## 2. Mimir 实测（3.2.0，单体模式 `-target=all`）

### 2.1 部署踩坑（实测）

| 写法 | 结果 | 实测报错 |
|------|------|---------|
| `s3.force_path_style: true` | ✗ | `field force_path_style not found in type s3.Config` |
| `compactor.sharding_ring.replication_factor` | ✗ | `field replication_factor not found in type compactor.RingConfig` |

**Mimir 的 `blocks-storage.s3` 只有 10 个字段**（实测 `-help`）：
```
access-key-id / bucket-name / endpoint / region / secret-access-key /
session-token / sse.kms-encryption-context / sse.kms-key-id / sse.type / sts-endpoint
```
**没有任何 path style 选项** —— 与 Thanos 不同，Mimir 对 MinIO 这类 S3 兼容存储自动处理。

### 2.2 镜像差异（实测）

Mimir 3.x 只提供 **distroless 镜像**，容器内**没有 `sh`/`bash`**：
```
docker run --rm --entrypoint sh grafana/mimir:3.2.0 -c '...'
→ exec: "sh": executable file not found in $PATH
```
排查只能靠日志与 HTTP 接口，不能 `docker exec` 进去。
（与 Mimir 2.16 release notes 中「仅提供 distroless 镜像」一致）

### 2.3 多租户隔离决定性对照

两个 Prometheus 分别以 `X-Scope-OrgID: tenantA/tenantB` remote write 到同一 Mimir，
数据带 `tenant` external label 区分。

| 验证项 | 结果 |
|--------|------|
| 无租户头写入 `/api/v1/push` | **401** |
| 有租户头写入（空 body） | **400**（走到参数校验，说明鉴权已过） |
| 无租户头查询 | **401** |
| tenantA 查 `app_requests_total{route="/"}` | 1 条，**tenant=tenantA**，value=5374 |
| tenantB 查 `app_requests_total{route="/"}` | 1 条，**tenant=tenantB**，value=5354 |
| **tenantA 查 `tenant="tenantB"`** | **0 条**（跨租户不可见） |
| **tenantB 查 `tenant="tenantA"`** | **0 条** |
| 不存在的租户 tenantZZZ | 0 条，**不报错** |
| 各租户 `count(app_requests_total)` | 各 3 条 |

**对照 Thanos**：同一查询 `count(app_requests_total)` 返回 3 条，**不区分租户**（无租户概念）。

### 2.4 资源占用

```
l9-mimir  CPU=0.43%  MEM=72.68MiB   <- 单体模式，内含全部微服务
```

启动耗时：**8 秒 ready**。

## 3. VictoriaMetrics 实测（v1.151.0）

### 3.1 单节点 vs 集群的 API 路径差异（实测，重要坑）

| 路径 | 单节点 (:8428) | 集群 vmselect (:8481) |
|------|---------------|---------------------|
| `/prometheus/api/v1/query` | ✓ 200 | ✗ **400** |
| `/api/v1/query` | ✓ 200 | ✗ **400** |
| **`/select/0/prometheus/api/v1/query`** | — | ✓ **200** |

vmselect 日志原文：
```
unsupported URL format for path "/prometheus/api/v1/query".
Make sure you're using cluster URL format
```

**单节点 → 集群迁移时，所有查询 URL 必须加 `/select/<tenantID>/` 前缀。**

### 3.2 写入端点

| 端点 | 空 payload 响应 |
|------|----------------|
| 单节点 `/api/v1/write` | **204** |
| 集群 vminsert `/insert/0/prometheus/api/v1/write` | 使用标准路径 |

写入计数器：`vm_rows_inserted_total{type="promremotewrite"} 754`

### 3.3 数据可见性延迟（实测）

remote write 完成后立即查 `count(app_requests_total)` 返回**空**，
但 `__name__` 列表里**已有** `app_requests_total`。
约 20~30 秒后查询正常返回 3 条。
**"查不到" ≠ "没写入"**，应查 `vm_rows_inserted_total` 计数器确认。

### 3.4 去重行为

单节点配 `-dedup.minScrapeInterval=5s`：
`count(app_requests_total{route="/"})` = **1**
`sum(app_requests_total)` = **61552**（与 Thanos Q1 的 62162 量级一致，非 2 倍）

**与课 8 一致**：VM 的 dedup 在标签完全相同时介入。

### 3.5 资源占用

```
l9-vm-single  CPU=0.24%  MEM=93.07MiB
l9-vmstorage  CPU=0.09%  MEM=10.85MiB
l9-vmselect   CPU=0.04%  MEM=7.699MiB
```
集群三组件合计约 **21.6MiB**，远低于单节点 93MiB（但集群版未灌满数据，**不可直接比大小**）。

## 4. 三方横向对比（同一份数据，实测）

| 维度 | Thanos v0.42.4 | Mimir 3.2.0 | VictoriaMetrics v1.151.0 |
|------|---------------|-------------|-------------------------|
| 部署形态 | 多组件（sidecar/store/query/compact） | 单体 1 进程 或 微服务 | 单节点 1 进程 或 3 组件集群 |
| 本实验容器数 | 7（含 1 对照） | **1** | 1（单）/ 3（集群） |
| 写入方式 | sidecar 传 block（Receive 才收 remote write） | `/api/v1/push` + 租户头 | `/api/v1/write` |
| 多租户 | ✗ 无 | ✓ `X-Scope-OrgID`，实测隔离 | 集群版 `/select/<id>/` 路径隔离 |
| HA 去重位置 | **查询层**（`--query.replica-label`） | HA tracker + 外部标签 | 写入/查询时 `dedup.minScrapeInterval` |
| 去重是否自动 | ✓ 配 flag 即自动 | 需 HA tracker 配置 | ✓ 配 flag 即自动 |
| 对象存储依赖 | ✓ 必需 | ✓ 必需 | 可选（本地磁盘即可） |
| 启动耗时 | 发现 store 约 35s | **8s ready** | ~10s |
| 内存（本实验） | query 15MiB / store 13MiB / sidecar 16.5MiB | **72.68MiB**（全组件） | 单节点 93MiB；集群 3 组件 21.6MiB |
| 容器内 shell | 有 | **无（distroless）** | 有 |

## 5. OTLP receiver 事实核查（Prometheus v3.14.0）

### 5.1 flag 存在性（实测 `--help`）

```
--[no-]web.enable-otlp-receiver    Enable API endpoint accepting OTLP write ...
```
**feature 列表里没有** `otlp-write-receiver`（该 2.x 写法已移除）。
可用的 feature：`otlp-deltatocumulative`、`otlp-native-delta-ingestion`。

**结论**：网上大量教程仍在用 `--enable-feature=otlp-write-receiver`，
在 3.x 上是**错的**；正确写法是 `--web.enable-otlp-receiver`。

### 5.2 端点路径（实测 POST）

| 路径 | 响应 |
|------|------|
| `/api/v1/otlp/v1/metrics` | ✓ **200** |
| `/api/v1/otlp`（短路径，教程常用） | ✗ **404** |

### 5.3 实测写入

POST 一个 OTLP JSON（`test.metric.total`，点号命名）→ 返回 200。
随后 `/api/v1/label/__name__/values` 返回 **`["test_metric_total_ratio"]`**。

**点号命名被自动转换为下划线**，并附加 `_ratio` 后缀（gauge 类型）。

`/api/v1/features` 返回：
```json
{"api": {..., "otlp_write_receiver": true, ...},
 "otlp_receiver": {"delta_conversion": false, "native_delta_ingestion": false}}
```
注意：feature 名仍是 `otlp_write_receiver`，但**启用方式是 `--web.enable-otlp-receiver`**，
两者命名不一致，是容易混淆的点。

## 6. 本轮"0 条/空结果"核查记录（共 5 次）

| # | 现象 | 查证结论 | 教训 |
|---|------|---------|------|
| 1 | Thanos `/api/v1/stores` 空 | store 发现需 **35s** | 空 ≠ 配置错误，要等发现周期 |
| 2 | Thanos 查 `app_requests_total` 0 条 | `up=0`，**app 容器没起来** | 先查 `up` 指标确认数据源活着 |
| 3 | VM 查 `count(...)` 空 | 数据已写入（754 行），**查询可见性延迟** ~30s | 查 `vm_rows_inserted_total` 计数器 |
| 4 | OTLP 查 `__name__` 空 | 端点路径应为 `/api/v1/otlp/v1/metrics`，短路径 404 | 验证端点时直接 POST 看响应码 |
| 5 | `tools bucket list` 全 ACCEPTED | 子命令名错误，报错与字段无关 | **工具报错可能掩盖真实校验** |

## 7. 挂账项处理情况

| 挂账项 | 来源 | 本课处理 |
|--------|------|---------|
| `replica` 思想在 Thanos 中的演进 | 课 8 | ✓ 已回收（1.3 节决定性对照） |
| remote read 三种模式分模式性能差异 | 课 7 | ⚠️ **部分**：环境已建（l9-prom-rr + l9-prom-wr），但只验证了数据可达性，**未测出分模式差异**（见 7.1） |
| 联邦在大规模序列数下的表现 | 课 8 | ⚠️ **未实测**（本例仅几百条序列，规模不足以暴露瓶颈） |
| Thanos/Mimir 远端侧背压机制 | 课 7 | ⚠️ **未实测**（需模拟后端故障与队列打满） |
| gossip 建立耗时在生产环境的数值 | 课 8 | → 顺延阶段 4 课 11 |

### 7.1 remote read 挂账项说明

已建好环境：
- `l9-prom-wr`：抓 app 并 remote write 到 VM 单节点（754 行已写入）
- `l9-prom-rr`：配置 `remote_read` 指向 VM

**未取得分模式性能数据的原因**：remote read 的三种模式由客户端与服务端的
协议协商（Accept 头 / `StreamedChunkedReadResponses`）自动决定，
本机环境难以强制指定某一种模式做对照，**未构造出可复现的分模式对照**。
本课**不编造数字**，标注为未实测，顺延。
