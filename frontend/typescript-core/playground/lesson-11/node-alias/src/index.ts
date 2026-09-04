// # 前缀 = Node 原生子路径导入，由 package.json 的 imports 字段解析
// 运行时 Node 认得它，类型层 TS 也认得它 —— 两边同一套规则
import { money } from "#money";

console.log(money(199));
