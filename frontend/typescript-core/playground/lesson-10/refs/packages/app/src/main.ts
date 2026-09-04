// 课 10 · 项目引用示例：依赖 core 的应用
// 注意：引用的是 core 的**产物**（dist/index.d.ts），不是源码
import { total, type Order } from "../../core/dist/index.js";

const orders: Order[] = [
  { id: "o1", amount: 100 },
  { id: "o2", amount: 80 },
];

console.log("total =", total(orders));
