// 叶子模块：不依赖任何东西
export function formatMoney(amount: number, currency: string): string {
  return currency + " " + amount.toFixed(2);
}
