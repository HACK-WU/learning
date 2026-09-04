// 课 9 · 知识点 1：边界探测 —— 映射类型丢了什么、留下了什么

interface Order {
  id: string;
  amount: number;
}
type MyPick<T, K extends keyof T> = { [P in K]: T[P] };
type MyPartial<T> = { [K in keyof T]?: T[K] };

// A：挑不存在的键
type Bad = MyPick<Order, "nmae">;

// B：映射是「浅层」的 —— 嵌套对象不受影响
interface Nested {
  meta: { tags: string[] };
}
const shallow: MyPartial<Nested> = {};
shallow.meta?.tags.push("x"); // 需要可选链（meta 可选了）
const deep: MyPartial<Nested> = { meta: { tags: [] } };
deep.meta?.tags.push("y"); // 里层的 tags 仍是 string[]，没被 Partial 变成可选

// C：用 as + never 过滤掉一部分键
type OnlyStringKeys<T> = {
  [K in keyof T as T[K] extends string ? K : never]: T[K];
};
type StringOnly = OnlyStringKeys<{ id: string; amount: number }>; // { id: string }
const s: StringOnly = { id: "o1" };
// const s2: StringOnly = { id: "o1", amount: 1 };   // ❌ amount 被过滤掉了

// D：映射类型会不会丢掉索引签名？
interface WithIndex {
  [key: string]: number;
  fixed: number;
}
type Mapped = Copy<WithIndex>;
const m: Mapped = { fixed: 1, extra: 2 }; // ❓ 索引签名还在吗

type Copy<T> = { [K in keyof T]: T[K] };

console.log(shallow, deep, s, m);
