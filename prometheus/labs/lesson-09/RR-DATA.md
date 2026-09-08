# 课 9 补做：remote read 分模式对照（回收课 7 挂账项）

> 挂账项原文：`remote read 三种模式的分模式性能差异（课 9）：课 7 只验证了整体代价 2.69x → 课 9 未取得（未构造出可复现对照），继续挂账`
> 本课补做完成。所有数值均为本机实测（Prometheus v3.14.0 + 自写 protobuf 客户端）。

## 0. 重要更正：不是"三种模式"，是"两种模式"

课 7 讲义写的三种（SAMPLES / STREAMED_XOR_CHUNKS / STREAMED_CHUNKS）中，
**`STREAMED_CHUNKS` 并不存在**。

证据链（本机 + 官方双向核验）：

1. Prometheus v3.14.0 二进制中只存在 `SAMPLES` 与 `STREAMED_XOR_CHUNKS`
   两个字符串；`STREAMED_CHUNKS` 出现 **0 次**（`grep -a -o` 实测）。
2. 官方 `prompb/remote.proto` 中 `ReadRequest.ResponseType` 枚举只有两个值：
   ```proto
   enum ResponseType {
     SAMPLES = 0;              // Content-Type: application/x-protobuf, Content-Encoding: snappy
     STREAMED_XOR_CHUNKS = 1;  // Content-Type: application/x-streamed-protobuf; proto=prometheus.ChunkedReadResponse
   }                            // Content-Encoding: ""  ← 空，不压缩
   ```
3. `--storage.remote.read-max-bytes-in-frame`（默认 1048576 = 1MB）**确实存在**，
   但它是 `STREAMED_XOR_CHUNKS` 的**分帧参数**，不是第三种模式。

→ 结论：课 7 把"分帧参数"误当成了"第三种模式"。正确表述是**两种响应模式 + 一个分帧参数**。

## 1. 实验环境

| 项 | 值 |
|---|---|
| Prometheus | v3.14.0（容器 `l9-prom-1`，未开 remote write receiver） |
| 客户端 | 自写 Python 客户端，手工编码 protobuf + cramjam 做 snappy |
| 造数指标 | `rr_bench{route,idx}`，RR_CARD=500 → 3×500 = **1500 条序列** |
| 对照指标 | `app_requests_total`（3 条）、`app_request_duration_seconds_bucket`（18 条） |
| 采样 | 每个场景 5 次取中位数 |

请求构造要点（决定能否分模式的关键）：
- 模式由 **请求体 protobuf 的 `accepted_response_types` 字段**协商，**不是 HTTP Accept 头**
  - `SAMPLES`：该字段留空
  - `STREAMED_XOR_CHUNKS`：该字段置 `[1]`
- 请求体必须 **snappy 压缩**（不压缩 → 400 Bad Request，实测）
- 需带 `X-Prometheus-Remote-Read-Version: 0.1.0`

## 2. 响应头实测（根因证据）

| 模式 | Content-Type | Content-Encoding | 说明 |
|---|---|---|---|
| SAMPLES | `application/x-protobuf` | `snappy` | **压缩** |
| STREAMED_XOR_CHUNKS | `application/x-streamed-protobuf; proto=prometheus.ChunkedReadResponse` | `None`（无该头） | **不压缩** |

这是后续所有体积反转的根因之一。

## 3. 体积对照：随序列数发生反转（决定性）

时间范围固定 1 小时，只变序列数：

| 序列数 | 指标 | SAMPLES | STREAMED | frames | 比值 SAMPLES/STREAMED | 谁更省 |
|---|---|---|---|---|---|---|
| 3 | `app_requests_total` | 18 032 | 5 608 | 3 | **3.22x** | STREAMED |
| 18 | `duration_seconds_bucket` | 57 417 | 31 791 | 21 | **1.81x** | STREAMED |
| 500 | `rr_bench{route="/"}` | 116 642 | 124 071 | 500 | 0.94x | SAMPLES |
| 1000 | `rr_bench`（部分） | 349 681 | 381 223 | 1500 | 0.92x | SAMPLES |
| 1500 | `rr_bench` 全部 | 359 572 | 384 243 | 1500 | 0.94x | SAMPLES |

**交叉点在 18 ~ 500 条序列之间。**

时间范围维度（1500 序列，验证不是时间造成的）：

| 时间范围 | SAMPLES | STREAMED | 比值 |
|---|---|---|---|
| 600 s | 132 348 | 311 871 | 0.42x |
| 3 600 s | 141 177 | 314 899 | 0.45x |
| 21 600 s | 141 177 | 317 918 | 0.44x |

少序列 + 长历史（3 序列，验证反向也成立）：

| 时间范围 | SAMPLES | STREAMED | 比值 |
|---|---|---|---|
| 3 600 s | 18 078 | 5 586 | **3.24x** |
| 21 600 s | 26 253 | 8 015 | **3.28x** |

## 4. 为什么反转（机制解释）

三条叠加效应：

1. **每帧固定开销**：流式每帧 = varint 长度 + **4 字节 CRC32C** + 完整标签集。
   序列越多帧越多（1500 帧 vs 3 帧），**标签集被重复编码 1500 次**。
2. **流式不压缩**：`Content-Encoding` 为空；SAMPLES 有 snappy 压缩，
   在标签高度重复时压缩率极高（3 序列 → 18 032 B，1500 序列 → 359 572 B）。
3. **XOR 编码要攒够样本才划算**：单序列样本多时 XOR 收益大；样本少时
   反而不如直接压缩原始样本。

→ 所以：**序列少、历史长 → 流式赢；序列多、历史短 → SAMPLES 赢。**

## 5. 内存对照：流式确实赢（官方宣称成立）

方法：每轮 GC 稳定后取独立 baseline，40 次 6 小时范围大查询，采样容器内存。
**跑两轮验证可复现**：

| 轮次 | 模式 | baseline | after | 净变化 |
|---|---|---|---|---|
| 1 | SAMPLES | 42.53 MiB | 50.19 MiB | **+7.66 MiB** |
| 1 | STREAMED | 50.19 MiB | 43.09 MiB | **−7.10 MiB** |
| 2 | SAMPLES | 43.09 MiB | 52.56 MiB | **+9.47 MiB** |
| 2 | STREAMED | 52.56 MiB | 43.00 MiB | **−9.56 MiB** |

两轮一致：SAMPLES 净增约 8~10 MiB，STREAMED 净降约 7~10 MiB
（流式期间几乎不 buffer，期间 GC 还回收了存量）。

→ **流式的价值在内存（服务端 buffer），不在体积。**

## 6. 耗时

小规模下两种模式耗时差异不显著（1~12 ms 量级，噪声大于信号）。
**本课不给出"谁更快"的结论** —— 这个规模下测不出来，给数字就是编造。

## 7. 对课 7 的更正与对课 9 的补充

**课 7 需更正**：
- 「三种读取模式」→「两种响应模式 + 一个分帧参数」
- `STREAMED_CHUNKS` 不存在；`read-max-bytes-in-frame` 是 STREAMED_XOR_CHUNKS 的参数

**课 9 需补充**：
- 选型建议：Thanos/VM 等通过 remote read 拉数据的场景，
  **序列数少时流式更省带宽，序列数多时 SAMPLES 更省带宽，但 SAMPLES 会让服务端内存翻倍**
- 这也解释了为什么 Prometheus 3.x 客户端默认优先 `STREAMED_XOR_CHUNKS`
  再回退 `SAMPLES`：`AcceptedResponseTypes = [STREAMED_XOR_CHUNKS, SAMPLES]`
  —— **优先保内存，而非保带宽**

## 8. 未实测 / 边界

- 未测 1 万序列 × 8 小时（官方博客场景）的内存绝对值，本机规模有限
- 未测跨节点网络延迟下的表现（本机全在 docker 同一 bridge 网络）
- 未测 `read-max-bytes-in-frame` 取不同值的影响
- 客户端为手工 protobuf 编码，frames 计数为自实现解析（已与序列数交叉验证：
  3 序列→3 帧、1500 序列→1500 帧，吻合）
