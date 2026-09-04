import { subtotal } from "./pricing.js";

// ❌ 这里传错了：discountRate 应该是数字
export const amount = subtotal(
  [{ sku: "A-1", unitPrice: 100, qty: 2 }],
  "0.1",
);
