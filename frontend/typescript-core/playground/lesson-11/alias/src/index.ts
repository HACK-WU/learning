// 走别名：类型解析靠 tsconfig 的 paths
import { money } from "@/utils/format";
// 走相对路径：写全扩展名，运行时 Node 认得出来（对照组）
import { label } from "./helper.js";

console.log(label, money(99));
