// 课 9 · 第四幕：把第一幕的三个需求，用类型表达出来

interface Order {
  id: string;
  amount: number;
  status: "pending" | "paid" | "refunded";
}

const order: Order = { id: "o1", amount: 100, status: "pending" };

// 需求一：部分更新 —— 键必须是 Order 的键，值类型还得对
function updateOrder(base: Order, patch: Partial<Order>): Order {
  return { ...base, ...patch };
}
const updated = updateOrder(order, { amount: 200 }); // ✅
// updateOrder(order, { ammount: 200 });             // ❌ 第一幕的事故一

// 需求二：事件总线 —— 事件名与 payload 都受类型约束
interface OrderEvents {
  orderCreated: { orderId: string };
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
bus.on("orderPaid", (p) => console.log(`event: ${p.orderId} paid ${p.amount}`));
bus.emit("orderPaid", { orderId: "o1", amount: 200 });

// 需求三：字段子集 —— 用 Pick 从源类型派生，不手写第二份
type OrderSummary = Pick<Order, "id" | "amount">;
function toSummary(o: Order): OrderSummary {
  return { id: o.id, amount: o.amount };
}

console.log("updated =", updated);
console.log("summary =", toSummary(order));
