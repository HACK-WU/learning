// 课 10 · target 对比：不同 target 对产物的降级程度
class Counter {
  #count = 0;
  increment(): void {
    this.#count += 1;
  }
  get value(): number {
    return this.#count;
  }
}

const list = [1, 2, 3];
const counter = new Counter();
counter.increment();

export const result = { last: list.at(-1), count: counter.value };
