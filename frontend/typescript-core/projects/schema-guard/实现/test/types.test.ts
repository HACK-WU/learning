/**
 * 类型测试：把「schema 应该推出什么类型」钉死（阶段 5 课 13）。
 *
 * 用业界通用的 Equals 惯用法，而不是 `extends` —— 因为 `never` / `any`
 * 会让 `extends` 蒙混过关（课 13 实测过）。
 */
import type { Infer } from "../src/infer.js";
import { array, boolean, number, object, string } from "../src/schema.js";

type Equals<X, Y> =
  (<T>() => T extends X ? 1 : 2) extends <T>() => T extends Y ? 1 : 2 ? true : false;
type Expect<T extends true> = T;

// ---- 标量 ----
type _1 = Expect<Equals<Infer<ReturnType<typeof string>>, string>>;
type _2 = Expect<Equals<Infer<ReturnType<typeof number>>, number>>;
type _3 = Expect<Equals<Infer<ReturnType<typeof boolean>>, boolean>>;

// ---- 组合：本项目真正要的能力 ----
const userSchema = object({
  name: string(1),
  age: number(0),
  active: boolean(),
  tags: array(string()),
  profile: object({
    email: string(),
    level: number(),
  }),
});

type User = Infer<typeof userSchema>;

type _4 = Expect<
  Equals<
    User,
    {
      name: string;
      age: number;
      active: boolean;
      tags: string[];
      profile: { email: string; level: number };
    }
  >
>;

// ---- 负向对照：证明这套判定真的会抓错 ----
// @ts-expect-error 故意写错：age 是 number 不是 string
type _5 = Expect<Equals<User["age"], string>>;

// ---- 运行时校验后收窄出来的值，类型必须正确 ----
import { parse } from "../src/parse.js";

const result = parse(userSchema, {
  name: "amy",
  age: 18,
  active: true,
  tags: ["a"],
  profile: { email: "a@b.c", level: 2 },
});

if (result.ok) {
  // 收窄之后，value 必须精确等于推导出来的 User
  type _6 = Expect<Equals<typeof result.value, User>>;
  const n: number = result.value.age; // 若推导失败，这一行就会报错
  void n;
}

// 未使用类型变量在 noUnusedLocals 下可能报警，显式引用一次
type __all = [_1, _2, _3, _4, _5];
