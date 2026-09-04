// 课 7 · 补测：abstract 编译后还在吗？运行时能被 new 吗？
export class Shape {
    describe() {
        return `area = ${this.area()}`;
    }
}
export class Square extends Shape {
    size;
    constructor(size) {
        super();
        this.size = size;
    }
    area() {
        return this.size * this.size;
    }
}
