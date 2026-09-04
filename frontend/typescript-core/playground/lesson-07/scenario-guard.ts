// 课 7 · 第四幕回扣：四道防线 + 一个逃逸口

interface Payable {
  id: string;
  total(): number;
}

abstract class Order implements Payable {
  private readonly brand = "order";
  constructor(
    public readonly id: string,
    protected amount: number,
  ) {}
  abstract total(): number;
  kind(): string {
    return this.brand;
  }
}

class NormalOrder extends Order {
  total(): number {
    return this.amount;
  }
}

class Coupon {
  private readonly brand = "coupon";
  constructor(
    public readonly id: string,
    public amount: number,
  ) {}
  total(): number {
    return this.amount;
  }
  kind(): string {
    return this.brand;
  }
}

function applyTo(order: Order): string {
  return `applied: ${order.total().toFixed(2)}`;
}

const order = new NormalOrder("o1", 100);

// ① 事故一：外部改内部字段
order.amount = -999;

// ② 事故二：子类忘了实现抽象方法
class Broken extends Order {}

// ③ 事故三：优惠券被当成订单传进去
applyTo(new Coupon("c1", 20));

// ④ 逃逸口：方括号访问能绕过 private / protected
order["amount"] = -999; // ⚠️ 编译通过

console.log(order, applyTo);
