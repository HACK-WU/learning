// 课 10 · 项目引用示例：被依赖的包
export interface Order {
  id: string;
  amount: number;
}

export function total(orders: Order[]): number {
  return orders.reduce((sum, order) => sum + order.amount, 0);
}
