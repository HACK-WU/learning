// 课 7 · 知识点 2：边界探测 —— abstract 与 implements 各拦什么

abstract class Base {
  abstract required(): void;
  optional(): void {
    console.log("default impl");
  }
}

interface Shape {
  area(): number;
}

// A：直接实例化抽象类
const b = new Base();

// B：子类忘了实现抽象方法
class Missing extends Base {}

// C：implements 了接口却没实现方法
class BadShape implements Shape {}

// D：正确写法 —— 继承抽象类 + 实现接口
class Good extends Base implements Shape {
  required(): void {}
  area(): number {
    return 0;
  }
}

// E：implements 只检查实例形状，静态成员管不着
interface Creatable {
  create(): void;
}
class WithStatics implements Creatable {
  static version = "1.0";
  create(): void {}
}

console.log(b, Missing, BadShape, new Good(), WithStatics.version);
