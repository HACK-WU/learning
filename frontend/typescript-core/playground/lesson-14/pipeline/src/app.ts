interface Order {
  id: string;
  amount: number;
}

function total(orders: Order[]): number {
  return orders.reduce((sum, order) => sum + order.amount, 0);
}

const orders: Order[] = [
  { id: "A-1", amount: 100 },
  { id: "A-2", amount: 250 },
];

console.log("total =", total(orders));
