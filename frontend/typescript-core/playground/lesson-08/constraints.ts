// 课 8 · 知识点 2：泛型约束与 keyof

interface Order {
  id: string;
  amount: number;
  status: string;
}

// ① keyof：把对象的键取出来，组成一个字面量联合
type OrderKeys = keyof Order; // "id" | "amount" | "status"
const k1: OrderKeys = "id";
const k2: OrderKeys = "amount";

// ② 索引访问类型：用键取出对应值的类型
type IdType = Order["id"]; // string
type AmountType = Order["amount"]; // number
const idValue: IdType = "o1";

// ③ 用 extends 约束类型参数：K 必须是 T 的键
function getField<T, K extends keyof T>(obj: T, key: K): T[K] {
  return obj[key];
}

const order: Order = { id: "o1", amount: 100, status: "paid" };
const id = getField(order, "id"); // string
const amount = getField(order, "amount"); // number
// getField(order, "nmae");   // ❌ 拼错会被拦住，见 constraints-probe.ts

// ④ 批量取值：第一幕那个 pluck 的泛型版
function pluck<T, K extends keyof T>(list: T[], key: K): T[K][] {
  return list.map((item) => item[key]);
}
const ids = pluck([order], "id"); // string[]
const amounts = pluck([order], "amount"); // number[]

// ⑤ 用 extends 约束「必须有某个形状」
interface HasId {
  id: string;
}
function logId<T extends HasId>(item: T): string {
  return item.id; // ✅ 因为 T 一定有 id
}

console.log(k1, k2, idValue, id, amount, ids, amounts, logId(order));
