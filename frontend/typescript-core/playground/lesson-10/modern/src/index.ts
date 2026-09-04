// 课 10 · 迁移后的 TS 7 项目
interface Order {
  id: string;
  amount: number;
}

export function total(orders: Order[]): number {
  return orders.reduce((sum, order) => sum + order.amount, 0);
}

console.log(total([{ id: "o1", amount: 100 }]));
