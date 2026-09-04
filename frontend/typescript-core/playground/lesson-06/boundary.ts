// 课 6 · 知识点 3：信任边界 —— 在数据入口处收敛不安全类型

interface Order {
  id: string;
  amount: number;
}

// ① 信任边界：逐字段做运行时校验，不合格就明确拒绝
function parseOrder(raw: unknown): Order | null {
  if (typeof raw !== "object" || raw === null) return null;
  const candidate = raw as Record<string, unknown>;
  if (typeof candidate.id !== "string") return null;
  if (typeof candidate.amount !== "number") return null; // 后端改成字符串 → 这里拦住
  return { id: candidate.id, amount: candidate.amount };
}

// ② 边界之内，类型是可信的（不用再写任何判断）
function formatOrder(order: Order): string {
  return `order ${order.id}: ${order.amount.toFixed(2)}`;
}

function handle(raw: unknown): string {
  const order = parseOrder(raw);
  if (order === null) return "invalid order";
  return formatOrder(order);
}

// 后端把 amount 从数字改成了字符串
const bad: unknown = JSON.parse('{"id":"o1","amount":"99"}');
const good: unknown = JSON.parse('{"id":"o2","amount":199}');

console.log(handle(bad)); // invalid order
console.log(handle(good)); // order o2: 199.00
