// 课 10 · 第一幕：一份照着 5.x 老教程抄的 tsconfig
interface Order {
  id: string;
  amount: number;
}

export function total(orders: Order[]): number {
  let sum = 0;
  for (const order of orders) {
    sum += order.amount;
  }
  return sum;
}
