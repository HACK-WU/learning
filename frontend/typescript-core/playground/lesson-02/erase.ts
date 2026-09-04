// 课 2 · 补测 B：只读与元组的「运行时不设防」

export const STATUS: readonly string[] = ["pending", "paid", "refunded"];
export const ROW: readonly [id: string, score: number] = ["u1", 98];
export const CONFIG = { mode: "dev", retries: 3 } as const;
