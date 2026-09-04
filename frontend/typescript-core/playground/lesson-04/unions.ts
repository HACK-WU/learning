// 课 4 · 知识点 1：联合类型

// ① 联合类型 = "几种可能之一"
type Status = "pending" | "paid" | "refunded";
let orderStatus: Status = "pending";
orderStatus = "paid";
// orderStatus = "shipped"; // ❌ 见 unions-probe.ts

// ② 联合上的属性访问：只能访问所有成员都有的
function format(id: string | number): string {
  return id.toString(); // ✅ string 和 number 都有 toString
  // return id.toUpperCase(); // ❌ number 上没有
}

// ③ 判别式联合：用一个字面量字段当"标签"
type Result =
  | { ok: true; data: string[] }
  | { ok: false; error: string };

function handle(r: Result): string {
  if (r.ok) {
    return r.data.join(", "); // ✅ 这个分支里 r 收窄为 { ok: true; data: string[] }
  }
  return `failed: ${r.error}`; // ✅ 收窄为 { ok: false; error: string }
}

// ④ 交叉类型 &：同时满足（与联合相反）
type Timestamped = { createdAt: string };
type Row = { id: string; score: number } & Timestamped;
const row: Row = { id: "u1", score: 98, createdAt: "2026-09-01" };

console.log(orderStatus, format(42));
console.log(handle({ ok: true, data: ["a", "b"] }));
console.log(handle({ ok: false, error: "timeout" }));
console.log(row);
