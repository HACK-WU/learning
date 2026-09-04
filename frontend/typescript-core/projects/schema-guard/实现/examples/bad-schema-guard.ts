/**
 * 反例：**能跑，但很糟** 的版本。
 *
 * 运行：npm run bad
 *
 * ⚠️ 这个脚本会以 exit 0 正常结束 —— 也就是说，如果你只看「能不能跑」，
 *    下面这 7 条问题**一条都发现不了**。它们只在真实使用里才咬人。
 *    逐条对照见 `反例对照.md`。
 */
const line = (s: string) => console.log(s);

// ══════════════════════════════════════════════════════════════════════════
// BAD 1：用 `as` 断言代替校验 —— 编译器信了你，然后什么都不做
// ══════════════════════════════════════════════════════════════════════════
line("【BAD 1】as 断言当校验用\n");

interface BadUser {
  name: string;
  age: number;
}

const raw: unknown = JSON.parse('{"name":"amy","age":"18"}'); // age 其实是字符串

const user = raw as BadUser; // ✅ 编译通过
line(`  断言后读 user.age = ${user.age}（类型是 number？）`);

try {
  // 💥 炸在这里：string 没有 toFixed
  line(`  user.age.toFixed(2) = ${(user.age as unknown as { toFixed?: (n: number) => string }).toFixed?.(2)}`);
  line(`  ↑ 侥幸没炸，但拿到的是 ${typeof user.age}，不是 number`);
} catch (e) {
  line(`  💥 运行时炸了：${(e as Error).message}`);
}

// ══════════════════════════════════════════════════════════════════════════
// BAD 2：用 any 让所有校验"通过" —— 等于把类型系统关掉
// ══════════════════════════════════════════════════════════════════════════
line("\n【BAD 2】any 一撒，天下太平\n");

function badParseAnything(_schema: unknown, value: unknown): any {
  // eslint-disable-next-line @typescript-eslint/no-unsafe-return
  return value as any;
}

const anything = badParseAnything({ kind: "number" }, "not a number");
line(`  校验"通过"了，值是 ${JSON.stringify(anything)}，类型是 any`);
line(`  → 后面不管写什么都不会报错，错误一路带到线上`);

// ══════════════════════════════════════════════════════════════════════════
// BAD 3：schema 和 interface 各写一份，然后慢慢不同步
// ══════════════════════════════════════════════════════════════════════════
line("\n【BAD 3】schema 与 interface 两份定义\n");

const schemaV2 = { kind: "object", fields: { name: { kind: "string" }, age: { kind: "number" }, vip: { kind: "boolean" } } };
//                                                                                    ↑ schema 加了 vip，但 interface 忘了改
interface UserV2 {
  name: string;
  age: number;
}
line(`  schema 有 3 个字段，interface 只有 2 个 —— 没有任何一处会报错`);
line(`  运行时拿到的 user.vip 在类型上"不存在"，用的时候要么 as，要么漏掉`);
void schemaV2;
void ({} as UserV2);

// ══════════════════════════════════════════════════════════════════════════
// BAD 4：只报第一条错误 —— 调用方要改 5 轮才知道全貌
// ══════════════════════════════════════════════════════════════════════════
line("\n【BAD 4】短路校验，只报第一条\n");

function badValidateFirstError(
  shape: Record<string, string>,
  value: Record<string, unknown>,
): string | null {
  for (const [key, expected] of Object.entries(shape)) {
    if (typeof value[key] !== expected) {
      return `${key} should be ${expected}`;
    }
  }
  return null;
}

const first = badValidateFirstError(
  { name: "string", age: "number", email: "string", active: "boolean" },
  { name: 1, age: "x", email: 2, active: "y" },
);
line(`  4 个字段全错，只报出：${first}`);
line(`  → 调用方改一个、跑一次、再改一个…… `);

// ══════════════════════════════════════════════════════════════════════════
// BAD 5：只查 top-level 的 typeof，嵌套结构完全没看
// ══════════════════════════════════════════════════════════════════════════
line("\n【BAD 5】浅校验：只看一层\n");

function badShallowCheck(value: unknown): boolean {
  return typeof value === "object" && value !== null;
}

const shallow = badShallowCheck({ profile: { name: 123 } });
line(`  { profile: { name: 123 } } → ${shallow ? "通过" : "不通过"}`);
line(`  → 里面 name 是 number 这件事，它一点都不知道`);

// ══════════════════════════════════════════════════════════════════════════
// BAD 6：switch 没有穷尽性兜底 —— 新增 kind 时静默漏掉
// ══════════════════════════════════════════════════════════════════════════
line("\n【BAD 6】没有穷尽性检查的 switch\n");

type BadShape = { kind: "string" } | { kind: "number" } | { kind: "date" }; // 新加了 date
function badDescribe(shape: BadShape): string {
  switch (shape.kind) {
    case "string":
      return "string";
    case "number":
      return "number";
    default:
      return "unknown"; // ← 把 date 吞了，而且不报错
  }
}
line(`  badDescribe({ kind: "date" }) = ${badDescribe({ kind: "date" })}`);
line(`  → 新增 kind 后，这里静默返回 unknown，没人会发现`);

// ══════════════════════════════════════════════════════════════════════════
// BAD 7：为了"通用"把 API 写成没人看得懂的形状
// ══════════════════════════════════════════════════════════════════════════
line("\n【BAD 7】过度泛型：能编译，但没人会用\n");

type OverGeneric<T, U extends keyof T, V extends T[U]> = T extends Record<U, V> ? T[U] : never;
const _over: OverGeneric<{ a: string; b: number }, "a", string> = "hello";
void _over;
line(`  OverGeneric<T, U, V> —— 三个参数，报错信息里全是 T/U/V，看不出在说什么`);
line(`  → 课 13 的判断：「需要注释才能解释这个类型在干什么」就是红灯`);

line("\n反例演示结束（exit 0：只看能不能跑，一条问题都发现不了）。");
