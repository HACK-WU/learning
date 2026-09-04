// 这四个问题，tsc --noEmit 一个都不会报

// ① float promise：Promise 没人接，里面的错误会被静默吞掉
export async function fetchOrder(id: string): Promise<{ id: string }> {
  const row = await Promise.resolve({ id });
  return row;
}

export function processOrder(id: string): void {
  fetchOrder(id);
}

// ② any：它是合法类型，tsc 不管；团队想禁它得靠 lint
export function parse(raw: any): any {
  return raw;
}

// ③ 永真条件：类型上 items 永远是数组，这个判断是死代码
export function firstLabel(items: string[]): string {
  if (items) {
    return items[0] ?? "";
  }
  return "";
}
