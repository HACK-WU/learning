# 实现说明

> 这是「数据库变更审批助手」的可运行实现，对应课程 Phase 3 结课项目。
> 全部代码用 TypeScript 编写，依赖 `@langchain/langgraph`，**已实测运行**。

## 目录结构与四层的对应

```
实现/
├── config/agent.yaml            # 定义面：一份 Agent 定义（纯数据）
├── src/
│   ├── definition/              # 定义面：schema + 校验前置
│   ├── compile/compiler.ts      # 编译面：定义 → StateGraph
│   ├── execute/tools.ts         # 执行面：工具 provider + 执行器（授权在此）
│   ├── account/                 # 账本面：checkpoint 存储 + 调用账本
│   └── main.ts                  # CLI：串起五步链路
├── verify.ts                    # 验收脚本 A（工具边界 / 校验 / 幂等）
└── verify2.ts                   # 验收脚本 B（策略拦截 / 拒绝路径 / 通道）
```

四层不是按目录硬分的，是按"输入输出"分的：定义面吃 YAML 产对象，编译面吃对象产图，执行面吃图产结果，账本面吃结果产记录。目录名只是让人一眼找到。

## 运行方式

```bash
npm install
npm run check      # 类型检查（tsc --noEmit）
npm run demo       # 发起变更 → 挂起等审批
npm run resume     # 新进程从 checkpoint 恢复并执行
npm run demo:reject # 审批拒绝路径
npx tsx verify.ts   # 验收脚本 A
npx tsx verify2.ts  # 验收脚本 B
```

## 实测记录

以下输出来自本机真实执行（Node 22.22.2 / @langchain/langgraph 1.6.0），不是预期稿。

**挂起（`npm run demo`）**：

```
event: started
data: {"type":"started","invocationId":"cfb8e94d-..."}
event: interrupt
data: {"type":"interrupt","payload":{"kind":"approval_required","tool":"executeSql","args":{"sql":"ALTER TABLE orders ADD COLUMN note TEXT"}}}

⏸  已挂起等待审批。进程可以退出，恢复请执行：npm run resume
```

**跨进程恢复（`npm run resume`，新进程）**：

```
event: tool
data: {"type":"tool","name":"executeSql","output":"[execute] 已为 orders 添加列 note"}
event: done
data: {"type":"done","status":"succeeded","output":["[execute] 已为 orders 添加列 note"]}
```

**验收脚本 A（10 项）**：

```
① 工具清单: querySql, executeSql, notifyOwner
② 只读查询: [query] orders 列：id, amount, status
③ 写操作: [execute] 已为 users 添加列 last_login
④ 变更后结构: id, email, last_login
⑤ 危险语句被拦: 本示例禁止 DROP / TRUNCATE（演示工具边界）
⑥ querySql 越权被拦: querySql 只接受 SELECT
⑦ 定义校验: policies.requireApprovalFor 引用了未声明的工具：「executeSql」
⑧ 定义校验（非法结构）: version / prompt / model 三条问题一次报出
⑨ 同键同输入重复提交 → duplicated: true
⑩ 同键异输入被拒: requestId 冲突
```

**验收脚本 B（拦截点证明）**：

```
A 有审批策略 → 是否挂起: true
B 去掉审批策略 → 是否挂起: false | 执行结果: ["[execute] 已为 orders 添加列 note"]
C1 先挂起: true
C1 挂起时 orders 结构: id,amount,status （应无 flag）
C2 拒绝后结果: ["审批未通过（reject），已取消执行"]
C2 拒绝后 orders 结构: id,amount,status （应仍无 flag）
```

B 组是本项目的关键证据：**只改定义里的 `requireApprovalFor`，代码一行不动，拦截行为就消失**——这证明拦截点确实在策略层，而不是写死在工具实现里。

## 三个刻意的取舍

**只做 3 个状态通道**（messages / approval / result），不是标本系统的 10 个。通道化的收益来自"多路写入需要独立合并"，本项目只有两条写入路径，再细拆只是增加心智负担。

**不缓存编译产物**，每次请求重编。代价是首字延迟，收益是行为永远与当前定义一致——本项目要验证的正是"改定义即改行为"，缓存会掩盖这条因果。

**工具 provider 只做两层**（builtin / remote），不追求覆盖所有来源。抽象做小的原因是：抽象一旦定错，后续所有工具都受影响；小抽象错了好改。

## 一处必须说明的限制

`InvocationRuntime` 是**进程内 Map**，仅用于演示幂等与账本语义。真实系统里它必须是数据库表 + 唯一约束（`request_id`），否则多副本部署时幂等直接失效——两个实例各记一份，同一个请求会执行两次。

这不是"没做完"，是刻意把"幂等语义"和"幂等实现"分开讲：语义（同键同输入返回旧结果、同键异输入拒绝）是设计，存到哪是部署问题。验收清单里那条"同一 request_id 提交两次只执行一次"，在单进程演示中成立，跨副本需要你补上唯一约束。
