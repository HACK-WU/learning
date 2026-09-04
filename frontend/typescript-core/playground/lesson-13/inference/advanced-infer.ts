// ============ 知识点 2：高级推断技巧 ============

// 精确类型相等判定（type-testing 的通用惯用法）。
// 直接用 `X extends Y` 不够：never、any、联合的父子类系都会蒙混过关。
// 这个写法利用了「条件类型对函数签名的同一性判定」来做到真正的相等。
type Equals<X, Y> =
  (<T>() => T extends X ? 1 : 2) extends (<T>() => T extends Y ? 1 : 2) ? true : false;
type Expect<T extends true> = T;

// ① 多次 infer：一次把参数、返回值全掏出来
type FunctionParts<F> = F extends (a: infer A, b: infer B) => infer R ? [A, B, R] : never;
type _1 = Expect<Equals<FunctionParts<(a: string, b: number) => boolean>, [string, number, boolean]>>;

// ② ⚠️ 陷阱：函数重载只推断「最后一个」签名
interface Overloaded {
  (x: string): number;
  (x: number): string;
}
// 只拿到 (x: number) => string 这一条 —— 前面那条被吃了
type _2 = Expect<Equals<Parameters<Overloaded>, [x: number]>>;
type _3 = Expect<Equals<ReturnType<Overloaded>, string>>;

// ③ infer ... extends（TS 4.7 引入）：推断的同时加约束
type ParseInt<S extends string> = S extends `${infer N extends number}` ? N : never;
type _4 = Expect<Equals<ParseInt<"100">, 100>>;
type _5 = Expect<Equals<ParseInt<"abc">, never>>;

// ④ 变元组推断（TS 4.0 引入）：infer 可以出现在元组的任意位置
type Concat<T extends unknown[], U extends unknown[]> = [...T, ...U];
type Last<T extends unknown[]> = T extends [...infer _Rest, infer L] ? L : never;
type DropFirst<T extends unknown[]> = T extends [infer _First, ...infer Rest] ? Rest : never;
type Init<T extends unknown[]> = T extends [...infer Rest, infer _Last] ? Rest : never;
type _6 = Expect<Equals<Concat<[1, 2], [3, 4]>, [1, 2, 3, 4]>>;
type _7 = Expect<Equals<Last<[1, 2, 3]>, 3>>;
type _8 = Expect<Equals<DropFirst<[1, 2, 3]>, [2, 3]>>;
type _9 = Expect<Equals<Init<[1, 2, 3]>, [1, 2]>>;

// ⑤ NoInfer<T>（TS 5.4 引入）：告诉 TS「这个位置别参与推断」
declare function createStreetLightPlain<C extends string>(colors: C[], defaultColor?: C): void;
declare function createStreetLightNoInfer<C extends string>(
  colors: C[],
  defaultColor?: NoInfer<C>,
): void;

// 没有 NoInfer：C 被两个参数「一起」推出来，"blue" 混进颜色联合里，静默通过
createStreetLightPlain(["red", "yellow", "green"], "blue"); // ✅ 通过了（但这是你想要的吗）

// 加了 NoInfer：C 只由第一个参数决定，第二个参数只能「跟从」
// @ts-expect-error "blue" 不在 C 里 → 报错（这才是你要的）
createStreetLightNoInfer(["red", "yellow", "green"], "blue");
createStreetLightNoInfer(["red", "yellow", "green"], "red"); // ✅ 合法值照常通过

// ⑥ const 类型参数（TS 5.0 引入）：让字面量推断成为默认，不用再写 as const
type HasNames = { names: readonly string[] };
declare function getNamesPlain<T extends HasNames>(arg: T): T["names"];
declare function getNamesConst<const T extends HasNames>(arg: T): T["names"];

// 普通泛型：推断成 string[]，字面量信息丢了
const namesPlain = getNamesPlain({ names: ["Alice", "Bob"] });
// 若 namesPlain 是 readonly ["Alice","Bob"]，赋给 string[] 会因 readonly 而失败
export const np: string[] = namesPlain;

// const 类型参数：推断成 readonly ["Alice", "Bob"]
const namesConst = getNamesConst({ names: ["Alice", "Bob"] });
// 若 namesConst 是 string[]，赋给 readonly ["Alice","Bob"] 会因缺少字面量信息而失败
export const nc: readonly ["Alice", "Bob"] = namesConst;
