// 课 7 · 知识点 2：抽象类与 implements

// 接口：只描述"实例长什么样"，不管实现
interface Payable {
  id: string;
  total(): number;
}

// 抽象类：半成品 —— 既有实现，也规定子类必须做的事
abstract class Order {
  constructor(
    public id: string,
    public amount: number,
  ) {}

  // 已实现的方法：所有子类共享
  describe(): string {
    return `${this.id} -> ${this.total()}`;
  }

  // 抽象方法：子类必须实现，否则编译不过
  abstract total(): number;
}

class NormalOrder extends Order {
  total(): number {
    return this.amount;
  }
}

// 既继承抽象类，又声明自己符合 Payable 接口
class GroupOrder extends Order implements Payable {
  total(): number {
    return this.amount * 0.8;
  }
}

const orders: Order[] = [new NormalOrder("o1", 100), new GroupOrder("g1", 100)];
for (const order of orders) {
  console.log(order.describe());
}
