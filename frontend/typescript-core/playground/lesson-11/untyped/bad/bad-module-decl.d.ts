// ⚠️ 反例：只要文件里有任何顶层 import / export，本文件就成了「模块」。
// 此时 declare module "xxx" 的含义从「环境声明」变成「扩展一个已存在的模块」，
// 而 legacy-math 此刻并没有任何类型声明可供扩展 —— 于是报错。
export {};

declare module "legacy-math" {
  export function add(a: number, b: number): number;
}
