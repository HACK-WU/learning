// 课 7 · 知识点 3：边界探测 —— 类的兼容什么时候会被破坏

// A：都有 private 成员，但来自不同的类声明
class WithPrivateA {
  constructor(
    public x: number,
    private tag: string,
  ) {}
}
class WithPrivateB {
  constructor(
    public x: number,
    private tag: string,
  ) {}
}
const a: WithPrivateA = new WithPrivateB(1, "t"); // ❓

// B：protected 同样会破坏兼容吗？
class ProtectedA {
  protected v = 1;
}
class ProtectedB {
  protected v = 1;
}
const b: ProtectedA = new ProtectedB(); // ❓

// C：只有 public 成员时，多一个属性没关系
class Loose {
  constructor(public x: number) {}
}
class Rich {
  constructor(
    public x: number,
    public y: number,
  ) {}
}
const c: Loose = new Rich(1, 2); // ✅

// D：子类赋给父类
class Parent {
  name = "p";
}
class Child extends Parent {
  age = 1;
}
const d: Parent = new Child(); // ✅

// E：父类赋给子类
const e: Child = new Parent(); // ❓ 缺 age

console.log(a, b, c, d, e);
