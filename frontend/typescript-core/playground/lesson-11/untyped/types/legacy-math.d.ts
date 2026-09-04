// 给无类型的 JS 库补类型：环境模块声明（ambient module declaration）
// 注意：本文件没有任何顶层 import / export —— 所以它是「全局脚本」，
// 里面的 declare module "xxx" 才会被当成「对模块名的环境声明」。
declare module "legacy-math" {
  export function add(a: number, b: number): number;
  export function mul(a: number, b: number): number;
}
