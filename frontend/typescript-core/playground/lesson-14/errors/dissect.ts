// ============ 知识点 4：拆解复杂报错的两把刀 ============

// ---------- 刀法一：读「原因链」的缩进层级 ----------
// 报错结构是：位置 → 错误码 → 主结论 → 逐层缩进的原因。
// 最内层那句才是根因，外面的都是「因为……所以……」的推导。

interface Formatter {
  (v: string, opt: { upper: boolean }): string;
  (v: number, opt: { precision: number }): string;
  (v: Date, opt: { iso: boolean }): string;
}
declare const fmt: Formatter;

export const r = fmt(true, { upper: true });
// error TS2769: No overload matches this call.                      ← 主结论
//   The last overload gave the following error.                     ← 第 1 层：哪一条失败了
//     Argument of type 'boolean' is not assignable to ... 'Date'.   ← 第 2 层：根因

// ---------- 刀法二：拆中间变量，把报错逼到精确位置 ----------
// 下面这行一次性做三件事：构造对象 → 传给泛型函数 → 断言返回值。
// 错在哪里？TS 只能报在最外层，你根本看不出是哪一个字段的锅。
interface Account {
  profile: { name: string; avatar: { url: string; size: number } };
  plan: { tier: "free" | "pro"; seats: number };
}
declare function submit<T extends Account>(a: T): { ok: boolean };

export const bad = submit({
  profile: { name: "amy", avatar: { url: "u", size: "big" } },
  plan: { tier: "pro", seats: 5 },
}).ok;

// 拆开之后：每一段自己报自己的错，定位精确到字段
export const good = (() => {
  const avatar = { url: "u", size: 123 }; // 这里单独检查
  const profile = { name: "amy", avatar };
  const plan: { tier: "free" | "pro"; seats: number } = { tier: "pro", seats: 5 };
  const account: Account = { profile, plan };
  return submit(account).ok;
})();
