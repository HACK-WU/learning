import { subtotal } from "./pricing.js";

// ❌ 同一个 bug：discountRate 应该是数字
export const amount = subtotal(
  [{ sku: "A-1", unitPrice: 100, qty: 2 }],
  "0.1",
);
