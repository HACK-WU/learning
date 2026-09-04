// .d.ts 是「环境上下文」，只能有类型，不能有实现
declare function bad(a: number): number {
  return a + 1;
}
