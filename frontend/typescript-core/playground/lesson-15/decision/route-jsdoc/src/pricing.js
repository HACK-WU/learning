// 轻量路线：不写 .ts，靠 JSDoc + checkJs 拿类型检查
/**
 * @typedef {{ sku: string, unitPrice: number, qty: number }} Line
 */

/**
 * @param {Line[]} lines
 * @param {number} discountRate
 * @returns {number}
 */
export function subtotal(lines, discountRate) {
  const raw = lines.reduce((sum, line) => sum + line.unitPrice * line.qty, 0);
  return raw * (1 - discountRate);
}
