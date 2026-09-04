/**
 * Schema 定义：一个判别式联合（阶段 2 课 4）。
 *
 * 用 `kind` 做判别式，这样 `parse()` 里可以用 `switch` + `never` 兜底做
 * 穷尽性检查（阶段 2 课 5）。
 *
 * ⚠️ `ArraySchema` / `ObjectSchema` 故意带类型参数：这样 builder 返回的
 *    具体结构（谁是谁的元素、有哪些字段）能被 `Infer<S>` 完整看到。
 */

export interface StringSchema {
  readonly kind: "string";
  readonly minLength?: number;
}

export interface NumberSchema {
  readonly kind: "number";
  readonly min?: number;
}

export interface BooleanSchema {
  readonly kind: "boolean";
}

export interface ArraySchema<S> {
  readonly kind: "array";
  readonly of: S;
}

export interface ObjectSchema<F> {
  readonly kind: "object";
  readonly fields: F;
}

/** 所有 schema 的联合。注意这里只用「结构」约束，不强求 S extends Schema。 */
export type Schema =
  | StringSchema
  | NumberSchema
  | BooleanSchema
  | ArraySchema<Schema>
  | ObjectSchema<Record<string, Schema>>;

// ---------- builders：让用户不用写 as const ----------

export function string(minLength?: number): StringSchema {
  // exactOptionalPropertyTypes 下，不能把 undefined 赋给可选属性 —— 必须干脆不给这个键
  return minLength === undefined ? { kind: "string" } : { kind: "string", minLength };
}

export function number(min?: number): NumberSchema {
  return min === undefined ? { kind: "number" } : { kind: "number", min };
}

export function boolean(): BooleanSchema {
  return { kind: "boolean" };
}

export function array<S>(of: S): ArraySchema<S> {
  return { kind: "array", of };
}

export function object<F>(fields: F): ObjectSchema<F> {
  return { kind: "object", fields };
}

/**
 * 把 schema 描述成人类可读的字符串 —— 顺带演示穷尽性检查（阶段 2 课 5）。
 *
 * 如果将来给 Schema 加了一种 kind 却忘了在这里加分支，TS 会在
 * `const _never: never = schema` 那一行报错。
 */
export function describe(schema: Schema): string {
  switch (schema.kind) {
    case "string":
      return schema.minLength === undefined
        ? "string"
        : `string(minLength=${schema.minLength})`;
    case "number":
      return schema.min === undefined ? "number" : `number(min=${schema.min})`;
    case "boolean":
      return "boolean";
    case "array":
      return `array<${describe(schema.of)}>`;
    case "object": {
      const fields = Object.entries(schema.fields)
        .map(([k, v]) => `${k}: ${describe(v)}`)
        .join(", ");
      return `{ ${fields} }`;
    }
    default: {
      const _exhaustive: never = schema; // ← 穷尽性检查的落点
      return _exhaustive;
    }
  }
}
