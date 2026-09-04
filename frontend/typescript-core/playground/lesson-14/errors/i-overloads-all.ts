// 候选 I：所有重载签名都失败 —— TS 会逐条列出失败原因
interface Formatter {
  (v: string, opt: { upper: boolean }): string;
  (v: number, opt: { precision: number }): string;
  (v: Date, opt: { iso: boolean }): string;
}

declare const fmt: Formatter;

export const r = fmt(true, { upper: true });
