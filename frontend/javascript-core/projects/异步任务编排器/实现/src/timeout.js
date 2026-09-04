// 超时控制 —— 回扣课 8 Promise.race + 课 11 finally + 课 12 定时器泄漏
//
// 这是「决策点 2」的落地：Promise.race 负责「判定超时」，AbortController 负责「真正取消」。
// 两者缺一不可 —— 只有前者是「假取消」，底层任务还在跑（详见 ../设计决策.md）。

import { TimeoutError, AbortError } from './errors.js';

/**
 * 给一个任务套上超时。
 * @param {(signal: AbortSignal) => any} task 任务；**接受一个 signal 参数**，可用可不用
 * @param {number} ms 超时毫秒数
 */
export async function withTimeout(task, ms, { taskId = null } = {}) {
  if (!Number.isFinite(ms) || ms <= 0) {
    throw new RangeError(`超时时间必须是正数，收到：${ms}`);
  }

  let timer = null;
  const controller = new AbortController();

  const timeoutPromise = new Promise((_resolve, reject) => {
    timer = setTimeout(() => {
      // 关键：超时时**同时**做两件事，且顺序有讲究
      reject(new TimeoutError(`任务超时（${ms}ms）`, { taskId }));  // ① 先让 race 判定为「超时」
      controller.abort();                                    // ② 再通知任务收手（真取消）
      //
      // 为什么这个顺序：controller.abort() 会**同步**触发任务的 abort 监听，
      // 任务随即 reject(AbortError)。若先 abort，race 就会先拿到 AbortError，
      // 上层就分不清「超时」和「主动取消」了 —— 两者在课 11 的错误边界里是不同的决策。
    }, ms);
  });

  try {
    // 用 Promise.resolve().then() 包一层，让 task 在微任务里启动，行为更一致（课 7 事件循环）
    const taskPromise = Promise.resolve().then(() => task(controller.signal));
    return await Promise.race([taskPromise, timeoutPromise]);
  } finally {
    // 课 12 泄漏 ②：定时器一定要清。
    // 不清理的话，即便任务 10ms 就跑完了，这个定时器也会把回调闭包一直留到触发为止。
    if (timer !== null) clearTimeout(timer);
  }
}

/**
 * 一个「尊重 signal」的 sleep —— 演示任务怎么配合 AbortController 做到真取消。
 * 对比：普通 sleep 被超时打断后，它自己还在倒数，资源照样占着。
 */
export function abortableSleep(ms, signal) {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) {
      reject(new AbortError('任务在启动前就已被取消'));
      return;
    }

    const timer = setTimeout(() => {
      cleanup();
      resolve(`睡了 ${ms}ms`);
    }, ms);

    const onAbort = () => {
      cleanup();
      reject(new AbortError(`任务在 ${ms}ms 的等待中被取消`));
    };

    function cleanup() {
      clearTimeout(timer);
      signal?.removeEventListener('abort', onAbort);   // 课 12 泄漏 ②：监听器也要解绑
    }

    signal?.addEventListener('abort', onAbort, { once: true });
  });
}
