// 课 7 · 第一幕：JS 类里三件没人管的事

class Order {
  constructor(id, amount) {
    this.id = id;
    this.amount = amount; // 本该是内部数据，谁都能改
  }
  total() {
    return this.amount;
  }
}

class GroupOrder extends Order {
  total() {
    return this.amount * 0.8;
  }
}

// 事故一：内部字段被外部改掉
const g = new GroupOrder("o1", 100);
console.log("before   =", g.total());
g.amount = -999;
console.log("after    =", g.total()); // -799.2

// 事故二：子类忘了实现方法，静默继承父类的实现
class PreOrder extends Order {
  // 忘了写 total()，本该返回定金
}
console.log("preorder =", new PreOrder("o2", 100).total()); // 100，错的

// 事故三：形状一样的东西可以互换，换错了也没人知道
class Coupon {
  constructor(id, amount) {
    this.id = id;
    this.amount = amount;
  }
  total() {
    return this.amount;
  }
}
function applyTo(order) {
  return order.total();
}
console.log("coupon   =", applyTo(new Coupon("c1", 20))); // 优惠券被当订单用了
