/**
 * 调用运行时（invocation runtime）· 生命周期 + 幂等 + 账本
 *
 * 知识点覆盖：课 11「Invocation 生命周期」「授权与幂等」「执行账本」「用量与预算」
 *
 * 一句提醒：本文件是"进程内 registry"，仅用于演示。真实系统要把它换成
 * 数据库表，否则多副本部署时幂等失效。
 */
import { randomUUID, createHash } from "node:crypto";

export type InvocationStatus =
  | "pending"
  | "running"
  | "waiting_approval"   // 挂起等人工：非终态，但"别再等它"
  | "succeeded"
  | "rejected"
  | "failed";

export interface Ledger {
  invocationId: string;
  requestId: string;
  status: InvocationStatus;
  startedAt: string;
  finishedAt?: string;
  /** 增量可累加量：每轮累积，不适合直接覆盖 */
  usage: { inputTokens: number; outputTokens: number; toolCalls: number };
  /** 终态量：只在意最后结果 */
  outcome?: { sql?: string; rows?: number };
  error?: string;
}

/** 幂等键：同 requestId 同输入 → 返回旧结果；同 requestId 异输入 → 冲突 */
interface IdempotencyRecord {
  fingerprint: string;
  ledgerId: string;
}

export class InvocationRuntime {
  private ledgers = new Map<string, Ledger>();
  private byRequest = new Map<string, IdempotencyRecord>();

  /** 第一步：开始。create 必须最先调用，拿到 id 才能记后续 */
  create(requestId: string, payload: unknown): { ledger: Ledger; duplicated: boolean } {
    const fingerprint = fingerprintOf(payload);
    const existing = this.byRequest.get(requestId);

    if (existing) {
      if (existing.fingerprint !== fingerprint) {
        throw new Error(`requestId 冲突：${requestId} 已用于不同输入（同键异输入必须拒绝）`);
      }
      const ledger = this.ledgers.get(existing.ledgerId)!;
      return { ledger, duplicated: true };
    }

    const ledger: Ledger = {
      invocationId: randomUUID(),
      requestId,
      status: "pending",
      startedAt: new Date().toISOString(),
      usage: { inputTokens: 0, outputTokens: 0, toolCalls: 0 },
    };
    this.ledgers.set(ledger.invocationId, ledger);
    this.byRequest.set(requestId, { fingerprint, ledgerId: ledger.invocationId });
    return { ledger, duplicated: false };
  }

  /** 第二步：过程中增量累加（可以多次调用） */
  addUsage(id: string, delta: Partial<Ledger["usage"]>): void {
    const l = this.require(id);
    l.usage.inputTokens += delta.inputTokens ?? 0;
    l.usage.outputTokens += delta.outputTokens ?? 0;
    l.usage.toolCalls += delta.toolCalls ?? 0;
  }

  /** 第三步：落定状态。成功、拒绝、异常都必须落，否则留下永远 RUNNING 的僵尸 */
  finish(id: string, status: Exclude<InvocationStatus, "pending" | "running">, outcome?: Ledger["outcome"], error?: string): void {
    const l = this.require(id);
    if (l.finishedAt) return;      // 终态幂等：重复 finish 不覆盖首次结论
    l.status = status;
    l.finishedAt = new Date().toISOString();
    if (outcome) l.outcome = outcome;
    if (error) l.error = error;
  }

  get(id: string): Ledger | undefined {
    return this.ledgers.get(id);
  }
  findByRequest(requestId: string): Ledger | undefined {
    const rec = this.byRequest.get(requestId);
    return rec ? this.ledgers.get(rec.ledgerId) : undefined;
  }

  private require(id: string): Ledger {
    const l = this.ledgers.get(id);
    if (!l) throw new Error(`未知 invocation：${id}`);
    return l;
  }
}

/** 预算护栏：fail-closed——没有用量记录时按"已超限"处理，宁可不跑 */
export class BudgetGuard {
  private limitTokens: number;
  constructor(limitTokens: number) {
    this.limitTokens = limitTokens;
  }
  check(ledger: Ledger): { ok: boolean; reason?: string } {
    const used = ledger.usage.inputTokens + ledger.usage.outputTokens;
    if (!Number.isFinite(used)) return { ok: false, reason: "用量记录异常，按 fail-closed 拒绝" };
    if (used >= this.limitTokens) {
      return { ok: false, reason: `token 预算已用尽（${used}/${this.limitTokens}）` };
    }
    return { ok: true };
  }
}

function fingerprintOf(payload: unknown): string {
  return createHash("sha256").update(JSON.stringify(payload ?? null)).digest("hex");
}
