// ============ SDK v1：对外只暴露必要的类型 ============

/**
 * 对外的入参类型。
 * 注意 currency 是「可选的」——这给未来留下了加字段的空间。
 */
export interface CreateOrderInput {
  id: string;
  amount: number;
  currency?: string;
}

/** 对外的返回值类型 */
export interface Order {
  id: string;
  amount: number;
  status: "pending" | "paid" | "refunded";
}

// 内部实现细节：不导出。
// 但 .d.ts 是「按使用推导」的 —— 如果某个对外签名用到了它，
// 即使没写 export，TS 也会把它写进 .d.ts（见 dist/index.d.ts）。
interface InternalAudit {
  at: string;
  by: string;
}

export function createOrder(input: CreateOrderInput): Order {
  const audit: InternalAudit = { at: new Date().toISOString(), by: "system" };
  void audit;
  return {
    id: input.id,
    amount: input.amount,
    status: "pending",
  };
}
