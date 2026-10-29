/**
 * 课 6 · 记忆、沙箱与身份（TypeScript 侧）
 *
 * 对应课文：stages/2-能力声明/lessons/06-记忆沙箱与身份.md
 *
 * 三个知识点：
 *   ① 记忆：memory.ts 声明层，省略 = 关闭（不是"默认开"）
 *   ② 沙箱：sandbox/ 声明，permissions 不在作者手里
 *   ③ 身份：principal 由平台签发，是判权限的唯一依据
 *
 * ⚠️ 本课实测到一个课文没写的事实：memoryLayer 的 allow 回调
 *    在 0.9.5 已标 @deprecated，见实验 2。
 */

import { defineMemory, memoryLayer, defineSandbox, defineIdentity } from "managed-deepagents";
import { section, step, show, showConfigKeys, hasKey, attempt } from "./_shared.ts";

type AppContext = { remember?: boolean; region?: string };

// ── 实验 1：记忆默认是关的 ─────────────────────────────────────
section("实验 1", "省略 memory.ts = 没有长期记忆");

console.log(`
  托管版把"有没有记忆"做成了文件存在性：
    仓库里没有 memory.ts        → 没有持久记忆
    有 memory.ts 但 export {}    → 同样没有（声明空 = 挂空层）

  这与"默认开、你可以关"相反。理由是：长期记忆是带成本的
  （存储、检索、注入 token），不该因为没写就默认背上。
`);

const plainMemory = defineMemory({
  agent: memoryLayer(),
  user: memoryLayer(),
});
show("kind", (plainMemory as unknown as { kind: string }).kind);
show("keys", Object.keys(plainMemory));
show("config", (plainMemory as unknown as { config: unknown }).config);

step("两层记忆的分工");
console.log(`
  agent 层：这个 agent 自己攒的经验，所有用户共享
  user  层：每个用户自己的偏好，跨会话跟着人走

  两条都声明 = 两层都开。只声明 agent = 只有团队记忆，没有个人记忆。
  这个"声明哪些就开哪些"的语义，是跟"默认全开再一个个关"最大的区别。
`);

// ── 实验 2：allow 回调——类型联合 + 已废弃 ─────────────────────
section("实验 2", "memoryLayer 的 allow 回调（两个隐藏坑）");

const gatedMemory = defineMemory<AppContext>({
  agent: memoryLayer(),
  user: memoryLayer<AppContext>({
    // 坑 ①：参数不是 AppContext，是 ManagedRunContext<AppContext>
    //        = AppContext | ManagedChannelContext 的联合类型，
    //        所以必须先判 in 再取字段，不能直接 context.remember
    allow: (context) => "remember" in context && context.remember === true,
  }),
});

show("gated kind", (gatedMemory as unknown as { kind: string }).kind);

console.log(`
  坑 ①：回调参数是联合类型
    ManagedRunContext<AppContext> = AppContext | ManagedChannelContext
    直接写 context?.remember 会被 tsc 拒（TS2339），
    因为 ManagedChannelContext 分支上没有 remember。

  坑 ②：allow 在 0.9.5 已标 @deprecated
    原文：Select memory from a dynamic agent definition instead.
          This callback will be removed in a future release.
    也就是说"按运行时条件决定要不要挂记忆"这条路官方正在收回，
    未来应改成"在工厂入口里挑 memory 定义"。
`);

step("allowed 写法对照：工厂入口挑层（未废弃的路）");
console.log(`
  工厂入口可以 return defineDeepAgent({ memory: 某个定义 })，或传 null 关掉：
    memory: null   → 本次运行不挂记忆
    memory: def    → 本次运行挂这个定义
  这样"要不要记忆"由工厂决定，不依赖已废弃的 allow 回调。
`);

// ── 实验 3：沙箱声明 ─────────────────────────────────────────
section("实验 3", "沙箱：声明资源，不是声明权限");

const sandbox = defineSandbox({
  idleTtlSeconds: 600,
  defaultTimeout: 600,
});
show("kind", (sandbox as unknown as { kind: string }).kind);
show("options", (sandbox as unknown as { options: unknown }).options);

step("permissions 不在作者手里");
console.log(`
  这是与直连 deepagents 差异最大的一处：
    直连：你在 createDeepAgent({ permissions }) 里自己写 allow/deny
    托管：permissions 归平台，作者只能声明"要不要沙箱、多大、多久回收"

  实测证据（Python 侧源码）：sandbox 一旦存在，
  runtime 会把 permissions 直接清空（两处：_mount_selected_skills 与
  _apply_managed_context），因为沙箱本身就是隔离边界。
  所以"我写了 deny 却没生效"在托管版不是 bug，是设计。
`);

// ── 实验 4：dockerImage 与其他选项互斥 ────────────────────────
section("实验 4", "dockerImage 与 snapshot 互斥（类型层就拦住）");

const dockerSandbox = defineSandbox({
  idleTtlSeconds: 900,
  defaultTimeout: 120,
  dockerImage: "python:3.12-slim",
});
show("dockerImage 写法 options", (dockerSandbox as unknown as { options: unknown }).options);

console.log(`
  类型定义里 dockerImage 那一路有四种互斥形态：
    不给镜像（默认）      dockerImage?: undefined
    给 snapshotName       dockerImage?: never
    给 snapshotId         dockerImage?: never
    给 dockerImage        dockerImage: string   ← 这一路才允许
  同时给 snapshotName 和 dockerImage 是类型错误；
  但即便用 as any 绕过类型硬跑，运行时也会再拦一次：
    TypeError: snapshotName, dockerImage are mutually exclusive.
               Pass only one bake base.
  双保险——所以"我绕过了类型为什么还炸"不是 bug。
`);

attempt("同时给 snapshotName 与 dockerImage", () =>
  defineSandbox({
    snapshotName: "my-snap",
    dockerImage: "python:3.12-slim",
  } as never),
);

// ── 实验 5：身份 ─────────────────────────────────────────────
section("实验 5", "身份：principal 是平台签发的，不是调用方填的");

console.log(`
  三条路进来的人，principal 来源不同：
    Slack 通道    → Slack 用户身份，平台校验后放进 principal
    HTTP 通道     → 你在 verify() 里验签，平台据此签发
    服务间调用    → LangSmith API key（auth.langsmithApiKey()）

  共同点：principal 由平台给出，代码里改不了。
  所以工具里判权限只能读 runtime.serverInfo.principal，
  读 runtime.context 等于让调用方自己声明"我是谁"。
`);

show("defineIdentity 类型", typeof defineIdentity);
show("defineIdentity arity", defineIdentity.length);

console.log(`
  身份配置的完整形态见身份文档（identity.ts）。
  本课不展开——它需要真实 IdP 才能验证，本地只能看声明形状。
`);

section("完成", "课 6 实测结束");
