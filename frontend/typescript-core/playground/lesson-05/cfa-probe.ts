// 课 5 · 知识点 3：边界探测 —— 漏分支会不会报错？闭包里还收窄吗？

type OrderStatus = "pending" | "paid" | "refunded";

function assertNever(value: never): never {
  throw new Error(`unexpected value: ${String(value)}`);
}

// A：漏了 refunded 分支 —— default 里的 status 不是 never
function nextMissing(status: OrderStatus): OrderStatus {
  switch (status) {
    case "pending":
      return "paid";
    case "paid":
      return "refunded";
    default:
      return assertNever(status); // ❓ 会报错吗
  }
}

// B：never 变量兜底法，同样漏分支
function labelMissing(status: OrderStatus): string {
  switch (status) {
    case "pending":
      return "PENDING";
    case "paid":
      return "PAID";
    default: {
      const exhaustive: never = status; // ❓ 会报错吗
      return exhaustive;
    }
  }
}

// C：闭包里的收窄 —— const 保留
function withConst(): void {
  const value: string | number = "hi";
  if (typeof value === "string") {
    setTimeout(() => console.log(value.toUpperCase()), 0); // ❓ const 保留收窄吗
  }
}

// D：闭包里的收窄 —— let 重置
function withLet(): void {
  let value: string | number = "hi";
  if (typeof value === "string") {
    setTimeout(() => console.log(value.toUpperCase()), 0); // ❓ let 还收窄吗
  }
}

// E：参数（类似 let）在闭包里
function withParam(value: string | number): void {
  if (typeof value === "string") {
    setTimeout(() => console.log(value.toUpperCase()), 0); // ❓ 参数保留收窄吗
  }
}

console.log(nextMissing, labelMissing, withConst, withLet, withParam);
