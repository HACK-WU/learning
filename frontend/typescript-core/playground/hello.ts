// 课 1 示例：类型擦除的证据
function greet(name: string): string {
  return `你好，${name}！`;
}

const message: string = greet("TypeScript");
console.log(message);

interface User {
  id: number;
  name: string;
  isAdmin: boolean;
}

const u: User = { id: 1, name: "Alice", isAdmin: true };
console.log(u);

// 类也会被降级/保留，取决于 target
class Order {
  readonly id: number;
  constructor(id: number) {
    this.id = id;
  }
}
console.log(new Order(42));
