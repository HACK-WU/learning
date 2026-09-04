/**
 * JSDoc 写出来的类型，和 .ts 里的类型一样会被检查。
 *
 * @param {number} price
 * @returns {string}
 */
export function formatPrice(price) {
  // ❌ 传错类型：JSDoc 说好是 number
  return formatPriceInner("" + price);
}

/**
 * @param {number} value
 * @returns {string}
 */
function formatPriceInner(value) {
  return "CNY " + value.toFixed(2);
}
