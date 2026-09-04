// 完整路线：写 .ts
export interface Line {
  sku: string;
  unitPrice: number;
  qty: number;
}

export function subtotal(lines: Line[], discountRate: number): number {
  const raw = lines.reduce((sum, line) => sum + line.unitPrice * line.qty, 0);
  return raw * (1 - discountRate);
}
