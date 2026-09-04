// 课 4 · 知识点 3：边界探测（enum 的安全性与名义性）

enum Num {
  A,
  B,
}

// A：数字 enum 接受任意 number 吗？
const n1: Num = 42;
const n2: Num = Num.A;

// B：字符串 enum 接受裸字符串吗？
enum Str {
  X = "x",
}
const s1: Str = "x";
const s2: Str = Str.X;

// C：两个不同的 enum 之间能互相赋值吗？
enum Other {
  Y = "x",
}
const cross: Str = Other.Y;

// D：const enum
const enum ConstEnum {
  P = "p",
}
const c: ConstEnum = ConstEnum.P;

console.log(n1, n2, s1, s2, cross, c);
