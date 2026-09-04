export interface Order {
  id: string;
  amount: number;
}

// 这个 bug 会让「金额为空」的订单被算成 0 元 —— 测试没覆盖到，类型能拦住
export function sumAmount(orders: Order[]): number {
  return orders.reduce((total, order) => total + order.amount, 0);
}
