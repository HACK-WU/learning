// 课 9 · 第一幕：JS 里那些「改一下形状」的需求，全靠人肉保证

const order = { id: "o1", amount: 100, status: "pending" };

// 需求一：部分更新（表单编辑只提交改动的字段）
function updateOrder(base, patch) {
  return { ...base, ...patch };
}
// 手滑拼错了字段名
const updated = updateOrder(order, { ammount: 200 });
console.log("updated =", updated);
console.log("amount 还是", updated.amount, "，却多了个 ammount =", updated.ammount);

// 需求二：事件总线，事件名全靠字符串对得上
const handlers = {};
function on(event, handler) {
  handlers[event] = handler;
}
function emit(event, payload) {
  handlers[event](payload);
}
on("orderPaid", (p) => console.log("paid:", p.orderId));
try {
  emit("order_paid", { orderId: "o1" }); // 事件名对不上 → 崩
} catch (e) {
  console.log("emit(order_paid) ->", e.constructor.name + ": " + e.message);
}

// 需求三：同一份数据，不同场景要不同字段子集
function toSummary(o) {
  return { id: o.id, amount: o.amount };
}
console.log("summary =", toSummary(order));
