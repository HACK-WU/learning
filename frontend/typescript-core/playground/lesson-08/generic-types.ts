// 课 8 · 知识点 3：泛型类型 —— 接口、别名与默认值

interface Order {
  id: string;
  amount: number;
}

const order: Order = { id: "o1", amount: 100 };

// ① 泛型接口：一份模具，装什么由调用方决定
interface ApiResponse<T> {
  code: number;
  message: string;
  data: T;
}
const single: ApiResponse<Order> = { code: 0, message: "ok", data: order };
const list: ApiResponse<Order[]> = { code: 0, message: "ok", data: [order] };

// ② 泛型类型别名：同样的事，用 type 写
type Result<T> = { ok: true; data: T } | { ok: false; error: string };
const success: Result<number> = { ok: true, data: 42 };
const failure: Result<number> = { ok: false, error: "timeout" };

// ③ 默认类型参数：不写就用默认的
interface Paged<T = Order> {
  items: T[];
  total: number;
}
const defaultPaged: Paged = { items: [order], total: 1 }; // T = Order
const stringPaged: Paged<string> = { items: ["a"], total: 1 };

// ④ 多个类型参数，后面的可以用前面的，也可以有默认值
interface KeyValue<K extends string | number, V = string> {
  key: K;
  value: V;
}
const kv: KeyValue<number> = { key: 1, value: "one" };
const kv2: KeyValue<string, number> = { key: "one", value: 1 };

// ⑤ 泛型类：课 7 的 Stack 加上类型参数
class Stack<T> {
  private items: T[] = [];
  push(item: T): this {
    this.items.push(item);
    return this;
  }
  pop(): T | undefined {
    return this.items.pop();
  }
  get size(): number {
    return this.items.length;
  }
}
const stack = new Stack<number>();
stack.push(1).push(2);

console.log(single.code, list.data.length, success.data, failure.error);
console.log(defaultPaged.total, stringPaged.items, kv.value, kv2.value);
console.log(stack.pop(), stack.size);
