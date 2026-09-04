// 候选 F：赋值给一个「内联的深度结构」—— TS 没法用一个类型名概括，只能把结构摊开
declare let config: {
  database: { host: string; port: number; pool: { min: number; max: number } };
  cache: { ttl: number; layers: Array<{ name: string; size: number }> };
  flags: { beta: boolean; experimental: { a: string; b: number } };
};

config = {
  database: { host: "localhost", port: 5432, pool: { min: 1, max: "10" } },
  cache: { ttl: 60, layers: [{ name: "l1", size: 100 }] },
  flags: { beta: true, experimental: { a: "x", b: 1 } },
};
