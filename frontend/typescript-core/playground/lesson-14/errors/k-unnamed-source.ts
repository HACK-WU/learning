// 源类型没有名字（是内联推断出来的大结构），TS 只能把整个结构拼进一行打出来。
// 这是让报错「看起来很长」的头号原因 —— 不是它有很多行，是它有一行极长。

declare function buildAppConfig(): {
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
};

// 把这么大一个结构赋给 string —— 报错会把左边整个结构逐字打出来
export const asString: string = buildAppConfig();
