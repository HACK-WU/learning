// 订单服务的欢迎语。类型错得离谱，但语法完全合法 —— 这正是要命的地方。
interface User {
  profile: { name: string };
}

function greet(user: User): string {
  return "hello, " + user.profile.name;
}

// ❌ 类型错误：profile 是 null，不是 { name: string }
//    tsc 会拦下它；只转译不检查的工具链会一路放行，直到运行时炸掉
const currentUser = { profile: null };

console.log(greet(currentUser));
