// 课 5 · 补测：typeof 的 null 盲区 / in 的收窄结果 / 断言函数能否返回值

// A：typeof 的盲区 —— null 的 typeof 也是 "object"
function g1(value: string[] | null): number {
  if (typeof value === "object") {
    return value.length; // ❓ 数组和 null 都匹配 "object"
  }
  return 0;
}

// B：in 用于未列出的属性，收窄出什么类型？
function g2(value: { a: number }): unknown {
  if ("b" in value) {
    const b: number = value.b; // ❓ b 是什么类型
    return b;
  }
  return value.a;
}

// C：断言函数能返回值吗？
interface Order {
  id: string;
  amount: number;
}
function badAssert(value: unknown): asserts value is Order {
  return false; // ❓
}

// D：真值检查把合法的 0 也排除（运行时行为）
function g3(count: number | undefined): number {
  if (count) return count;
  return 0;
}

console.log("g3(0) =", g3(0), "| g3(5) =", g3(5));
console.log(g1(["a"]), g2({ a: 1 }));
