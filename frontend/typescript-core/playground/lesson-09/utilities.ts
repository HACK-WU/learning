// 课 9 · 知识点 3：内置工具类型全景与手写实现

interface Order {
  id: string;
  amount: number;
  status: "pending" | "paid";
  note?: string;
}

// ── 第一组：改修饰符（映射类型）────────────────────────
type MyPartial<T> = { [K in keyof T]?: T[K] };
type MyRequired<T> = { [K in keyof T]-?: T[K] };
type MyReadonly<T> = { readonly [K in keyof T]: T[K] };

// ── 第二组：挑键（映射 + 约束）────────────────────────
type MyPick<T, K extends keyof T> = { [P in K]: T[P] };
type MyOmit<T, K extends keyof any> = MyPick<T, Exclude<keyof T, K>>;

// ── 第三组：造对象 ────────────────────────────────────
type MyRecord<K extends keyof any, V> = { [P in K]: V };

// ── 第四组：联合运算（条件类型 + 分发）─────────────────
type MyExclude<T, U> = T extends U ? never : T;
type MyExtract<T, U> = T extends U ? T : never;
type MyNonNullable<T> = T extends null | undefined ? never : T;

// ── 第五组：从函数类型里挖 ─────────────────────────────
type MyReturnType<T extends (...args: any[]) => any> = T extends (...args: any[]) => infer R ? R : never;
type MyParameters<T extends (...args: any[]) => any> = T extends (...args: infer P) => any ? P : never;
type MyAwaited<T> = T extends Promise<infer U> ? MyAwaited<U> : T; // 递归：剥掉所有层 Promise

// ── 逐个用一遍 ────────────────────────────────────────
const draft: MyPartial<Order> = { id: "o1" };
const complete: MyRequired<MyPartial<Order>> = { id: "o1", amount: 100, status: "pending", note: "" };
const frozen: MyReadonly<Order> = { id: "o1", amount: 100, status: "paid" };
const summary: MyPick<Order, "id" | "amount"> = { id: "o1", amount: 100 };
const withoutNote: MyOmit<Order, "note"> = { id: "o1", amount: 100, status: "pending" };
const labels: MyRecord<Order["status"], string> = { pending: "PENDING", paid: "PAID" };
const statuses: MyExclude<Order["status"], "paid"> = "pending";
const paidOnly: MyExtract<Order["status"], "paid"> = "paid";
const clean: MyNonNullable<string | null> = "text";

function createOrder(id: string, amount: number): Order {
  return { id, amount, status: "pending" };
}
async function loadOrder(): Promise<Order> {
  return createOrder("o1", 100);
}
const created: MyReturnType<typeof createOrder> = { id: "o1", amount: 100, status: "pending" };
const args: MyParameters<typeof createOrder> = ["o1", 100];
const loaded: MyAwaited<ReturnType<typeof loadOrder>> = { id: "o1", amount: 100, status: "paid" };

console.log(draft, complete, frozen, summary, withoutNote, labels);
console.log(statuses, paidOnly, clean, created, args, loaded);
