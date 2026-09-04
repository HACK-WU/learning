import { sumAmount } from "./order.js";

// ❌ 类型错误：amount 写成了字符串
const orders = [{ id: "A-1", amount: "100" }];

console.log("total =", sumAmount(orders));
