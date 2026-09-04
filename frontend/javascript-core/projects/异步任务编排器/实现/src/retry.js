// 重试 —— 回扣课 8 async/await + 课 11 cause 错误链 + 课 11 错误边界
//
// 错误边界的分工在这里体现得很清楚：
//   · 不可重试的错误 → 原样上抛（我什么都做不了，就别接）
//   · 重试耗尽        → 加上下文 + cause，再抛给上层决策

import { RetryExhaustedError } from './errors.js';

/**
 * @param {(attempt: number) => any} fn 每次尝试都会调用它，参数是第几次尝试（从 0 开始）
 * @param {object} options
 * @param {number} [options.retries=0] 额外重试次数（0 表示不重试，总共只跑 1 次）
 * @param {(error: Error) => boolean} [options.shouldRetry] 判断某个错误值不值得重试
 */
export async function withRetry(fn, { retries = 0, shouldRetry, taskId = null } = {}) {
  if (!Number.isInteger(retries) || retries < 0) {
    throw new RangeError(`重试次数必须是 ≥ 0 的整数，收到：${retries}`);
  }

  let lastError = null;

  for (let attempt = 0; attempt <= retries; attempt += 1) {
    try {
      return await fn(attempt);
    } catch (error) {
      lastError = error;

      // ① 明确不可重试 → 原样上抛，不包装、不加戏
      //    课 11 结论：什么都做不了的时候，catch 只会让错误从「能被发现」变成「只能靠猜」
      if (shouldRetry && !shouldRetry(error)) throw error;

      // ② 还有次数 → 继续下一轮
      if (attempt < retries) continue;
    }
  }

  // ③ 次数耗尽 → 包一层再抛，用 cause 保留最后一次的真实错误（课 11 知识点 1）
  throw new RetryExhaustedError(`重试 ${retries} 次后仍然失败`, {
    cause: lastError,
    taskId,
    attempts: retries + 1,
  });
}
