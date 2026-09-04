// 这个不是模块（没有 import / export），却用了 declare global —— 非法
declare global {
  var __BAD_ID__: string;
}
