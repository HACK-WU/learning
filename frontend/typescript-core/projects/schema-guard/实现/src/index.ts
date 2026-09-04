/**
 * 公开 API 边界（阶段 5 课 15）。
 *
 * 这里刻意**只导出使用方需要的东西**：`check()` 是内部实现，不导出；
 * `result.ts` 的内部工具也不导出。因为 `declaration: true` 产出的
 * `.d.ts` 会暴露「对外签名里用到的类型」—— 少导出一个，就少一个
 * 将来改不动的承诺。
 */
export { SchemaGuardError } from "./errors.js";
export { array, boolean, describe, number, object, string } from "./schema.js";
export type {
  ArraySchema,
  BooleanSchema,
  NumberSchema,
  ObjectSchema,
  Schema,
  StringSchema,
} from "./schema.js";
export type { Infer } from "./infer.js";
export { assert, is, parse, parseOrThrow } from "./parse.js";
export type { ParseError, ParseResult } from "./result.js";
