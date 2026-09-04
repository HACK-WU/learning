// 课 7 · 补测：abstract 编译后还在吗？运行时能被 new 吗？

export abstract class Shape {
  abstract area(): number;
  describe(): string {
    return `area = ${this.area()}`;
  }
}

export class Square extends Shape {
  constructor(private size: number) {
    super();
  }
  area(): number {
    return this.size * this.size;
  }
}
