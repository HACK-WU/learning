// 课 9 · 知识点 4：泛型的实际设计场景

// ── 场景一：API 响应包装 ──────────────────────────────
type ApiResult<T> = { ok: true; data: T } | { ok: false; error: string };
interface Paged<T> {
  items: T[];
  total: number;
  page: number;
}

interface Order {
  id: string;
  amount: number;
  status: "pending" | "paid";
}

// ── 场景二：类型安全的事件总线 ────────────────────────
// 事件名 → payload 类型 的映射表，只需要维护这一份
interface OrderEvents {
  orderCreated: { orderId: string };
  orderPaid: { orderId: string; amount: number };
  orderRefunded: { orderId: string; reason: string };
}

class EventBus<Events extends object> {
  private handlers: { [K in keyof Events]?: ((payload: Events[K]) => void)[] } = {};

  on<K extends keyof Events>(event: K, handler: (payload: Events[K]) => void): this {
    const list = (this.handlers[event] ??= []) as ((payload: Events[K]) => void)[];
    list.push(handler);
    return this;
  }

  emit<K extends keyof Events>(event: K, payload: Events[K]): void {
    for (const handler of (this.handlers[event] ?? []) as ((payload: Events[K]) => void)[]) {
      handler(payload);
    }
  }
}

const bus = new EventBus<OrderEvents>();
bus.on("orderPaid", (p) => console.log(`paid ${p.orderId}: ${p.amount}`));
bus.emit("orderPaid", { orderId: "o1", amount: 100 }); // ✅
// bus.emit("order_paid", { orderId: "o1" });          // ❌ 事件名拼错，见 scenario-guard.ts
// bus.emit("orderPaid", { orderId: "o1" });           // ❌ 缺 amount，见 scenario-guard.ts

// ── 场景三：从数据模型生成表单字段类型 ────────────────
// 技巧：映射类型 + 索引访问，把对象「转」成一个联合
type FormField<T> = {
  [K in keyof T]: { name: K; value: T[K]; label: string };
}[keyof T];

type OrderField = FormField<Order>;
const field1: OrderField = { name: "id", value: "o1", label: "订单号" };
const field2: OrderField = { name: "amount", value: 100, label: "金额" };
// const field3: OrderField = { name: "amount", value: "100", label: "金额" }; // ❌ value 类型不对
// const field4: OrderField = { name: "missing", value: 1, label: "X" };       // ❌ 键不存在

console.log(field1, field2);
