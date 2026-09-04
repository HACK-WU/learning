// 课 5 · 知识点 2：边界探测（守卫的能力与责任）

interface Order {
  id: string;
  amount: number;
}

// A：普通 boolean 函数不能收窄
function checkOrder(value: unknown): boolean {
  return typeof value === "object" && value !== null;
}
function f1(value: unknown): void {
  if (checkOrder(value)) {
    console.log(value.id); // ❓ 收窄了吗
  }
}

// B：说谎的守卫 —— 编译器不检查你的实现，只检查返回类型
function isLyingOrder(value: unknown): value is Order {
  return true; // 永远返回 true
}
function f2(value: unknown): void {
  if (isLyingOrder(value)) {
    console.log(value.amount.toFixed(2)); // ✅ 编译通过，运行时可能炸
  }
}

// C：断言函数写成箭头函数并赋给变量
const assertOrderArrow = (value: unknown): asserts value is Order => {
  if (!isLyingOrder(value)) throw new Error("not an order");
};
function f3(value: unknown): void {
  assertOrderArrow(value); // ❓ 能收窄吗
  console.log(value.id);
}

// D：断言函数不能返回值
function badAssert(value: unknown): asserts value is Order {
  return; // ❓ 断言函数能 return 值吗
}

// E：守卫可以收窄联合中的一部分
type Shape = { kind: "circle"; radius: number } | { kind: "square"; size: number };
function isCircle(shape: Shape): shape is { kind: "circle"; radius: number } {
  return shape.kind === "circle";
}
function f4(shape: Shape): number {
  if (isCircle(shape)) return shape.radius;
  return shape.size;
}

console.log(f1, f2, f3, badAssert, f4);
