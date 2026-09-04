// ============ SDK v2：加了一个「必填」字段 ============
// 对 SDK 作者来说只是一行；对使用方来说是破坏性变更 —— 所有调用点都要改。

export interface CreateOrderInput {
  id: string;
  amount: number;
  currency?: string;
  customerId: string; // ← 新增，且是必填
}

export interface Order {
  id: string;
  amount: number;
  status: "pending" | "paid" | "refunded";
}

interface InternalAudit {
  at: string;
  by: string;
}

export function createOrder(input: CreateOrderInput): Order {
  const audit: InternalAudit = { at: new Date().toISOString(), by: input.customerId };
  void audit;
  return {
    id: input.id,
    amount: input.amount,
    status: "pending",
  };
}
