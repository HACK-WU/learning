// 课 3 · 知识点 3：类型断言 as 与 satisfies

type Method = "GET" | "POST";
type Req = { method: Method; url: string };

// ① 类型注解：类型被固定成 Req，"我写的是 GET" 这个信息丢了
const byAnnotation: Req = { method: "GET", url: "/users" };

// ② satisfies：既要合规检查，又要保留"我写的就是 GET"
const bySatisfies = { method: "GET", url: "/users" } satisfies Req;

// ③ 关键差异：satisfies 保留了 "GET" 这个字面量类型
const methodFromSatisfies: "GET" = bySatisfies.method; // ✅ 通过
// const methodFromAnnotation: "GET" = byAnnotation.method; // ❌ 见 assertions-probe.ts

// ④ satisfies 不合规会当场拦下（as 不会）
// const bad = { method: "PUT", url: "/users" } satisfies Req;

console.log(byAnnotation, bySatisfies, methodFromSatisfies);
