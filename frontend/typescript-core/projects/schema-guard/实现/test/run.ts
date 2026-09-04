/**
 * 运行时断言测试（零依赖，用 Node 内置 assert）。
 *
 * 它守护的是 `parse.ts` 里那唯一一处 `as Infer<S>` —— 库对使用方的承诺
 * 不能只靠注释，得有断言盯着（课 6 信任边界 / 课 12 CI 门禁）。
 */
import assert from "node:assert/strict";
import { SchemaGuardError, array, boolean, describe, number, object, string } from "../src/index.js";
import { assert as assertSchema, is, parse, parseOrThrow } from "../src/index.js";

let passed = 0;
let failed = 0;

function test(name: string, fn: () => void): void {
  try {
    fn();
    passed++;
    console.log(`  ✓ ${name}`);
  } catch (e) {
    failed++;
    console.log(`  ✗ ${name}`);
    console.log(`      ${(e as Error).message.split("\n").join("\n      ")}`);
  }
}

console.log("schema-guard 验收测试\n");

// ---------- 标量 ----------
test("string：合法值通过", () => {
  const r = parse(string(), "hello");
  assert.equal(r.ok, true);
  if (r.ok) assert.equal(r.value, "hello");
});

test("string：非字符串被拦下", () => {
  const r = parse(string(), 42);
  assert.equal(r.ok, false);
  if (!r.ok) assert.equal(r.errors[0]?.message, "expected string, got number");
});

test("string：minLength 生效", () => {
  const r = parse(string(3), "ab");
  assert.equal(r.ok, false);
  if (!r.ok) assert.match(r.errors[0]?.message ?? "", /expected length >= 3/);
});

test("number：NaN 被当成非法（typeof 是 number 但业务上不是）", () => {
  assert.equal(parse(number(), Number.NaN).ok, false);
});

test("number：min 生效", () => {
  assert.equal(parse(number(0), -1).ok, false);
  assert.equal(parse(number(0), 1).ok, true);
});

test("boolean：只认真正的布尔", () => {
  assert.equal(parse(boolean(), true).ok, true);
  assert.equal(parse(boolean(), "true").ok, false);
});

// ---------- 组合 ----------
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

test("嵌套 object：合法数据通过", () => {
  const r = parse(userSchema, {
    name: "amy",
    age: 18,
    active: true,
    tags: ["a", "b"],
    profile: { email: "a@b.c", level: 2 },
  });
  assert.equal(r.ok, true);
});

test("嵌套 object：缺字段会报出完整路径", () => {
  const r = parse(userSchema, {
    name: "amy",
    age: 18,
    active: true,
    tags: [],
    profile: { email: "a@b.c" },
  });
  assert.equal(r.ok, false);
  if (!r.ok) {
    assert.equal(r.errors.length, 1);
    assert.equal(r.errors[0]?.path, "profile.level");
    assert.equal(r.errors[0]?.message, "missing required field");
  }
});

test("错误不短路：一次报出全部问题", () => {
  const r = parse(userSchema, { name: "", age: -1, active: "x", tags: "nope", profile: null });
  assert.equal(r.ok, false);
  if (!r.ok) assert.ok(r.errors.length >= 5, `期望 >=5 条，实际 ${r.errors.length} 条`);
});

test("array：逐项校验并带上索引路径", () => {
  const r = parse(array(number()), [1, "two", 3]);
  assert.equal(r.ok, false);
  if (!r.ok) assert.equal(r.errors[0]?.path, "[1]");
});

test("null 不会蒙混过关（object 分支显式挡掉）", () => {
  assert.equal(parse(object({ a: string() }), null).ok, false);
});

test("数组不会蒙混过关（object 分支显式挡掉）", () => {
  assert.equal(parse(object({ a: string() }), []).ok, false);
});

// ---------- 三种调用姿势 ----------
test("is()：类型守卫，不抛异常", () => {
  const value: unknown = "hello";
  assert.equal(is(string(), value), true);
  if (is(string(), value)) {
    // 收窄生效：这里 value 已经是 string
    assert.equal(value.toUpperCase(), "HELLO");
  }
});

test("assert()：失败时抛 SchemaGuardError 且带全部错误", () => {
  assert.throws(
    () => assertSchema(userSchema, { name: "", age: -1 }),
    (e: unknown) => {
      assert.ok(e instanceof SchemaGuardError);
      assert.equal(e.name, "SchemaGuardError");
      assert.ok(e.errors.length >= 5);
      return true;
    },
  );
});

test("parseOrThrow()：拿到已收窄的值", () => {
  const user = parseOrThrow(userSchema, {
    name: "bob",
    age: 30,
    active: false,
    tags: [],
    profile: { email: "b@c.d", level: 9 },
  });
  assert.equal(user.profile.level, 9);
});

// ---------- describe + 穷尽性 ----------
test("describe()：把 schema 说成人话", () => {
  assert.equal(describe(userSchema), "{ name: string(minLength=1), age: number(min=0), active: boolean, tags: array<string>, profile: { email: string, level: number } }");
});

// ---------- 边界：来自外部的数据 ----------
test("真实场景：JSON.parse 出来的东西必须过一遍校验", () => {
  const payload: unknown = JSON.parse('{"name":"amy","age":"18"}');
  // age 是字符串，肉眼看着像数字 —— 这正是类型帮不上、校验才管用的地方
  const r = parse(object({ name: string(), age: number() }), payload);
  assert.equal(r.ok, false);
  if (!r.ok) assert.equal(r.errors[0]?.path, "age");
});

console.log(`\n${passed} 通过 / ${failed} 失败`);
process.exit(failed === 0 ? 0 : 1);
