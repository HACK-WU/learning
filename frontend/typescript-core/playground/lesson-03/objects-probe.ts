// 课 3 · 知识点 1：边界探测（预期报错，用来看清 interface 与 type 的能力边界）

// A：type 同名重复声明
type Dup = { x: number };
type Dup = { y: number };

// B：readonly 属性能改吗？
const ro: { readonly x: number } = { x: 1 };
ro.x = 2;

// C：可选属性显式赋 undefined（exactOptionalPropertyTypes 默认关吗？）
interface Opt {
  a?: number;
}
const o1: Opt = { a: undefined };

// D：{} 到底能接受什么？
const e1: {} = "hello";
const e2: {} = 42;
const e3: {} = null;
const e4: object = "hello";
const e5: object = { a: 1 };

// E：索引签名与具体属性共存：具体属性的类型必须服从索引签名
interface Mixed {
  id: string; // string 不服从下面的 number 索引签名
  [key: string]: number;
}

// F：interface 没有「给联合类型起名字」的语法（这是 type 的专属能力）
// 下面这行是非法语法，只能写成 type Id = string | number;
// interface NotPossible = string | number;

console.log(o1, e1, e2, e3, e4, e5, ro);
