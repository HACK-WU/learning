// 课 9 · 知识点 2：条件类型与 infer

// ① 类型层面的三元表达式
type IsString<T> = T extends string ? "yes" : "no";
type A1 = IsString<string>; // "yes"
type A2 = IsString<number>; // "no"

// ② 裸类型参数会「分发」：联合类型被拆开逐个计算
type ToArray<T> = T extends unknown ? T[] : never;
type B1 = ToArray<string | number>; // string[] | number[]  ← 分发了

// ③ 用 [T] 包起来可以阻止分发
type ToArrayNoDist<T> = [T] extends [unknown] ? T[] : never;
type B2 = ToArrayNoDist<string | number>; // (string | number)[]

// ④ infer：从类型结构里「挖」出一部分
type MyReturnType<T> = T extends (...args: any[]) => infer R ? R : never;
type C1 = MyReturnType<() => string>; // string

type ElementOf<T> = T extends (infer U)[] ? U : never;
type C2 = ElementOf<number[]>; // number

// ⑤ 分发最常见的用途：从联合里剔除成员
type MyExclude<T, U> = T extends U ? never : T;
type D1 = MyExclude<"a" | "b" | "c", "a">; // "b" | "c"

type MyExtract<T, U> = T extends U ? T : never;
type D2 = MyExtract<"a" | "b" | "c", "a" | "b">; // "a" | "b"

type MyNonNullable<T> = T extends null | undefined ? never : T;
type D3 = MyNonNullable<string | null | undefined>; // string

// 用赋值把类型"验证"出来（写错就会编译报错）
const checkA1: A1 = "yes";
const checkB2: B2 = ["x", 1];
const checkC1: C1 = "hello";
const checkC2: C2 = 42;
const checkD1: D1 = "b";
const checkD3: D3 = "text";

console.log(checkA1, checkB2, checkC1, checkC2, checkD1, checkD3);
