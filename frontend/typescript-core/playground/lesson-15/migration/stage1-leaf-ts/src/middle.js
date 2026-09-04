// 中间层：依赖 leaf，暂时没有任何类型标注
import { formatMoney } from "./leaf.js";

export function lineTotal(qty, unitPrice) {
  return formatMoney(qty * unitPrice, "CNY");
}
