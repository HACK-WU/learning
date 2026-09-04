// 课 8 · 第四幕：把订单工具函数库改成泛型版

interface Order {
  id: string;
  amount: number;
  status: "pending" | "paid" | "refunded";
}

// ① 取第一个元素 —— 不用 any，类型信息完整保留
function first<T>(list: readonly T[]): T {
  if (list.length === 0) throw new Error("empty list");
  return list[0];
}

// ② 按 key 批量取值 —— key 拼错会被当场拦住
function pluck<T, K extends keyof T>(list: readonly T[], key: K): T[K][] {
  return list.map((item) => item[key]);
}

// ③ API 响应包装 —— 一份模具适配所有数据
interface ApiResponse<T> {
  code: number;
  message: string;
  data: T;
}
function ok<T>(data: T): ApiResponse<T> {
  return { code: 0, message: "ok", data };
}

const orders: Order[] = [
  { id: "o1", amount: 100, status: "paid" },
  { id: "g1", amount: 80, status: "pending" },
];

const head = first(orders); // Order（不是 any）
const ids = pluck(orders, "id"); // string[]
const amounts = pluck(orders, "amount"); // number[]
const response = ok(orders); // ApiResponse<Order[]>

console.log("head.id        =", head.id);
console.log("ids            =", ids);
console.log("amounts        =", amounts);
console.log("response       =", response.code, response.data.length);
console.log("total          =", amounts.reduce((a, b) => a + b, 0));
