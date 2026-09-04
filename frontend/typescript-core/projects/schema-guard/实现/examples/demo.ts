/**
 * 演示：7 个场景，逐个对应课程里的知识点。
 * 运行：npm run demo
 */
import { SchemaGuardError, array, boolean, describe, number, object, string } from "../src/index.js";
import { assert as assertSchema, is, parse, parseOrThrow } from "../src/index.js";

const line = (s: string) => console.log(s);

// ── 场景 1：一份 schema，同时得到「运行时校验」和「编译期类型」 ────────────
line("【场景 1】一份 schema → 校验 + 类型推导（阶段 3 课 9）\n");

const userSchema = object({
  name: string(1),
  age: number(0),
  active: boolean(),
  tags: array(string()),
  profile: object({
    email: string(),
    level: number(),
  }),
});

line(`schema = ${describe(userSchema)}`);

const good = parse(userSchema, {
  name: "amy",
  age: 18,
  active: true,
  tags: ["admin"],
  profile: { email: "amy@example.com", level: 2 },
});

if (good.ok) {
  // 不需要手写 interface：value 的类型是从 schema 推出来的
  line(`✓ 通过：${good.value.name}（level=${good.value.profile.level}）`);
} else {
  line(`✗ 失败：${JSON.stringify(good.errors)}`);
}

// ── 场景 2：错误带完整路径 ────────────────────────────────────────────────
line("\n【场景 2】错误路径精确到字段（阶段 4 课 12 的可观测性）\n");

const missingField = parse(userSchema, {
  name: "amy",
  age: 18,
  active: true,
  tags: [],
  profile: { email: "amy@example.com" }, // 少了 level
});

if (!missingField.ok) {
  for (const e of missingField.errors) {
    line(`  ✗ ${e.path}: ${e.message}`);
  }
}

// ── 场景 3：类型帮不上忙的地方，正是运行时校验的价值 ──────────────────────
line("\n【场景 3】外部数据：类型保证不了，校验才行（阶段 2 课 6 / 阶段 5 课 15）\n");

const payload: unknown = JSON.parse('{"name":"bob","age":"30"}');

// 下面这行如果只用 `as`，编译器会「相信你」，然后什么都不做：
//   const user = payload as { name: string; age: number };   // 编译通过
//   user.age.toFixed(2);                                     // 运行时 TypeError
const checked = parse(object({ name: string(), age: number() }), payload);

line(`  用 as 断言      → 编译通过，运行时才炸（看不见）`);
line(`  用 parse 校验   → ${checked.ok ? "通过" : `拦下：${checked.errors[0]?.path} ${checked.errors[0]?.message}`}`);

// ── 场景 4：is() 类型守卫收窄 unknown ─────────────────────────────────────
line("\n【场景 4】is() 类型守卫：收窄 unknown（阶段 2 课 5）\n");

const mystery: unknown = "hello";
if (is(string(), mystery)) {
  line(`  mystery 已收窄为 string → ${mystery.toUpperCase()}`);
}

// ── 场景 5：assert() 断言函数，一次报出全部问题 ───────────────────────────
line("\n【场景 5】assert()：错误不短路，一次给全（阶段 2 课 5）\n");

try {
  assertSchema(userSchema, { name: "", age: -1, active: "yes", tags: "nope", profile: null });
} catch (e) {
  if (e instanceof SchemaGuardError) {
    line(`  ${e.name}: ${e.message.split("\n")[0]}`);
    for (const err of e.errors) line(`    - ${err.path}: ${err.message}`);
  }
}

// ── 场景 6：穷尽性检查兜住了 schema 的每一种 kind ─────────────────────────
line("\n【场景 6】穷尽性检查：加新 kind 忘了改代码会报错（阶段 2 课 5）\n");

line(`  describe(array(object({ a: number() }))) = ${describe(array(object({ a: number() })))}`);
line("  （src/check.ts 与 src/schema.ts 的 default 分支都有 `const _exhaustive: never = schema`）");

// ── 场景 7：三种调用姿势的取舍 ────────────────────────────────────────────
line("\n【场景 7】parse / is / assert / parseOrThrow 四种姿势（决策点 1）\n");

const raw: unknown = { name: "carol", age: 25, active: true, tags: [], profile: { email: "c@d.e", level: 1 } };

const asResult = parse(userSchema, raw);
line(`  parse()        → 返回 Result，调用方必须判 ok（${asResult.ok ? "通过" : "失败"}）`);

line(`  is()           → 只要一个布尔，顺带收窄（${is(userSchema, raw)}）`);

try {
  const v = parseOrThrow(userSchema, raw);
  line(`  parseOrThrow() → 直接拿值，失败就抛（name=${v.name}）`);
} catch {
  line(`  parseOrThrow() → 抛了`);
}

line("\n演示结束。");
