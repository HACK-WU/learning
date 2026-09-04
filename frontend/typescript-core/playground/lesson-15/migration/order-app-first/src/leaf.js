// 叶子模块：不依赖任何东西
/**
 * @param {number} amount
 * @param {string} currency
 * @returns {string}
 */
export function formatMoney(amount, currency) {
  return currency + " " + amount.toFixed(2);
}
