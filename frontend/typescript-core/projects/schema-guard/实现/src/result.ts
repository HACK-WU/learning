/**
 * 校验结果：一个判别式联合（阶段 2 课 4 / 课 5）。
 *
 * 用 `ok` 做判别式，调用方必须判断 `ok` 才能拿到 `value` —— 这就是
 * 「让编译器逼你处理失败」，而不是靠注释提醒。
 */
export type ParseResult<T> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly errors: readonly ParseError[] };

/** 单条校验错误：带路径，便于定位到具体字段 */
export interface ParseError {
  readonly path: string;
  readonly message: string;
}

export function ok<T>(value: T): ParseResult<T> {
  return { ok: true, value };
}

export function err<T>(errors: readonly ParseError[]): ParseResult<T> {
  return { ok: false, errors };
}

/** 在子路径上追加前缀，让错误路径完整（如 `user.profile.name`） */
export function withPath(errors: readonly ParseError[], prefix: string): readonly ParseError[] {
  return errors.map((e) => ({
    path: prefix === "" ? e.path : `${prefix}.${e.path}`,
    message: e.message,
  }));
}
