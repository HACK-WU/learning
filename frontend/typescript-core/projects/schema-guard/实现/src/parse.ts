import type { Infer } from "./infer.js";
import { check } from "./check.js";
import type { Schema } from "./schema.js";
import { SchemaGuardError } from "./errors.js";
import { err, ok, type ParseResult } from "./result.js";

/**
 * 主入口：返回一个判别式联合，而不是抛异常（决策点 1）。
 *
 * ⚠️ 这里出现了一次 `as Infer<S>`，是本项目**唯一**必须写断言的地方。
 *    原因：`Infer<S>` 是编译期的推导结果，TS 无法证明「运行时校验通过」
 *    等价于「这个值就是 Infer<S>」。这个断言是**库对使用方的承诺**，
 *    由 `test/` 下的断言测试来保证它没撒谎 —— 这是课 6「信任边界」的
 *    正确用法：断言集中在边界处，并且被测试覆盖。
 */
export function parse<S extends Schema>(schema: S, value: unknown): ParseResult<Infer<S>> {
  const errors = check(schema, value, "");
  if (errors.length > 0) return err(errors);
  return ok(value as Infer<S>);
}

/** 类型守卫（课 5）：`if (is(schema, x))` 之后 x 会被收窄成 Infer<S> */
export function is<S extends Schema>(schema: S, value: unknown): value is Infer<S> {
  return check(schema, value, "").length === 0;
}

/** 断言函数（课 5）：失败就抛，适合"数据不合法就该崩"的场景 */
export function assert<S extends Schema>(schema: S, value: unknown): asserts value is Infer<S> {
  const errors = check(schema, value, "");
  if (errors.length > 0) throw new SchemaGuardError(errors);
}

/** `parse()` 的抛异常版本：拿不到值就炸，返回值已经收窄过了 */
export function parseOrThrow<S extends Schema>(schema: S, value: unknown): Infer<S> {
  assert(schema, value);
  return value;
}
