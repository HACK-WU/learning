// 课 5 · 知识点 3：控制流分析与穷尽性检查

type OrderStatus = "pending" | "paid" | "refunded";

// 兜底函数：参数类型是 never，意味着「不该有值能传进来」
function assertNever(value: never): never {
  throw new Error(`unexpected value: ${String(value)}`);
}

// ① 分支完整 —— default 里的 status 是 never，传得进去
function nextStatus(status: OrderStatus): OrderStatus {
  switch (status) {
    case "pending":
      return "paid";
    case "paid":
      return "refunded";
    case "refunded":
      return "refunded";
    default:
      return assertNever(status);
  }
}

// ② 另一种写法：用 never 类型的变量兜底
function label(status: OrderStatus): string {
  switch (status) {
    case "pending":
      return "PENDING";
    case "paid":
      return "PAID";
    case "refunded":
      return "REFUNDED";
    default: {
      const exhaustive: never = status;
      return exhaustive;
    }
  }
}

// ③ 控制流分析：赋值之后类型跟着变
function flow(): void {
  let value: string | number = "start";
  console.log(value.toUpperCase()); // ✅ 此刻是 string
  value = 42;
  console.log(value.toFixed(2)); // ✅ 此刻是 number
}

console.log(nextStatus("pending"));
console.log(label("paid"));
flow();
