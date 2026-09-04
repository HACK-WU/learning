// 自定义错误体系 —— 回扣课 11《错误处理与调试》知识点 1
//
// 三个设计要点（都是课 11 实测过的结论）：
// 1. 必须写 this.name，否则 e.stack 首行会显示成 "Error:"（课 11 实测）
// 2. 必须 extends Error，否则 catch 到的东西没有 stack（课 11 实测 throw 原始值的坑）
// 3. 用 cause 把「原始错误」挂在包装错误上，形成可追溯的错误链（ES2022）

/** 所有任务错误的基类 */
export class TaskError extends Error {
  constructor(message, options = {}) {
    // 整个 options 交给 Error —— 它会自己取出 cause 字段
    super(message, options);
    this.name = 'TaskError';
    this.taskId = options.taskId ?? null;
  }
}

/** 任务超时 */
export class TimeoutError extends TaskError {
  constructor(message, options = {}) {
    super(message, options);
    this.name = 'TimeoutError';
  }
}

/** 任务被主动取消 */
export class AbortError extends TaskError {
  constructor(message, options = {}) {
    super(message, options);
    this.name = 'AbortError';
  }
}

/** 重试次数耗尽（它的 cause 就是最后一次的真实错误） */
export class RetryExhaustedError extends TaskError {
  constructor(message, options = {}) {
    super(message, options);
    this.name = 'RetryExhaustedError';
    this.attempts = options.attempts ?? 0;
  }
}

/**
 * 判断一个错误是否值得重试 —— 复用到课 11 的「错误边界」思路：
 * 能判定的才判定，判不定的一律不重试（不擅自吞掉错误）。
 */
export function isRetryable(error) {
  // 超时可以重试：多半是偶发抖动
  if (error instanceof TimeoutError) return true;
  // 被主动取消不该重试：那是使用者自己的决定
  if (error instanceof AbortError) return false;
  // 其余一概不重试 —— 宁可保守，也不要把「参数写错」重放十遍
  return false;
}
