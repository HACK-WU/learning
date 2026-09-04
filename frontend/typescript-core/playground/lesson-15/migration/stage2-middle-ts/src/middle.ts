// 中间层：依赖 leaf，已迁移到 TS
import { formatMoney } from "./leaf.js";

export function lineTotal(qty: number, unitPrice: number): string {
  return formatMoney(qty * unitPrice, "CNY");
}
