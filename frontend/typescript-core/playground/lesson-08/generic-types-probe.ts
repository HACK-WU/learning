// 课 8 · 知识点 3：边界探测 —— 类型参数的规则

// A：没有默认值又没传参数
interface Box<T> {
  value: T;
}
const missing: Box = { value: 1 };

// B：有默认值，可以省略
interface Paged<T = string> {
  items: T[];
}
const ok: Paged = { items: ["a"] };

// C：违反约束
interface Numeric<T extends number> {
  value: T;
}
const bad: Numeric<string> = { value: "x" };

// D：泛型接口描述函数类型
interface Mapper<T, U> {
  (input: T): U;
}
const good: Mapper<string, number> = (s) => s.length;
const badMapper: Mapper<string, number> = (s) => s;

// E：同一泛型的不同实例互不兼容
const stringBox: Box<string> = { value: "a" };
const numberBox: Box<number> = stringBox;

console.log(missing, ok, bad, good, badMapper, numberBox);
