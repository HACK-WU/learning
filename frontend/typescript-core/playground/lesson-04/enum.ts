// 课 4 · 知识点 3：枚举 —— TS 里少数「编译后不会消失」的类型

// ① 数字 enum：值从 0 开始自动递增
enum OrderStatus {
  Pending, // 0
  Paid, // 1
  Refunded, // 2
}

// ② 字符串 enum：每个成员都要显式给值
enum Direction {
  Up = "UP",
  Down = "DOWN",
}

const s: OrderStatus = OrderStatus.Paid;
const d: Direction = Direction.Up;

// 数字 enum 有反向映射：OrderStatus[0] === "Pending"
console.log("s =", s, "d =", d);
console.log("OrderStatus[0] =", OrderStatus[0]);
