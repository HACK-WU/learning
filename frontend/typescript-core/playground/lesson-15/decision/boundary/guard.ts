// 方案二：类型 + 运行时校验（类型守卫）—— 外部数据在边界处被拦下
interface User {
  profile: { name: string };
}

// 运行时校验：真正去看数据的形状，并把它收窄成 User（课 5 的类型守卫）
function isUser(value: unknown): value is User {
  if (typeof value !== "object" || value === null) return false;
  if (!("profile" in value)) return false;
  const profile = (value as { profile: unknown }).profile;
  if (typeof profile !== "object" || profile === null) return false;
  return "name" in profile && typeof profile.name === "string";
}

const payload: unknown = JSON.parse('{"profile": null}');

if (!isUser(payload)) {
  // 编译：✅ 通过。运行：给出清晰的错误，而不是崩在半路
  throw new Error("invalid user payload from API");
}

console.log("hello, " + payload.profile.name);
