// 演示脚本：node examples/demo.js
// 六个场景，逐个对应课程里的知识点

import { TaskQueue, TimeoutError, RetryExhaustedError, TaskError } from '../src/index.js';
import { abortableSleep } from '../src/timeout.js';

const line = (s = '') => console.log(s);
const title = (s) => console.log(`\n===== ${s} =====`);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const job = (id, ms) => () => sleep(ms).then(() => `${id}(${ms}ms)`);

async function main() {
  title('场景 1：并发限制 —— 4 个任务，最多同时跑 2 个');
  {
    const queue = new TaskQueue({ concurrency: 2 });
    const started = Date.now();
    const results = await queue.runAll([
      { task: job('A', 100), id: 'A' },
      { task: job('B', 50), id: 'B' },
      { task: job('C', 120), id: 'C' },
      { task: job('D', 30), id: 'D' },
    ]);
    const elapsed = Date.now() - started;
    for (const r of results) {
      line(`  ${r.status === 'fulfilled' ? '✅' : '❌'} ${String(r.value.taskId).padEnd(2)} → ${r.value.value}`);
    }
    line(`  实际耗时约 ${elapsed}ms（串行会是 ${100 + 50 + 120 + 30}ms）`);
    line(`  → 回扣课 7 事件循环 + 课 8 Promise.allSettled`);
  }

  title('场景 2：超时 —— 任务 500ms，只给 100ms');
  {
    const queue = new TaskQueue({ concurrency: 1 });
    const [r] = await queue.runAll([{ task: job('慢任务', 500), id: '慢任务', timeout: 100 }]);
    line(`  状态: ${r.status}`);
    line(`  错误: ${r.reason.name} — ${r.reason.message}`);
    line(`  instanceof TimeoutError: ${r.reason instanceof TimeoutError}`);
    line(`  instanceof TaskError   : ${r.reason instanceof TaskError}`);
    line(`  stack 首行             : ${r.reason.stack.split('\n')[0]}`);
    line(`  → 回扣课 11：只有 throw Error 子类才带得走 stack`);
  }

  title('场景 3：真取消 vs 假取消 —— 底层定时器到底有没有被清掉');
  {
    const queue = new TaskQueue({ concurrency: 1 });
    let liveTimers = 0;

    // 包装一层，用来「数」底层到底还有几个定时器活着
    const tracked = (ms, signal) => {
      liveTimers += 1;
      return abortableSleep(ms, signal).finally(() => { liveTimers -= 1; });
    };

    // ① 真取消：任务把 signal 用起来，收到通知就自己清理
    liveTimers = 0;
    try {
      await queue.run((signal) => tracked(2000, signal), { id: '尊重 signal', timeout: 80 });
    } catch (e) {
      line(`  [真取消] 外层收到: ${e.name} — ${e.message}`);
    }
    line(`  [真取消] 超时后仍活着的底层定时器: ${liveTimers}  ← 立刻归零，资源马上释放`);

    // ② 假取消：任务不理会 signal，被 Promise.race 甩在身后，自己还在倒数
    //    （重新计数：不然会把上面那次的结果累加进来，看不出差别）
    liveTimers = 0;
    try {
      await queue.run(() => tracked(600, undefined), { id: '不理会 signal', timeout: 80 });
    } catch (e) {
      line(`  [假取消] 外层收到: ${e.name} — ${e.message}`);
    }
    line(`  [假取消] 超时后仍活着的底层定时器: ${liveTimers}  ← 它还在后台倒数 600ms`);
    line(`  → 你会感觉到脚本在结尾多停了半秒才退出 —— 那就是白占的资源`);
    line(`  → 回扣课 12 泄漏 ②：不清理的定时器会把整个回调闭包一直留着`);
    line(`  → 关键差别不在 Promise.race，而在「任务自己收不收手」`);
  }

  title('场景 4：重试 + cause 错误链');
  {
    const queue = new TaskQueue({ concurrency: 1 });
    let calls = 0;
    const flaky = () => {
      calls += 1;
      return sleep(10).then(() => { throw new Error(`第 ${calls} 次调用失败`); });
    };
    try {
      await queue.run(flaky, { id: '抖动任务', retries: 3, shouldRetry: () => true });
    } catch (e) {
      line(`  实际调用次数: ${calls}（1 次首发 + 3 次重试）`);
      line(`  外层收到: ${e.name} — ${e.message}`);
      line(`  instanceof RetryExhaustedError: ${e instanceof RetryExhaustedError}`);
      line(`  错误链: ${e.message} ← ${e.cause.message}`);
      line(`  → 回扣课 11：cause 把「原始错误」挂在包装错误上`);
    }

    line('');
    line('  —— 对照：不可重试的错误会被原样上抛，不包装 ——');
    try {
      await queue.run(() => Promise.reject(new TypeError('参数类型不对')), {
        id: '参数错误', retries: 3, shouldRetry: () => false,
      });
    } catch (e) {
      line(`  外层收到: ${e.name} — ${e.message}`);
      line(`  还是 RetryExhaustedError 吗: ${e instanceof RetryExhaustedError}`);
      line(`  → 回扣课 11 错误边界：做不了就别接，让它原样往上冒`);
    }
  }

  title('场景 5：缓存命中与 LRU 淘汰');
  {
    const queue = new TaskQueue({ concurrency: 1, cacheMax: 2 });   // 上限故意设成 2
    const mk = (id) => ({ task: job(id, 10), id, cacheKey: id });

    await queue.run(mk('X').task, mk('X'));
    await queue.run(mk('Y').task, mk('Y'));
    line(`  放入 X、Y 后 cacheSize = ${queue.cache.size}`);

    await queue.run(mk('Z').task, mk('Z'));   // 超上限 → 淘汰最久未用的 X
    line(`  放入 Z 后 cacheSize = ${queue.cache.size}（上限 2，最久未用的被淘汰）`);
    line(`  X 还在吗: ${queue.cache.has('X')}`);
    line(`  Y 还在吗: ${queue.cache.has('Y')}`);

    const again = await queue.run(mk('Z').task, mk('Z'));
    line(`  再跑一次 Z → fromCache = ${again.fromCache}, attempts = ${again.attempts}`);
    line(`  → 回扣课 9 Map 保序 + 课 12：有界缓存 vs 无界 Map（后者会泄漏）`);
  }

  title('场景 6：stream —— 按「完成顺序」产出，不是提交顺序');
  {
    const queue = new TaskQueue({ concurrency: 3 });
    const entries = [
      { task: job('慢', 150), id: '慢' },
      { task: job('快', 20), id: '快' },
      { task: job('中', 80), id: '中' },
    ];
    const order = [];
    for await (const r of queue.stream(entries)) order.push(r.taskId);
    line(`  提交顺序: 慢 → 快 → 中`);
    line(`  产出顺序: ${order.join(' → ')}`);
    line(`  → 回扣课 9 生成器 + 课 4 控制反转：谁先完成谁先出来`);
  }

  title('场景 7：this 陷阱 —— 把 queue.run 提取出来会怎样');
  {
    const queue = new TaskQueue({ concurrency: 1 });
    const ok = await queue.run(job('正常', 10), { id: '正常' });
    line(`  正常调用          → ${ok.value}`);
    try {
      const run = queue.run;          // ← 课 5：只把方法拿出来，「点」没了
      await run(job('提取后', 10), { id: '提取后' });
    } catch (e) {
      line(`  提取成裸函数后调用 → ${e.name}: ${e.message}`);
      line(`  → 回扣课 5 隐式丢失：this 看调用点，不看出生地`);
      line(`     修复：const run = queue.run.bind(queue)`);
    }
  }

  line('\n===== 演示结束 =====');
}

main().catch((e) => {
  console.error('演示脚本自己炸了：', e);
  process.exitCode = 1;
});
