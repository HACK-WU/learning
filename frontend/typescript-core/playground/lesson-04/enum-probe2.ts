// 课 4 · 补测：enum 与数字的边界（变量 vs 字面量）

enum Num {
  A,
  B,
}

// A：字面量 42 —— 已实测报错 TS2322
// B：number 类型的变量呢？
declare const someNumber: number;
const fromVariable: Num = someNumber;

// C：const enum 的产物
const enum ConstEnum {
  P = "p",
  Q = "q",
}
const c: ConstEnum = ConstEnum.P;

console.log(fromVariable, c);
