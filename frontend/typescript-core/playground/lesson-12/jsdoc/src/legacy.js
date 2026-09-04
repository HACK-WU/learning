/**
 * 老项目里的一个 JS 函数，一行 .ts 都没写，但靠 JSDoc 拿到了完整的类型检查。
 *
 * @param {{ id: string, price: number }} item
 * @param {number} quantity
 * @returns {number}
 */
export function subtotal(item, quantity) {
  return item.price * quantity;
}

/**
 * @typedef {{ id: string, price: number }} CartItem
 */

/**
 * @param {CartItem[]} items
 * @returns {number}
 */
export function total(items) {
  return items.reduce((sum, item) => sum + subtotal(item, 1), 0);
}
