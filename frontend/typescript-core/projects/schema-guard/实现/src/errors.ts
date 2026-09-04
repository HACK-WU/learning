/**
 * 严格模式下的自定义错误（阶段 2 课 6 / 阶段 4 课 12）。
 *
 * 它只在 `assert()` / `parseOrThrow()` 里被抛出；默认的 `parse()` 返回
 * Result 而不抛异常 —— 这是本项目的决策点 1，详见 `设计决策.md`。
 */
export class SchemaGuardError extends Error {
  /** 全部校验错误，一条不落（不是"遇到第一个就停"） */
  readonly errors: readonly { path: string; message: string }[];

  constructor(errors: readonly { path: string; message: string }[]) {
    super(SchemaGuardError.format(errors));
    // 课 12 强调过：不写 name，栈首行会显示成 "Error:"，扫日志时认不出来
    this.name = "SchemaGuardError";
    this.errors = errors;
  }

  private static format(errors: readonly { path: string; message: string }[]): string {
    if (errors.length === 0) return "validation failed (no detail)";
    const lines = errors.map((e) => `  - ${e.path === "" ? "<root>" : e.path}: ${e.message}`);
    return `validation failed with ${errors.length} error(s):\n${lines.join("\n")}`;
  }
}
