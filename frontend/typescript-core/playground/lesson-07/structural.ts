// 课 7 · 知识点 3：类的结构化兼容与 this 类型

// ① this 类型：返回值写 this，子类调用时自动变成子类类型
class QueryBuilder {
  protected conditions: string[] = [];

  where(cond: string): this {
    this.conditions.push(cond);
    return this;
  }

  build(): string {
    return this.conditions.join(" AND ");
  }
}

class OrderQuery extends QueryBuilder {
  onlyPaid(): this {
    return this.where("status = 'paid'");
  }
}

// 链式调用：每一步都保留真实的子类类型
const query = new OrderQuery().onlyPaid().where("amount > 100");
console.log(query.build());

// ② 结构化兼容：形状对就能赋值（与课 3 的对象规则一致）
class Point2D {
  constructor(
    public x: number,
    public y: number,
  ) {}
}
class Coordinate {
  constructor(
    public x: number,
    public y: number,
  ) {}
}
const asPoint: Point2D = new Coordinate(1, 2); // ✅ 没人声明过它们有关系
console.log(asPoint);
