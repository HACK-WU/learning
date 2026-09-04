// 任务编排器主体 —— 把四个模块焊起来的地方
// 回扣：课 4 高阶函数、课 5 this、课 8 Promise/async、课 9 生成器与 Map、课 10 ESM、课 11 错误边界

import { Semaphore } from './semaphore.js';
import { withTimeout } from './timeout.js';
import { withRetry } from './retry.js';
import { ResultCache } from './cache.js';
import { isRetryable } from './errors.js';

export { Semaphore } from './semaphore.js';
export { withTimeout, abortableSleep } from './timeout.js';
export { withRetry } from './retry.js';
export { ResultCache } from './cache.js';
export * from './errors.js';

export class TaskQueue {
  #semaphore;
  #defaults;
  #cache;

  /**
   * @param {object} [options]
   * @param {number} [options.concurrency=4] 最大并发数
   * @param {number|null} [options.timeout=null] 默认超时（毫秒），null 表示不限时
   * @param {number} [options.retries=0] 默认额外重试次数
   * @param {number} [options.cacheMax=0] 结果缓存上限，0 表示不缓存
   * @param {(e: Error) => boolean} [options.shouldRetry=isRetryable] 默认的可重试判定
   */
  constructor({
    concurrency = 4,
    timeout = null,
    retries = 0,
    cacheMax = 0,
    shouldRetry = isRetryable,
  } = {}) {
    this.#semaphore = new Semaphore(concurrency);
    this.#defaults = { timeout, retries, shouldRetry };
    // 课 12：缓存必须有上限。cacheMax=0 就是明确「不缓存」，而不是「无限缓存」
    this.#cache = cacheMax > 0 ? new ResultCache({ max: cacheMax }) : null;
  }

  get stats() {
    return {
      active: this.#semaphore.active,
      pending: this.#semaphore.pending,
      cacheSize: this.#cache?.size ?? 0,
    };
  }

  get cache() { return this.#cache; }

  /**
   * 跑一个任务。
   * @param {(signal: AbortSignal|null) => any} task
   * @param {object} [options] id / timeout / retries / shouldRetry / cacheKey
   */
  async run(task, options = {}) {
    const {
      id = null,
      timeout = this.#defaults.timeout,
      retries = this.#defaults.retries,
      shouldRetry = this.#defaults.shouldRetry,
      cacheKey = null,
    } = options;

    // ① 命中缓存就直接返回，连闸门都不进（省一次并发名额）
    if (cacheKey !== null && this.#cache?.has(cacheKey)) {
      return { taskId: id, value: this.#cache.get(cacheKey), fromCache: true, attempts: 0 };
    }

    // ② 进并发闸门 —— 用 semaphore.run 包住，finally 里一定还名额
    return this.#semaphore.run(async () => {
      let attempts = 0;

      const runOnce = () => {
        attempts += 1;
        const job = (signal) => task(signal);        // 课 4：task 是被传来传去的一等公民
        return timeout == null ? job(null) : withTimeout(job, timeout, { taskId: id });
      };

      const value = retries > 0
        ? await withRetry(runOnce, { retries, shouldRetry, taskId: id })
        : await runOnce();

      if (cacheKey !== null) this.#cache?.set(cacheKey, value);
      return { taskId: id, value, fromCache: false, attempts };
    });
  }

  /**
   * 批量跑：一个失败不影响其他。
   * 课 8：allSettled 与 all 的区别 —— all 会在第一个失败时 reject，
   * 但**其余任务并没有被取消**，只是它们的结果被丢弃了。
   */
  async runAll(entries) {
    return Promise.allSettled(entries.map((entry) => this.#normalize(entry)));
  }

  /**
   * 按「完成顺序」逐个产出结果（不是提交顺序）。
   * 课 9 生成器 + 课 8 Promise.race：谁先好谁先出来。
   */
  async *stream(entries) {
    // 先把每个任务包成「永不 reject」的 Promise，避免 race 被某一个失败直接打断
    const pending = new Map();
    entries.forEach((entry, index) => {
      const p = this.#normalize(entry).then(
        (result) => ({ index, result }),
        (error) => ({ index, error }),
      );
      pending.set(index, p);
    });

    while (pending.size > 0) {
      const settled = await Promise.race(pending.values());
      pending.delete(settled.index);
      if ('error' in settled) throw settled.error;   // 课 11：边界层才决定怎么对待失败
      yield settled.result;
    }
  }

  #normalize(entry) {
    return typeof entry === 'function'
      ? this.run(entry)
      : this.run(entry.task, { id: entry.id ?? null, ...entry });
  }
}
