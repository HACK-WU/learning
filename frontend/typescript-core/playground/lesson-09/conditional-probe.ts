// 课 9 · 知识点 2：边界探测 —— 分发的坑

// A：经典陷阱 —— 判断「是不是 never」
type IsNever<T> = T extends never ? true : false;
type A1 = IsNever<never>; // ❓ 期望 true
const checkA1: A1 = true; // 如果 A1 是 never，这行会报错

// B：正确写法 —— 用元组包起来阻止分发
type IsNeverCorrect<T> = [T] extends [never] ? true : false;
type A2 = IsNeverCorrect<never>; // true
const checkA2: A2 = true;

// C：分发导致联合被逐个处理
type Wrap<T extends string | number> = T extends string ? `s:${T}` : `o:${T}`;
type C1 = Wrap<"a" | 1>; // "s:a" | "o:1"
const checkC1: C1 = "s:a";
const checkC1b: C1 = "o:1";

// D：boolean 也会被分发（boolean = true | false）
type BoolWrap<T> = T extends true ? "T" : "F";
type D1 = BoolWrap<boolean>; // "T" | "F"（不是 "F"）
const checkD1: D1 = "T";

// E：infer 只能出现在条件类型的 extends 右侧
type Bad<T> = infer U; // ❌ 语法错误

console.log(checkA1, checkA2, checkC1, checkC1b, checkD1);
