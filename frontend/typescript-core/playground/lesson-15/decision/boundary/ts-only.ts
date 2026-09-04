// 方案一：只有编译期类型（断言）—— 外部数据它管不住
interface User {
  profile: { name: string };
}

// 模拟从网络拿到的数据：运行时是什么形状，编译器一无所知
const payload: unknown = JSON.parse('{"profile": null}');

// 断言 = 「我向编译器保证」。编译器信了，然后什么都不做（课 6 / 课 11）
const user = payload as User;

// 编译：✅ 通过。运行：💥 崩
console.log("hello, " + user.profile.name);
