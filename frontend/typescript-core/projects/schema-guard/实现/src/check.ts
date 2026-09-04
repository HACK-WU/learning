import type { Schema } from "./schema.js";
import type { ParseError } from "./result.js";

/** 把值的运行时类型说成人话（顺便处理 null 与数组，课 6 的信任边界从这里开始） */
function typeName(value: unknown): string {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  if (value === undefined) return "undefined";
  return typeof value;
}

function joinPath(parent: string, child: string): string {
  return parent === "" ? child : `${parent}.${child}`;
}

/**
 * 递归校验：返回错误列表，空数组代表通过。
 *
 * 注意它**不去重、不短路** —— 一次性把所有问题报出来，而不是"遇到第一个就停"。
 * 这是课 12 错误边界原则的体现：调用方需要完整的上下文才能决策。
 *
 * ⚠️ 这是**内部实现**，不从 `index.ts` 导出（阶段 5 课 15 的导出边界）。
 *    它被单独抽成一个模块，是为了让 `test/` 下的对照组能直接复用同一份
 *    运行时校验逻辑，从而在测量「类型推导的代价」时只改变编译期那一半。
 */
export function check(
  schema: Schema,
  value: unknown,
  path: string,
): readonly ParseError[] {
  switch (schema.kind) {
    case "string": {
      if (typeof value !== "string") {
        return [{ path, message: `expected string, got ${typeName(value)}` }];
      }
      if (schema.minLength !== undefined && value.length < schema.minLength) {
        return [
          {
            path,
            message: `expected length >= ${schema.minLength}, got ${value.length}`,
          },
        ];
      }
      return [];
    }

    case "number": {
      // NaN 也是 typeof "number"，但它几乎不可能是合法业务数据 —— 单独挡掉
      if (typeof value !== "number" || Number.isNaN(value)) {
        return [{ path, message: `expected number, got ${typeName(value)}` }];
      }
      if (schema.min !== undefined && value < schema.min) {
        return [{ path, message: `expected >= ${schema.min}, got ${value}` }];
      }
      return [];
    }

    case "boolean": {
      if (typeof value !== "boolean") {
        return [{ path, message: `expected boolean, got ${typeName(value)}` }];
      }
      return [];
    }

    case "array": {
      if (!Array.isArray(value)) {
        return [{ path, message: `expected array, got ${typeName(value)}` }];
      }
      const errors: ParseError[] = [];
      for (let i = 0; i < value.length; i++) {
        errors.push(...check(schema.of, value[i], `${path}[${i}]`));
      }
      return errors;
    }

    case "object": {
      if (typeof value !== "object" || value === null || Array.isArray(value)) {
        return [{ path, message: `expected object, got ${typeName(value)}` }];
      }
      const record: Record<string, unknown> = { ...(value as Record<string, unknown>) };
      const errors: ParseError[] = [];
      for (const key of Object.keys(schema.fields)) {
        const fieldSchema: Schema | undefined = schema.fields[key];
        if (fieldSchema === undefined) continue; // noUncheckedIndexedAccess 下的必要防护
        const childPath = joinPath(path, key);
        if (!(key in record)) {
          errors.push({ path: childPath, message: "missing required field" });
          continue;
        }
        errors.push(...check(fieldSchema, record[key], childPath));
      }
      return errors;
    }

    default: {
      // 穷尽性检查（课 5）：新增 schema kind 却忘了加分支，这里会报错
      const _exhaustive: never = schema;
      return _exhaustive;
    }
  }
}
