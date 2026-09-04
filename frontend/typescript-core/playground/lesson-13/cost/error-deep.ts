// 再深一层：链式路径取值。这类「多层条件类型 + 递归 infer」是类型体操的重灾区。
type Get<T, P extends string> = P extends `${infer K}.${infer Rest}`
  ? K extends keyof T
    ? Get<T[K], Rest>
    : never
  : P extends keyof T
    ? T[P]
    : never;

declare function pick<T extends object, P extends string>(obj: T, path: P): Get<T, P>;

const obj = {
  user: { profile: { name: "amy", age: 18 }, settings: { theme: "dark" } },
};

// ① 正常用法
const ok: string = pick(obj, "user.profile.name");

// ② 写错类型：实际是 string，却声明成 number
//    → 实测报错很干净：Type 'string' is not assignable to type 'number'.
const wrong: number = pick(obj, "user.profile.name");

// ③ ⚠️ 真正的坑：路径写错时，结果是 never ——
//    而 never 可以赋给任何类型，于是「错误被静默吞掉了」
const missing = pick(obj, "user.profile.nickname");
export const m: string = missing; // 实测：不报错！

// 验证一下它确实是 never
type IsNever<T> = [T] extends [never] ? true : false;
type MissingIsNever = IsNever<typeof missing>;
export const proof: true = null as unknown as MissingIsNever;

// ---------- 另一个方向：嵌套映射类型的报错 ----------
type DeepPartial<T> = { [K in keyof T]?: T[K] extends object ? DeepPartial<T[K]> : T[K] };
declare function update<T>(id: string, patch: DeepPartial<T>): void;

interface Account {
  profile: { name: string; avatar: { url: string; size: number } };
  plan: { tier: "free" | "pro"; seats: number };
}

// 故意把最内层的 size 写成字符串
update<Account>("a-1", { profile: { avatar: { url: "u", size: "big" } } });
