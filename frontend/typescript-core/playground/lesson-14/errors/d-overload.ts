// 候选 D：函数重载，没有一个签名匹配
interface Api {
  (a: string): string;
  (a: number, b: number): number;
}

declare const api: Api;

export const r = api(true);
