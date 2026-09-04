// 课 4 · 第四幕回扣：四道防线（预期报错，对照第一幕的静默穿透）

type OrderStatus = "pending" | "paid" | "refunded";

type Order =
  | { status: "pending"; id: string; amount: number }
  | { status: "paid"; id: string; amount: number; paidAt: string }
  | { status: "refunded"; id: string; amount: number; refundedAt: string };

// ① 拼错 —— 第一幕里静默穿透了
const typo: OrderStatus = "pendng";

// ② 大小写不一致 —— 第一幕里静默穿透了
const wrongCase: OrderStatus = "PAID";

// ③ 中文状态 —— 第一幕里静默穿透了
const chinese: OrderStatus = "已付款";

// ④ 判别式联合：不先判断 status，就访问别的分支才有的字段
function wrongAccess(order: Order): string {
  return order.paidAt;
}

// ⑤ 外部字符串不校验就当状态用
declare const rawFromApi: string;
const unvalidated: OrderStatus = rawFromApi;

console.log(typo, wrongCase, chinese, wrongAccess, unvalidated);
