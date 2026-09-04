// 另一种漏网：类型错了，但运行时「一切正常」
type OrderStatus = "paid" | "refunded";

function statusLabel(status: OrderStatus): string {
  return status.toUpperCase();
}

// ❌ 类型错误：拼写错了，但它是个合法字符串
//    运行时不崩，只是输出 PAYD —— 跑一百遍也发现不了
const status: OrderStatus = "payd";

console.log("status label =", statusLabel(status));
