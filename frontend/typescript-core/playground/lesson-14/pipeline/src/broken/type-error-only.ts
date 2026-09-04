// 语法完全正确，只是类型不对。用来和 syntax-error.ts 做对照。
function total(a: number, b: number): number {
  return a + b;
}

export const result: string = total(1, 2);
