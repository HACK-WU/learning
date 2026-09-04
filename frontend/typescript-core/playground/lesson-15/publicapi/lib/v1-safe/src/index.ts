// ============ SDK v1.1：加的是「可选」字段 ============
// 同样加了一个字段，但它是可选的 —— 使用方不用改一行代码。

export interface CreateOrderInput {
  id: string;
  amount: number;
  currency?: string;
  customerId?: string; // ← 新增，但可选
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
  const audit: InternalAudit = { at: new Date().toISOString(), by: input.customerId ?? "anonymous" };
  void audit;
  return {
    id: input.id,
    amount: input.amount,
    status: "pending",
  };
}
