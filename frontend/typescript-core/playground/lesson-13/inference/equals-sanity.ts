// 负向对照：证明 Equals 这套判定真的会「抓错」，不是永远返回 true
type Equals<X, Y> =
  (<T>() => T extends X ? 1 : 2) extends (<T>() => T extends Y ? 1 : 2) ? true : false;
type Expect<T extends true> = T;

type Last<T extends unknown[]> = T extends [...infer _Rest, infer L] ? L : never;

// ✅ 正确：Last<[1,2,3]> 确实是 3
type _ok = Expect<Equals<Last<[1, 2, 3]>, 3>>;

// ❌ 故意写错：期望 4，实际是 3 —— 这一行必须报错，否则前面的断言都不可信
// @ts-expect-error 故意写错，用于验证判定有效
type _wrong = Expect<Equals<Last<[1, 2, 3]>, 4>>;

// ❌ 再试一个更隐蔽的：never 与 any 不能被混过
// @ts-expect-error never 不等于 undefined
type _wrong2 = Expect<Equals<never, undefined>>;
