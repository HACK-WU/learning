// 入口：依赖 middle。这里埋了一个 bug —— qty 是字符串
import { lineTotal } from "./middle.js";

export const label = lineTotal("3", 10);
