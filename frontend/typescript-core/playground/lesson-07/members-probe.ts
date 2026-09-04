// 课 7 · 知识点 1：边界探测 —— 四个修饰符到底拦住了什么

class Vault {
  public open = 1;
  private secret = "key";
  protected internal = 42;
  readonly fixed = "ro";
}

const v = new Vault();
console.log(v.open); // ✅ public 谁都能访问

// A：private 成员在类外访问
console.log(v.secret);

// B：protected 成员在类外访问
console.log(v.internal);

// C：readonly 成员被改
v.fixed = "new";

// D：方括号访问 —— 能绕过 private 吗？
console.log(v["secret"]);

// E：参数属性生成的字段同样受修饰符约束
class Param {
  constructor(
    public a: number,
    private b: number,
  ) {}
}
const p = new Param(1, 2);
console.log(p.a);
console.log(p.b);

// F：#private（JS 硬私有）—— 语法层面就访问不了
class Hard {
  #hidden = "secret";
  reveal(): string {
    return this.#hidden;
  }
}
const h = new Hard();
console.log(h.reveal());
console.log(h.#hidden);
