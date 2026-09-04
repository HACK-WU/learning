// 并发闸门（Semaphore）—— 回扣课 3 闭包 + 课 6 class 与私有字段 + 课 5 箭头函数
//
// 职责：同时最多放行 N 个任务，超出的排队等。
// 这是「决策点 1」选中方案的落地（详见 ../设计决策.md）。

export class Semaphore {
  #limit;          // 最大并发数
  #active = 0;     // 当前正在跑的数量
  #waiting = [];   // 等待队列（存的是「唤醒函数」）

  constructor(concurrency) {
    // 课 11：参数不合法就抛 RangeError，而不是悄悄改成默认值
    if (!Number.isInteger(concurrency) || concurrency < 1) {
      throw new RangeError(`并发数必须是 ≥ 1 的整数，收到：${concurrency}`);
    }
    this.#limit = concurrency;
  }

  get active() { return this.#active; }
  get pending() { return this.#waiting.length; }

  /**
   * 取得一个执行名额。
   * @returns {Promise<Function>} 一个「释放函数」，用完必须调用
   */
  async acquire() {
    // 还有名额：立刻放行
    if (this.#active < this.#limit) {
      this.#active += 1;
      return this.#makeRelease();
    }

    // 名额用完：把「唤醒函数」排进队列，等别人释放时叫醒我（课 8 Promise）
    return new Promise((resolve) => {
      this.#waiting.push(() => {
        this.#active += 1;
        resolve(this.#makeRelease());
      });
    });
  }

  /**
   * 造一个「只能生效一次」的释放函数。
   * 课 3 闭包：released 这个变量活在函数返回之后，用来防重复释放。
   */
  #makeRelease() {
    let released = false;
    // 课 5 知识点 2：用箭头函数，这样无论被谁拿着调用，this 都还是这个 Semaphore
    return () => {
      if (released) return;
      released = true;
      this.#release();
    };
  }

  #release() {
    this.#active -= 1;
    const next = this.#waiting.shift();   // FIFO：先来的先走
    if (next) next();
  }

  /**
   * 便捷方法：包一层，保证 finally 里一定还名额。
   * 课 11 知识点 2：finally 只做清理，绝不写 return/throw。
   */
  async run(fn) {
    const release = await this.acquire();
    try {
      return await fn();
    } finally {
      release();
    }
  }
}
