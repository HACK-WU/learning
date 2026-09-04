// 课 9 · 知识点 3：类型层面的单元测试 —— 手写版与内置版等价吗？

interface Order {
  id: string;
  amount: number;
  status: "pending" | "paid";
}

type MyPartial<T> = { [K in keyof T]?: T[K] };
type MyRequired<T> = { [K in keyof T]-?: T[K] };
type MyReadonly<T> = { readonly [K in keyof T]: T[K] };
type MyPick<T, K extends keyof T> = { [P in K]: T[P] };
type MyOmit<T, K extends keyof any> = MyPick<T, Exclude<keyof T, K>>;
type MyRecord<K extends keyof any, V> = { [P in K]: V };
type MyExclude<T, U> = T extends U ? never : T;
type MyExtract<T, U> = T extends U ? T : never;
type MyNonNullable<T> = T extends null | undefined ? never : T;
type MyReturnType<T extends (...args: any[]) => any> = T extends (...args: any[]) => infer R ? R : never;
type MyParameters<T extends (...args: any[]) => any> = T extends (...args: infer P) => any ? P : never;
type MyAwaited<T> = T extends Promise<infer U> ? MyAwaited<U> : T;

// 双向可赋值 = 结构等价（简版严格相等）
type Equivalent<A, B> = [A] extends [B] ? ([B] extends [A] ? true : false) : false;

// 十二组对照；任何一组不等价，下面的 `= true` 就会编译报错
const t01: Equivalent<MyPartial<Order>, Partial<Order>> = true;
const t02: Equivalent<MyRequired<Order>, Required<Order>> = true;
const t03: Equivalent<MyReadonly<Order>, Readonly<Order>> = true;
const t04: Equivalent<MyPick<Order, "id">, Pick<Order, "id">> = true;
const t05: Equivalent<MyOmit<Order, "status">, Omit<Order, "status">> = true;
const t06: Equivalent<MyRecord<"a" | "b", number>, Record<"a" | "b", number>> = true;
const t07: Equivalent<MyExclude<"a" | "b", "a">, Exclude<"a" | "b", "a">> = true;
const t08: Equivalent<MyExtract<"a" | "b", "a">, Extract<"a" | "b", "a">> = true;
const t09: Equivalent<MyNonNullable<string | null>, NonNullable<string | null>> = true;
const t10: Equivalent<MyReturnType<() => Order>, ReturnType<() => Order>> = true;
const t11: Equivalent<MyParameters<(a: string) => void>, Parameters<(a: string) => void>> = true;
const t12: Equivalent<MyAwaited<Promise<Promise<Order>>>, Awaited<Promise<Promise<Order>>>> = true;

// 反例（预期报错，用来确认这个测试真的有效）
const f01: Equivalent<MyPartial<Order>, Order> = true; // ❌ 不等价

console.log(t01, t02, t03, t04, t05, t06, t07, t08, t09, t10, t11, t12, f01);
