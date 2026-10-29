/**
 * 课 8 · 通道与调度（TypeScript 侧）
 *
 * 对应课文：stages/3-运行与交付/lessons/08-通道与调度.md
 *
 * 三个知识点：
 *   ① 通道：Slack 开箱可用，HTTP 要自己写 verify / parse / post
 *   ② 调度：at 取整、五分钟下界、post 与 newThread 语义
 *   ③ 线程：current_thread 与 new_thread 的选择
 *
 * 本课不真连 Slack / 不真排调度：所有实测都在"适配器形状与校验"这一层。
 */

import { channels, defineSchedule } from "managed-deepagents";
import type { HttpChannelRequest, HttpChannelParseResult } from "managed-deepagents";
import { section, step, show, attempt } from "./_shared.ts";

// ── 实验 1：Slack 开箱 ───────────────────────────────────────
section("实验 1", "channels.slack：单个函数，全是可选参数");

show("channels 命名空间的键", Object.keys(channels as unknown as object));
show("channels.slack 类型", typeof (channels as any).slack);

const slack = (channels as any).slack({
  name: "support",
  triggerOnAllMessages: false,
  reactions: "eyes",
});
show("slack 返回类型", slack?.constructor?.name);
show("slack kind", slack?.kind);
show("slack keys", Object.keys(slack ?? {}));

console.log(`
  Slack 是唯一"开箱即用"的通道：不用写 verify / parse，
  平台侧已经处理了签名验证与事件解析。
  你能调的只有行为开关：
    name                    通道名（多通道时区分用）
    triggerOnAllMessages    是否响应所有消息（默认只响应 @ 提及）
    allowBotTriggers        是否允许其他 bot 触发（防循环）
    reactions               收到消息后先打什么表情
`);

// ── 实验 2：HTTP 通道的三件套 ────────────────────────────────
section("实验 2", "channels.http：verify / parse / post 三件套");

export function verify({ request, rawBody }: HttpChannelRequest): boolean {
  const secret = process.env.ORDERS_WEBHOOK_SECRET;
  if (!secret) return false;
  // 真实实现要用 HMAC + timingSafeEqual；这里只演示形状
  return rawBody.length > 0 && request.headers.has("x-orders-signature");
}

export async function parse({
  request,
}: HttpChannelRequest): Promise<HttpChannelParseResult> {
  const event = await request.json();
  if (event.type !== "order.comment") {
    return { type: "ignore" };
  }
  return {
    type: "message",
    message: {
      userId: String(event.actor.id),
      threadId: String(event.order.id),
      content: event.comment.body,
      target: String(event.order.id),
    },
    rawEvent: event,
  };
}

export const ordersChannel = channels.http({
  provider: "orders",
  verify,
  parse,
});

show("http 通道 kind", (ordersChannel as unknown as { kind: string }).kind);
show("provider", (ordersChannel as unknown as { provider: string }).provider);

step("三件套各自的责任边界");
console.log(`
  verify(req)   → boolean        验签：这个请求真是对方发的吗
  parse(req)    → ParseResult    解码：这条事件要不要处理、处理成什么消息
  post(input)   → PostedMessage  回帖：把 agent 的回复送回对方系统

  分工的关键在"返回 ignore 的能力"：
    verify 只能整体放行或拒绝（拒绝 = 401）
    parse 可以"验过了但这条不用管"（返回 { type: "ignore" }）
  这两种"不处理"在对方看来完全不同，别混用。
`);

step("ParseResult 的两种形态");
console.log(`
  { type: "message", message: {...}, rawEvent? }
  { type: "ignore" }
  只有这两种。message 里四个必填字段：
    userId    谁说的（映射成 principal 的依据）
    threadId  落到哪个会话（决定上下文是否延续）
    content   说了什么
    target    回帖往哪发（与 threadId 解耦，可以不相等）
`);

// ── 实验 3：post 的 newThread 语义 ──────────────────────────
section("实验 3", "post 与 newThread：定时任务的线程归属");

console.log(`
  post(input) 收到的 input 上有个 newThread 标志：
    普通消息回复   newThread 为假 → 回复进原会话，对话上下文延续
    定时任务投递   newThread 为真 → 新开一个会话，target 不变

  为什么定时任务要新开会话？
    定时任务没有"原会话"这个概念（它是时间触发，不是消息触发），
    硬塞进某个已有会话会污染那段对话的上下文。
`);

// ── 实验 4：起不来的三种坏适配器 ───────────────────────────
section("实验 4", "坏适配器：各自在哪一层炸");

attempt("verify 返回非布尔", () =>
  channels.http({ provider: "x", verify: (() => "yes") as never, parse } as never),
);

attempt("缺少 parse", () =>
  channels.http({ provider: "x", verify } as never),
);

attempt("provider 为空串", () =>
  channels.http({ provider: "", verify, parse } as never),
);

console.log(`
  实测结论（只有一条会炸，其余静默通过）：
    verify 返回非布尔     → 不抛，返回 { kind: "x" }（缺少其他键）
    缺少 parse            → 不抛，返回 { kind: "x" }
    provider: ""          → 抛错：channels.http provider must be a non-empty string

  这个结果比"全都拦"更值得记：
    通道声明只校验 provider，verify / parse 的函数签名不校验。
    所以"我的通道起来了但消息全被忽略"多数是 parse 返回了错误的形状，
    而不是声明阶段报错——声明阶段根本不会告诉你。

  与其他能力对比：sandbox 的互斥会双保险（类型 + 运行时），
  通道适配器只在 provider 上兜底——同一个包里校验强度并不一致。
`);

// ── 实验 5：调度声明 ───────────────────────────────────────
section("实验 5", "defineSchedule：at 的格式与下界");

show("defineSchedule 类型", typeof defineSchedule);
show("defineSchedule arity", defineSchedule.length);

console.log(`
  调度声明的三个必填概念：
    schedule   什么时候跑（cron 表达式 或 at 时间点）
    prompt     跑的时候让 agent 做什么
    delivery   结果投到哪（target + newThread）

  ⚠️ 两个实测得出的约束（Python 侧同）：
    ① at 只接受整分钟——秒会被取整，写 "09:30:45" 实际是 09:30
    ② 距今不足五分钟的 at 会被拒——避免"排一个马上就要跑的任务"

  这两个约束本地只能看定义，真跑要部署；
  所以本课对调度"只测声明形状"，触发行为标 ⚠️ 未实测。
`);

attempt("调度缺 delivery", () =>
  defineSchedule({ schedule: "0 9 * * *", prompt: "早安" } as never),
);

// ── 实验 6：current_thread 不能用于调度 ─────────────────────
section("实验 6", "调度不能用 current_thread");

console.log(`
  投递目标有两个：
    current_thread   回到"发起这次运行的那个会话"
    target           指定一个具体目标

  调度没有"发起会话"（时间触发），所以 current_thread 对它无意义。
  类型定义里 ScheduleDeliveryTarget 已经把 current_thread 排除——
  排调度时只能给具体 target。
`);

section("完成", "课 8 实测结束");
