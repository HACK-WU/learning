/** 内部类型，不打算对外暴露 */
type Mode = "fast" | "safe";

/** 对外公开的形状 */
export interface CalcOptions {
  mode: Mode;
  scale?: number;
}

export function calc(n: number, options: CalcOptions): number {
  return options.mode === "fast" ? n : n * (options.scale ?? 1);
}
