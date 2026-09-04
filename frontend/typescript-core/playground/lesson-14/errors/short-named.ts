// 与 k-unnamed-source.ts 完全相同的结构，唯一区别是：这个类型「有名字」。
// 有名字之后，TS 在报错里直接写类型名，一行就完事了 —— 不用把结构摊开。

interface AppConfig {
  database: {
    host: string;
    port: number;
    pool: { min: number; max: number; idleTimeout: number };
    replica: { host: string; lag: number; weight: number };
  };
  cache: {
    ttl: number;
    layers: Array<{ name: string; size: number; evict: "lru" | "lfu" }>;
    fallback: { enabled: boolean; threshold: number };
  };
  flags: {
    beta: boolean;
    experimental: { a: string; b: number; c: boolean };
    rollout: { percent: number; cohorts: string[] };
  };
  logging: {
    level: "debug" | "info" | "error";
    sinks: Array<{ type: "console" | "file"; path: string; rotate: boolean }>;
  };
  security: {
    cors: { origins: string[]; credentials: boolean };
    rateLimit: { rpm: number; burst: number; keyBy: "ip" | "user" };
  };
}

declare function buildAppConfig(): AppConfig;

export const asString: string = buildAppConfig();
