// 课 5 · 第四幕回扣：防线与破口（预期报错 + 一处运行时崩溃）

type OrderStatus = "pending" | "paid" | "refunded";

interface Order {
  id: string;
  amount: number;
  status: OrderStatus;
}

function assertNever(value: never): never {
  throw new Error(`unhandled status: ${String(value)}`);
}

// ① 漏了 refunded 分支 —— 穷尽性检查立刻报错
function nextMissing(status: OrderStatus): OrderStatus {
  switch (status) {
    case "pending":
      return "paid";
    case "paid":
      return "refunded";
    // 漏了 refunded
    default:
      return assertNever(status); // ❌ 报错
  }
}

// ② 不用守卫就直接用外部数据 —— 编译器不让
function useRaw(raw: unknown): number {
  return raw.amount; // ❌ 报错
}

// ③ 说谎的守卫：编译通过，运行时炸
function lyingGuard(value: unknown): value is Order {
  return true; // 永远放行
}
function useLying(raw: unknown): number {
  if (lyingGuard(raw)) return raw.amount; // ✅ 编译通过（守卫在说谎）
  return 0;
}

try {
  console.log("useLying(null) =", useLying(null));
} catch (e) {
  console.log("useLying(null) ->", (e as Error).message);
}

console.log(nextMissing, useRaw);
