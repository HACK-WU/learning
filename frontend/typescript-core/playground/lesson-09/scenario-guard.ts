// 课 9 · 第四幕回扣：四道防线（预期报错）

interface Order {
  id: string;
  amount: number;
  status: "pending" | "paid" | "refunded";
}
const order: Order = { id: "o1", amount: 100, status: "pending" };

function updateOrder(base: Order, patch: Partial<Order>): Order {
  return { ...base, ...patch };
}

interface OrderEvents {
  orderPaid: { orderId: string; amount: number };
}
class EventBus<Events extends object> {
  private handlers: { [K in keyof Events]?: ((payload: Events[K]) => void)[] } = {};
  on<K extends keyof Events>(event: K, handler: (payload: Events[K]) => void): this {
    const list = (this.handlers[event] ??= []) as ((payload: Events[K]) => void)[];
    list.push(handler);
    return this;
  }
  emit<K extends keyof Events>(event: K, payload: Events[K]): void {
    for (const h of (this.handlers[event] ?? []) as ((payload: Events[K]) => void)[]) h(payload);
  }
}
const bus = new EventBus<OrderEvents>();

// ① 拼错的字段 —— 第一幕的事故一
updateOrder(order, { ammount: 200 });

// ② 事件名拼错 —— 第一幕的事故二
bus.emit("order_paid", { orderId: "o1", amount: 100 });

// ③ payload 缺字段
bus.emit("orderPaid", { orderId: "o1" });

// ④ Omit 删掉的字段不能再用
const withoutStatus: Omit<Order, "status"> = { id: "o1", amount: 100, status: "paid" };

console.log(withoutStatus, bus);
