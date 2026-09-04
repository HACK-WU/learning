// 课 6 · 知识点 3：边界探测 —— 断言为什么替代不了校验

interface Order {
  id: string;
  amount: number;
}

// A：as 不会检查任何东西 —— 缺字段也放行
const raw: unknown = JSON.parse('{"id":"o1"}');
const order = raw as Order; // ✅ 编译通过，缺 amount 也照样
try {
  console.log("as ->", order.amount.toFixed(2));
} catch (e) {
  console.log("as ->", (e as Error).message); // 💥 运行时炸
}

// B：双重断言能把完全不对的东西"变成" Order
const notAnOrder = "hello" as unknown as Order; // ✅ 编译通过
try {
  console.log("double as ->", notAnOrder.amount.toFixed(2));
} catch (e) {
  console.log("double as ->", (e as Error).message); // 💥 运行时炸
}

// C：断言之后，类型系统再也不会提醒你任何事
function use(order: Order): number {
  return order.amount * 2;
}
console.log("use(notAnOrder) ->", use(notAnOrder)); // NaN，静默错误

console.log(order);
