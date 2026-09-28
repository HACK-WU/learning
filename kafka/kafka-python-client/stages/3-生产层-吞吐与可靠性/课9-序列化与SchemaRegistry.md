# 课 9 · 序列化与 Schema Registry

> 一句话：**序列化决定消息多大，Schema Registry 决定 schema 能不能安全地变**——前者是钱（磁盘+带宽），后者是命（演进不炸）。

## 你将学到什么

- Avro / JSON / Protobuf 的**体积与速度实测对照**（不是网上抄的数字）
- **六种 schema 演进**哪种安全、哪种会炸（本地 fastavro 实测）
- Schema Registry 的**核心价值**：把"能不能演进"从上线后炸，提前到注册时拒
- 兼容性策略矩阵 **backward / forward / full / none** 的真实差异
- 一个**推翻课程预设**的发现：Schema Registry 不是 confluent-kafka 独占能力
- 三个**必踩的坑**（本课实测踩全了，全都有复现与解法）

## 先修

- 课 1~2（生产者/消费者基础）
- 阶段 3 环境：`docker build -t kafka-pybench:3.12 assets/bench/`

## 本课实验环境

| 组件 | 版本 / 说明 |
|---|---|
| Kafka | `apache/kafka:4.0.0`，3 节点 KRaft，PLAINTEXT |
| Schema Registry | `confluentinc/cp-schema-registry:7.6.1` |
| confluent-kafka | 2.15.x |
| kafka-python | 3.0.11 |
| fastavro | 1.12.2 |

启动：`docker compose -f assets/bench/docker-compose.l9.yml up -d`

---

## 一、先纠一个预设：SR 客户端不是"不存在"，是依赖没装

阶段 3 概览原本的判断是"confluent-kafka 的 schema_registry 子包不可用"。

**这句是错的，已被本课实测推翻。**

第一次探路时 `import confluent_kafka.schema_registry` 报 `ModuleNotFoundError`，我据此判定"子包不存在"。但进一步剥依赖发现：**子包在，缺的是它的 HTTP 层依赖**。

逐个补齐后全部可用：

| 依赖 | 缺它时的报错 | 作用 |
|---|---|---|
| `certifi` | ModuleNotFoundError | HTTPS 证书 |
| `httpx` | ModuleNotFoundError | HTTP 客户端 |
| `authlib` | ModuleNotFoundError | OAuth 鉴权 |
| `cachetools` | ModuleNotFoundError | schema 缓存 |
| `googleapis-common-protos` | `No module named 'google.type'` | Protobuf well-known types |

补齐后实测：

```
✓ SchemaRegistryClient / Schema 可导入
✓ AvroSerializer / AvroDeserializer 存在
✓ JSONSerializer 存在
✓ ProtobufSerializer 存在
✓ SerializingProducer / DeserializingConsumer 可用
```

> 📌 **教训**：`ModuleNotFoundError` 报的是"某个依赖没装"，不等于"这个功能不存在"。我第一版探路脚本用 mock 循环剥依赖，只剥了 4 层就停了，漏掉 `cachetools`——**探路脚本本身有 bug，却得出了"子包不存在"的结论**。

---

## 二、格式对照：Avro 到底省在哪

同一条订单消息，各格式实测（N=20000）：

| 格式 | 单条字节 | 相对 JSON |
|---|---|---|
| JSON（无 schema） | 162 | 100% |
| JSON + type 标记 | 178 | 109% |
| **Avro（schema 外部）** | **62** | **38%** |
| Avro + 内嵌 schema | 439 | 270% |

| 格式 | 编码吞吐（10 次采样区间） | 解码吞吐 |
|---|---|---|
| JSON | 418,078 ~ 454,567/s | 576,437 ~ 768,117/s |
| Avro (fastavro) | 490,367 ~ 529,664/s | 511,133 ~ 825,367/s |

> 数值说明：上表为**本机 10 次采样区间**（分两轮各 5 次），非单次测量。
> 单次采样浮动可达 ±8%，不以单点值呈现。
>
> ⚠️ **不同脚本测出的绝对值不同**：本节用 `l9_format_compare.sh`（Avro 49~53 万），
> 三点五节用 `l9_protobuf.sh`（Avro 65~80 万）。两者**实现细节不同**（写入路径与
> 数据构造方式有差异），**不可跨表比较**。比较请在**同一张表内**进行。

**两个实测结论**：

1. **Avro 省 62% 体积**。按 1 亿条/天算，省 9.3 GB/天，磁盘和网络双省。
2. **Avro 编码比 JSON 快，且 10 次采样区间不重叠**（Avro 最低 490k > JSON 最高 455k）。
   我原本的预设是"纯 Python 的 fastavro 肯定比 C 加速的 json 慢"——**实测推翻**。
   fastavro 带 Cython 加速，性能不是选型的顾虑点。

**但注意第三行**：把 schema 塞回每条消息，体积立刻涨到 439 字节，比裸 JSON 还大 2.7 倍。

这就引出了 Avro 的核心设计取舍：

```
schema 放外面  -> 消息小，但需要一个地方集中管理 schema
schema 放里面  -> 自描述，但每条都要带上，体积爆炸
```

**Schema Registry 就是"schema 放外面"那个方案的集中管理组件。**

---

## 三、六种演进，哪种会炸

用 fastavro 实测 writer/reader schema 解析（writer 写、reader 读）：

| 演进类型 | 本地结果 | 说明 |
|---|---|---|
| 新增字段**带默认值** | ✅ 读得通 | 旧数据读出默认值 `currency=CNY` |
| 新增字段**无默认值** | ❌ `SchemaResolutionError` | 旧数据缺该字段 |
| 删除字段 | ✅ 读得通 | reader 忽略多余字段 |
| int → long 提升 | ✅ 读得通 | Avro 原生支持 |
| long → int 缩窄 | ❌ `Schema mismatch` | 小值大值都被拦 |
| **改字段名** | ✅ **读得通** | ⚠️ **数据静默丢失** |

### 这里推翻了我的预设

我预判"long→int 缩窄会静默损坏（小值侥幸通过、大值溢出）"。**实测不是**：

```
✗ long->int 缩窄(小值42)  : SchemaResolutionError: Schema mismatch: long is not int
✗ long->int 缩窄(大值30亿): SchemaResolutionError: Schema mismatch: long is not int
```

fastavro 本地就拦得住，反而**安全**。

**真正危险的是改字段名**：

```python
# v1 写的：{"order_id":"ORD-1","amount":99.5}
# v2 reader 把 amount 改名为 total，并给了默认值 0.0
# 读出来：
{'order_id': 'ORD-1', 'total': 0.0}   # ← amount 的 99.5 凭空消失了，零警告
```

**这是唯一一个本地完全静默的破坏性改动**。改字段名在 Avro 眼里等于"删掉 amount + 新增 total"，语义上你的数据就断了。

> 📌 记住这张表的**真实风险排序**（按危险度，不是按能不能跑）：
> 1. 🥇 **改字段名**：静默丢数据，本地零警告，只能靠规范或 SR 策略防
> 2. 🥈 **删字段**：读得通，但下游若还要该字段会静默拿到缺失
> 3. 🥉 **类型变更**：fastavro 本地就报错，反而是安全的

---

## 三点五、Protobuf：第三方对照补齐

> 补齐说明：本节知识点标题写的是「JSON/Avro/Protobuf」，但课 9 首版只验证了
> Protobuf 客户端"能导入"——那等于这块是空的。本节补齐完整对照。

### 无 protoc 也能玩 Protobuf

本机没有 `grpcio-tools`（无 protoc）。但 protobuf 的 `descriptor_pb2` 支持**动态构造消息类型**，不需要预编译 `.proto`：

```python
from google.protobuf import descriptor_pb2, descriptor_pool, message_factory
from google.protobuf.descriptor_pb2 import FieldDescriptorProto as FDP

fdp = descriptor_pb2.FileDescriptorProto()
fdp.package = "bench"; fdp.syntax = "proto3"
d = fdp.message_type.add(); d.name = "Order"
f = d.field.add(); f.name = "order_id"; f.number = 1
f.type = FDP.TYPE_STRING; f.label = FDP.LABEL_OPTIONAL
# ... 其余字段
fd = descriptor_pool.Default().Add(fdp)
OrderCls = message_factory.GetMessageClass(fd.message_types_by_name["Order"])
```

⚠️ **API 变更**：protobuf 4.x 的 `message_factory.GetPrototype()` 在 7.x **已移除**，改用 `GetMessageClass(descriptor)`。老教程照抄会 `AttributeError`。

### 三方体积对照（同一条订单）

| 格式 | 字节 | 相对 JSON |
|---|---|---|
| JSON | 88 | 100% |
| **Avro** | **32** | **36%** |
| Protobuf | 37 | 42% |

Avro 与 Protobuf 基本打平，都比 JSON 省约 6 成。

### 三方吞吐对照（N=20000，5 次采样区间）

| 格式 | 编码/s | 解码/s |
|---|---|---|
| JSON | 480,763 ~ 555,872 | 683,279 ~ 768,117 |
| Avro | 650,987 ~ 798,640 | 795,856 ~ 825,367 |
| **Protobuf** | **1,707,012 ~ 2,104,799** | **3,985,405 ~ 4,471,124** |

> 数值为 5 次采样区间。Avro 波动可达 19%（65 万 ~ 80 万），**单点值不可信**。
> 但 Protobuf 最低值（170 万）仍高于 Avro 最高值（80 万），**区间不重叠**，
> 故「Protobuf 编码快于 Avro」结论稳定成立。

> ⚠️ **测法陷阱（核验后修正）**
>
> 首版测出 Protobuf 编码 **7,428,822/s**，比 Avro 快 10 倍。这个数字**夸大了 3.1 倍**——
> 原因是循环里复用了同一个 message 对象，protobuf 的 upb 实现对复用对象有加成。
>
> 三种测法对比（同机、同样波动，取多次采样中位量级）：
>
> | 测法 | 编码/s |
> |---|---|
> | A. 复用同一对象 | 448 万 ~ 652 万 |
> | B. 每次新建（构造参数） | 198 万 ~ 214 万 |
> | **C. 新建 + 逐字段赋值** | **174 万 ~ 208 万** |
>
> 讲义采用**测法 C**（最保守）。真实结论是 Protobuf **比 Avro 快约 2.2~2.7 倍**，不是 10 倍。
> 复用对象会夸大 **2.6~3.1 倍**——这是最容易踩的性能测量陷阱。

### Protobuf 的演进模型：靠编号，不靠名字

**加字段（用新编号）是安全的**：

```
新 reader 读旧数据 -> currency 自动为默认值 ''（proto3 无显式默认值语义）
旧 reader 读新数据 -> 未知 currency 进 unknown fields，不报错
```

**但改 field number 是致命的**——这是 Protobuf 独有的风险：

```
原始:  amount=99.5, status='PAID'
把 amount 的编号从 3 改成 4、status 从 4 改成 3 后读同一个 bytes:
  -> order_id: "ORD-1"  user_id: "U-1001"  ts: ...
     amount 和 status 都消失了
```

Protobuf 靠**数字编号**识别字段，不看字段名。改编号 = wire data 被错误解读，且**不报错**。

### Protobuf 也能接入 SR

真 SR 对 Protobuf 一视同仁（实测）：

| 操作 | 结果 |
|---|---|
| 注册 P1（`schemaType: PROTOBUF`） | ✅ id=12 |
| 注册 P2（加字段，新编号 6） | ✅ 放行 id=13 |
| 注册 P3（改 amount 类型） | ❌ 409 `FIELD_SCALAR_KIND_CHANGED` |

### 三者怎么选

| 维度 | JSON | Avro | Protobuf |
|---|---|---|---|
| 体积 | 100% | **36%** | 42% |
| 编码速度 | 1x | 1.5x | **2.7x** |
| 演进依据 | 无 schema | schema 解析规则 | **field number** |
| 静默风险 | 无 | 改字段名丢数据 | **改编号错位** |
| 适合 | 调试/小流量 | Kafka 生态默认 | gRPC 已有体系 |

> 📌 选型分水岭不在体积和速度（同量级），在**演进安全模型和既有生态**：
> 已经是 gRPC 体系 → Protobuf；Kafka 新项目 → Avro（生态最配）。

---

## 四、没有 Schema Registry 怎么活

kafka-python 顶层确实没有 schema 相关导出（实测确认）。**但这不代表它不能用 Avro**——序列化库是通用的，可以手工拼。

### Confluent wire format

SR 生态的标准消息布局，就三截：

```
[magic byte: 1字节 0x00][schema id: 4字节 big-endian][Avro payload]
```

实测一条真实消息：

```
0000000002 0a4f52442d31 0000000000e05840 06 555344
^^^^^^^^^^ ^^^^^^^^^^^^ ^^^^^^^^^^^^^^^^ ^^ ^^^^^^
magic+id=2 "ORD-1"       amount=99.5     len "USD"
```

总共 23 字节。手工拼也完全可行（实验④已跑通端到端 10 条）。

### 手工方案的四个软肋

| 维度 | 手工方案 (kafka-python) | Schema Registry |
|---|---|---|
| schema 存在哪 | 自己找地方存 | 集中存 `_schemas` topic |
| **兼容性谁校验** | **没人校验 / 人肉评审** | **注册时强制校验** |
| 能设兼容策略吗 | 不能 | 7 种策略 |
| 消费端怎么拿 schema | 约定俗成 / 硬编码 | 按 id 自动拉取+缓存 |
| 改坏 schema 会怎样 | 上线后炸，回滚数据难 | 注册时就拒绝 |

**结论**：kafka-python 缺的不是序列化能力，是**集中式兼容性校验的治理能力**。

所以阶段 3 概览那句话应改为：

> ❌ 旧："Schema Registry 是 confluent-kafka 独占"
> ✅ 新："**SR 客户端**是 confluent-kafka 独占；**Avro 序列化本身**两库都能做"

---

## 五、Schema Registry 的核心价值：注册时拒

真 SR 7.6.1 实测（官方 Python 客户端）：

| 操作 | 结果 |
|---|---|
| 注册 v1 首版 | ✅ id=1 |
| 注册 v2（新字段带默认值） | ✅ 放行 id=2 |
| 注册 v3（新字段**无**默认值） | ❌ HTTP 409 拒绝 |
| 注册 v4（改字段类型） | ❌ HTTP 409 拒绝 |
| 重复注册 v2 | ✅ id=2（幂等） |
| 预检 v3 兼容性（不注册） | `False` |

服务端给的是**结构化错误码**，比"不兼容"三个字有用得多：

```
[5] errorType: READER_FIELD_MISSING_DEFAULT_VALUE
    description: The type ... in the new schema ...
[6] errorType: TYPE_MISMATCH
    description: The type (path '/fields/1/type') of a ...
```

**这就是全部价值所在**：坏 schema 根本进不了系统，从"上线后炸"提前到"注册时拒"。

### 兼容性策略矩阵（真 SR 实测）

| 演进 | BACKWARD | FORWARD | FULL | NONE |
|---|---|---|---|---|
| 删字段 | ✅ 放行 | ❌ 拒绝 | ❌ 拒绝 | ✅ 放行 |
| 加字段(带默认值) | ✅ 放行 | ✅ 放行 | ✅ 放行 | ✅ 放行 |

**选型口诀**：

- 能先升消费者 → **BACKWARD**（SR 默认，最常用）
- 只能先升生产者（消费者是外部系统、升级慢）→ **FORWARD**
- 两方向都有旧版本在线 → **FULL**
- 生产环境**永远不要 NONE**——那就等于没上 SR

---

## 六、端到端：老生产者不停机，新消费者照读

真 SR + 真 Kafka 的完整闭环，10/10 条：

```
✓ schema 注册: v1->id1, v2->id2
✓ v2 serializer 生产 5 条
✓ v1 serializer 生产 5 条（模拟老生产者未升级）

消费 10 条（全部用 v2 schema 解码）：
  {'order_id': 'V2-3', 'amount': 23.0, 'currency': 'USD'}   ← v2 消息，保持 USD
  {'order_id': 'V1-3', 'amount': 13.0, 'currency': 'CNY'}   ← v1 消息，自动填默认值
```

**关键在第三行**：v1 消息本身**没有** currency 字段（老生产者不知道有这字段），但被 v2 schema 读出时自动填上了 `CNY`。

**这就是 backward 兼容的完整兑现**：老生产者不用改、不用停机，新消费者一把全读，零报错。

---

## 七、三个必踩的坑（本课全踩了一遍）

### 坑 1：`SerializingProducer` 的 serializer 签名

想省事直接传 `str.encode`：

```python
SerializingProducer({"key.serializer": str.encode})   # ❌
```

实测报错：

```
KeySerializationError: encode() argument 'encoding' must be str, not SerializationContext
```

**原因**：serializer 签名必须是 `(obj, ctx)` 两参数，`str.encode` 只接受 `(encoding, errors)`。

```python
def key_ser(k, ctx): return k.encode() if isinstance(k, str) else k   # ✅
```

消费端 `bytes.decode` 同理，也要包装。

### 坑 2：`set_config` 静默不生效（最危险）

```python
client.set_config(subj, ServerConfig(compatibility_level=ConfigCompatibilityLevel.FULL))
# 不报错，返回 {} —— 但策略【根本没设上去】
```

回读发现还是 `BACKWARD`：

```
GET /config/DIAG-full  ->  {"compatibilityLevel":"BACKWARD"}
```

**根因**：`ServerConfig` 有 `compatibility` 和 `compatibility_level` 两个字段，`to_dict()` 产出不同的 JSON key：

```python
ServerConfig(compatibility_level=FULL).to_dict()  # {"compatibilityLevel": "FULL"}
ServerConfig(compatibility=FULL).to_dict()        # {"compatibility": "FULL"}
```

而 SR 7.6.1 的 REST 端认的是 `compatibility`。传 `compatibility_level` **不报错但静默失效**。

这是最危险的失败模式——**不报错，只是没生效**。我因此拿到了一张"全部放行"的假矩阵，如果直接写进讲义就是错的。

**解法**：设完立刻回读确认，或直接走 REST：

```python
rest("PUT", f"/config/{subj}", {"compatibility": level})
_, r = rest("GET", f"/config/{subj}")
assert r["compatibilityLevel"] == level, "策略未生效"    # 不确认就等于没设
```

### 坑 3：fastavro 1.12 的 API 位置

```python
fastavro.write(...)                    # ❌ 是模块，不是函数
fastavro.schema.parse_schema(...)      # ❌ 是模块，不是函数
```

正确入口：

```python
fastavro.parse_schema(schema)                       # ✅
fastavro.schemaless_writer(buf, parsed, rec)        # ✅ Kafka 场景用它
fastavro.schemaless_reader(buf, writer, reader)     # ✅
```

用 `schemaless_*` 更贴合 Kafka：消息体不含 schema 文本，靠外部 schema id 引用。

### 坑 4：protobuf 7.x 的 `GetPrototype` 已移除

老教程的写法：

```python
message_factory.GetPrototype(descriptor)     # ❌ AttributeError in 7.x
```

改为：

```python
message_factory.GetMessageClass(descriptor)  # ✅
```

### 坑 5：Protobuf 吞吐测法会夸大 3 倍

循环里复用同一个 message 对象，protobuf 的 upb 实现有内部加成，
实测夸大到 448 万 ~ 652 万/s（真实保守值 174 万 ~ 208 万/s），**夸大 2.6~3.1 倍**。

**测吞吐必须每次新建对象**，否则数字不可信。详见三点五节测法对比表。

---

## 八、本节结论

1. **体积**：Avro 省 62%、Protobuf 省 58%，两者打平，1 亿条/天省 9 GB 级
2. **速度**：Protobuf > Avro > JSON（编码区间不重叠），但同量级，不是选型主因
3. **演进安全**：加字段带默认值最安全；**Avro 怕改字段名，Protobuf 怕改编号**，都会静默坏
4. **SR 价值**：把兼容性从"上线后炸"提前到"注册时拒"，返回结构化错误码
5. **kafka-python**：不是不能用 Avro，是缺集中治理能力；手工拼 wire format 完全可行
6. **策略选择**：默认 BACKWARD；生产别用 NONE
7. **选型分水岭**：不在体积速度，在**演进模型 + 既有生态**（gRPC→Protobuf，Kafka 新项目→Avro）

## 九、复现命令

```bash
# 环境与集群
docker compose -f assets/bench/docker-compose.l9.yml up -d

# 各实验
bash assets/bench/l9_avro_compat.sh        # 六种演进兼容性
bash assets/bench/l9_format_compare.sh     # 格式体积/速度对照
bash assets/bench/l9_no_sr.sh              # 无 SR 手工方案
bash assets/bench/l9_e2e_manual_wire.sh    # 手工 wire format 端到端
bash assets/bench/l9_real_sr.sh            # 真 SR 官方客户端全流程
bash assets/bench/l9_e2e_real_sr.sh        # 真 SR 端到端闭环
bash assets/bench/l9_compat_policy.sh      # 兼容性策略矩阵
bash assets/bench/l9_protobuf.sh           # Protobuf 三方对照
bash assets/bench/l9_pb_sr.sh              # Protobuf 接入 SR
bash assets/bench/l9_pb_verify.sh          # Protobuf 吞吐测法核验
```

---

## 诚实标注

- 本课所有数字均为本机实测（WSL2 / Docker / 3 节点 KRaft），**非引用文档**
- Protobuf 吞吐已从「复用对象」测法改为「新建+逐字段赋值」测法（原值夸大 3.1 倍，见三点五节）
- 吞吐量存在 ±5% 浮动，表格中的速度值为单次采样；体积值确定
- 兼容性策略只实测了 4 种（BACKWARD/FORWARD/FULL/NONE），SR 另有 3 种 transitive 变体未实测
- SR 单节点部署，**未测多节点 HA 与故障切换**
- Protobuf 未接 `ProtobufSerializer` 跑完整 Kafka 端到端，只做到 SR 注册与本地编解码

## 导航

- ⬆️ 返回：[阶段 3 概览](overview.md)
- ⬅️ 上一课：[课 8 · 事务与恰好一次](课8-事务与恰好一次.md)
- ➡️ 下一课：[课 10 · 消费者工程与并发模型](课10-消费者工程与并发模型.md)
- 📖 进度：[00-学习档案](../../00-学习档案.md)
