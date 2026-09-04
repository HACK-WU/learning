// 课 5 · 知识点 2：自定义类型守卫与断言函数

interface Order {
  id: string;
  amount: number;
}

// ① 类型守卫：返回值写成 `value is Order`，编译器才认这个结论
function isOrder(value: unknown): value is Order {
  if (typeof value !== "object" || value === null) return false;
  const candidate = value as Record<string, unknown>;
  return typeof candidate.id === "string" && typeof candidate.amount === "number";
}

function processOrder(input: unknown): string {
  if (isOrder(input)) {
    return `order ${input.id}: ${input.amount}`; // ✅ input 收窄为 Order
  }
  return "not an order";
}

// ② 断言函数：不满足就抛错，调用之后的代码全部收窄
function assertOrder(value: unknown): asserts value is Order {
  if (!isOrder(value)) throw new Error("not an order");
}

function handle(input: unknown): string {
  assertOrder(input);
  return `${input.id} -> ${input.amount}`; // ✅ 从这一行起，input 都是 Order
}

console.log(processOrder({ id: "o1", amount: 99 }));
console.log(processOrder("hello"));
console.log(handle({ id: "o2", amount: 199 }));
try {
  handle(null);
} catch (e) {
  console.log("handle(null) ->", (e as Error).message);
}
