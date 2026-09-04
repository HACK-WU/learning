// 课 5 · 第一幕：JS 里「判断过了」和「判断全了」都不受保护

// 场景一：switch 漏了分支 —— 静默返回 undefined
function nextStatus(status) {
  switch (status) {
    case "pending":
      return "paid";
    case "paid":
      return "refunded";
    // 忘了 refunded 分支
  }
}
console.log("nextStatus(refunded) =", nextStatus("refunded"));

// 场景二：判断不全 —— 运行时炸
function describeResult(result) {
  if (typeof result === "string") return "error: " + result;
  return "ok: " + result.amount;
}
console.log(describeResult({ amount: 99 }));
console.log(describeResult("timeout"));
try {
  describeResult(null);
} catch (e) {
  console.log("describeResult(null) ->", e.constructor.name + ": " + e.message);
}

// 场景三：真值判断把合法的 0 也排除了
function discount(count) {
  if (count) return "count = " + count;
  return "no count";
}
console.log("discount(0) =", discount(0));
console.log("discount(3) =", discount(3));
