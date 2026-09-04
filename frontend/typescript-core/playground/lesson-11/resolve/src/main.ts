// 相对路径：./ 或 ../ 开头，从当前文件所在目录找
import { label } from "./helper.js";
// 相对路径 + 目录：nodenext 下必须写到文件名，不能停在目录
import { money } from "./utils/index.js";
// 裸标识符（bare specifier）：去 node_modules 里找
import { GREETING, VERSION } from "demo-pkg";
// 子路径导出：由 demo-pkg 的 exports 字段决定
import { subLabel } from "demo-pkg/sub";

console.log(label, money(128.5), GREETING, VERSION, subLabel());
