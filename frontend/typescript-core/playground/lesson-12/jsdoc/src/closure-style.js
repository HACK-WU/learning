/**
 * TS 7 不再支持 Closure 风格的函数类型语法。
 * 下面这种写法在 TS 6 里能认，在 TS 7 里不行 —— 得换成 TS 的简写。
 *
 * @param {function(string): void} callback
 * @returns {void}
 */
export function onMessage(callback) {
  callback("hello");
}
