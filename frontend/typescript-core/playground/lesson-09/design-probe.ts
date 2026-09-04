// 课 9 · 补测：interface 与 type 的「隐式索引签名」差异

type EventMapAsType = {
  orderPaid: { orderId: string };
};

interface EventMapAsInterface {
  orderPaid: { orderId: string };
}

// A：type 版本能满足 Record<string, unknown> 吗？
const asType: Record<string, unknown> = { orderPaid: { orderId: "o1" } } as EventMapAsType;

// B：interface 版本呢？
const asInterface: Record<string, unknown> = { orderPaid: { orderId: "o1" } } as EventMapAsInterface;

console.log(asType, asInterface);
