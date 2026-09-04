// 课 9 · 知识点 1：映射类型 —— 类型的 map

interface Order {
  id: string;
  amount: number;
  status: "pending" | "paid" | "refunded";
}

// ① 最基础的映射：原样复制一份
type Copy<T> = { [K in keyof T]: T[K] };

// ② 全部变可选 —— 手写 Partial
type MyPartial<T> = { [K in keyof T]?: T[K] };
type OrderDraft = MyPartial<Order>;
const draft: OrderDraft = { id: "o1" }; // ✅ 只填一部分

// ③ 去掉可选（-?）与去掉只读（-readonly）
type MyRequired<T> = { [K in keyof T]-?: T[K] };
type MyMutable<T> = { -readonly [K in keyof T]: T[K] };
const full: MyRequired<OrderDraft> = { id: "o1", amount: 100, status: "pending" };
const editable: MyMutable<Readonly<Order>> = { id: "o1", amount: 100, status: "paid" };

// ④ 挑出部分键 —— 手写 Pick
type MyPick<T, K extends keyof T> = { [P in K]: T[P] };
type OrderSummary = MyPick<Order, "id" | "amount">;
const summary: OrderSummary = { id: "o1", amount: 100 };

// ⑤ 键重映射：用 as 给键改名
type Getters<T> = {
  [K in keyof T as `get${Capitalize<string & K>}`]: () => T[K];
};
type OrderGetters = Getters<Order>; // getId / getAmount / getStatus

// ⑥ 用键的联合直接造对象类型 —— 手写 Record
type MyRecord<K extends keyof any, V> = { [P in K]: V };
type StatusLabel = MyRecord<Order["status"], string>;
const labels: StatusLabel = { pending: "PENDING", paid: "PAID", refunded: "REFUNDED" };

console.log(draft, full, editable, summary, labels);
