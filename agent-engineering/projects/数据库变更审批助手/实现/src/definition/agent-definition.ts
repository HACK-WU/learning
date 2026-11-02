/**
 * 定义面（declaration）· 类型与运行时构造
 *
 * 知识点覆盖：课 4「一份定义包含什么」「定义与实例分离」
 *
 * 这份文件只做一件事：把「一份 Agent 定义」翻译成内存中的对象，并保证
 * 定义本身是纯数据（可序列化、可版本化），运行时对象由它派生。
 */
import { z } from "zod";

/** 定义 schema：六组要素里本项目实际用到的部分 */
export const AgentDefinitionSchema = z.object({
  key: z.string(),                       // 身份：唯一键，供引用与路由
  name: z.string(),
  version: z.number().int().positive(),

  // 说话：模型人格与规则（提示词本身就是数据，改它不必改代码）
  prompt: z.string(),

  // 模型：只存"要哪个"，不存客户端实例
  model: z.object({
    provider: z.literal("fake"),         // 本项目用桩模型，聚焦链路而非模型能力
    temperature: z.number().min(0).max(2).default(0),
  }),

  // 能力：工具清单（名字引用，不含实现——实现由 provider 提供）
  tools: z.array(z.string()),

  // 能力：策略（哪些工具需要审批）
  policies: z
    .object({
      requireApprovalFor: z.array(z.string()).default([]),
    })
    .default({ requireApprovalFor: [] }),

  // 协作：本项目是单 Agent，显式留空，防止"看起来支持但其实没实现"
  collaborators: z.array(z.string()).default([]),
});

export type AgentDefinition = z.infer<typeof AgentDefinitionSchema>;

/**
 * 定义 → 运行时对象。
 *
 * 关键：返回的是"从定义派生的只读视图"，不是定义本身。
 * 这样运行时无法回写定义（避免"跑一次就改了配置"）。
 */
export function toRuntime(def: AgentDefinition): Readonly<AgentDefinition> {
  return Object.freeze({ ...def, tools: [...def.tools] });
}

/**
 * 校验前置：在保存/发布前拦下结构性错误。
 *
 * 返回值是"问题清单"而不是抛异常——校验器要能一次报出全部问题，
 * 而不是让用户改一个、再跑一次、再发现下一个。
 */
export function validateDefinition(raw: unknown): string[] {
  const parsed = AgentDefinitionSchema.safeParse(raw);
  if (!parsed.success) {
    return parsed.error.issues.map((i) => `${i.path.join(".") || "(root)"}: ${i.message}`);
  }

  const def = parsed.data;
  const problems: string[] = [];

  // 组合冲突：审批策略里点了不存在的工具
  for (const t of def.policies.requireApprovalFor) {
    if (!def.tools.includes(t)) {
      problems.push(`policies.requireApprovalFor 引用了未声明的工具：「${t}」`);
    }
  }

  // 图级：本项目是单 Agent，却声明了协作者 → 配置与实现不一致
  if (def.collaborators.length > 0) {
    problems.push(`collaborators 非空（${def.collaborators.join(", ")}），但本项目未实现多 Agent 协作`);
  }

  return problems;
}
