// 验收测试：node test/run.js
// 用 Node 内置 assert，零依赖。每条断言都标了它验证的是哪个知识点。

import assert from 'node:assert/strict';
import {
  TaskQueue, Semaphore, ResultCache, withTimeout, withRetry,
  TimeoutError, RetryExhaustedError, TaskError, AbortError, isRetryable,
} from '../src/index.js';
import { abortableSleep } from '../src/timeout.js';

let passed = 0;
let failed = 0;

async function test(name, fn) {
  try {
    await fn();
    passed += 1;
    console.log(`  ✅ ${name}`);
  } catch (error) {
    failed += 1;
    console.log(`  ❌ ${name}`);
    console.log(`     ${error.message}`);
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const group = (name) => console.log(`\n===== ${name} =====`);

async function main() {
  group('1. Semaphore（并发闸门）');

  await test('并发上限被严格遵守（课 3 闭包 / 课 8 Promise）', async () => {
    const sem = new Semaphore(2);
    let active = 0;
    let peak = 0;
    await Promise.all(
      Array.from({ length: 6 }, () => sem.run(async () => {
        active += 1;
        peak = Math.max(peak, active);
        await sleep(20);
        active -= 1;
      })),
    );
    assert.equal(peak, 2);
  });

  await test('非法并发数抛 RangeError（课 11 内置错误类型）', () => {
    assert.throws(() => new Semaphore(0), RangeError);
    assert.throws(() => new Semaphore(1.5), RangeError);
  });

  await test('释放函数可重复调用而不破坏计数（课 3 闭包）', async () => {
    const sem = new Semaphore(1);
    const release = await sem.acquire();
    assert.equal(sem.active, 1);
    release();
    release();                 // 第二次应当被忽略
    assert.equal(sem.active, 0);
    const r2 = await sem.acquire();
    assert.equal(sem.active, 1);
    r2();
  });

  await test('finally 保证名额一定归还（课 11 finally）', async () => {
    const sem = new Semaphore(1);
    await assert.rejects(() => sem.run(async () => { throw new Error('炸了'); }));
    assert.equal(sem.active, 0);       // 就算任务抛错，名额也还回来了
  });

  group('2. withTimeout（超时与真取消）');

  await test('超时抛 TimeoutError，且属于 TaskError（课 11 自定义错误）', async () => {
    await assert.rejects(
      () => withTimeout(() => sleep(500), 60),
      (e) => e instanceof TimeoutError && e instanceof TaskError && e instanceof Error,
    );
  });

  await test('任务提前完成时定时器被清理（课 12 泄漏 ②）', async () => {
    const started = Date.now();
    const value = await withTimeout(() => '很快', 3000);   // 超时设 3 秒
    assert.equal(value, '很快');
    const elapsed = Date.now() - started;
    // 若 finally 里没 clearTimeout，这个进程会被挂到 3 秒才结束
    assert.ok(elapsed < 500, `实际耗时 ${elapsed}ms，说明定时器没清干净`);
  });

  await test('任务能收到 signal 并真的收手（决策点 2：真取消）', async () => {
    let liveTimers = 0;
    const tracked = (ms, signal) => {
      liveTimers += 1;
      return abortableSleep(ms, signal).finally(() => { liveTimers -= 1; });
    };
    await assert.rejects(
      () => withTimeout((signal) => tracked(2000, signal), 60),
      TimeoutError,
    );
    assert.equal(liveTimers, 0, `仍有 ${liveTimers} 个底层定时器活着 —— 这是假取消`);
  });

  await test('超时抛的是 TimeoutError 而不是 AbortError（错误语义不混淆）', async () => {
    await assert.rejects(
      () => withTimeout((signal) => abortableSleep(1000, signal), 50),
      (e) => e instanceof TimeoutError && !(e instanceof AbortError),
    );
  });

  await test('非法超时时间抛 RangeError', async () => {
    await assert.rejects(() => withTimeout(() => 'x', 0), RangeError);
    await assert.rejects(() => withTimeout(() => 'x', -1), RangeError);
  });

  group('3. withRetry（重试与错误链）');

  await test('可重试的错误会重试指定次数（课 8 async/await）', async () => {
    let calls = 0;
    await assert.rejects(
      () => withRetry(async () => { calls += 1; throw new Error('总是失败'); },
        { retries: 3, shouldRetry: () => true }),
      RetryExhaustedError,
    );
    assert.equal(calls, 4);       // 1 次首发 + 3 次重试
  });

  await test('cause 串起原始错误（课 11 Error.cause）', async () => {
    try {
      await withRetry(async () => { throw new TypeError('底层真实错误'); },
        { retries: 1, shouldRetry: () => true });
      assert.fail('本应抛出');
    } catch (e) {
      assert.ok(e instanceof RetryExhaustedError);
      assert.ok(e.cause instanceof TypeError);
      assert.equal(e.cause.message, '底层真实错误');
      assert.equal(e.attempts, 2);
    }
  });

  await test('不可重试的错误原样上抛，不包装（课 11 错误边界）', async () => {
    const original = new TypeError('参数类型不对');
    let calls = 0;
    await assert.rejects(
      () => withRetry(async () => { calls += 1; throw original; },
        { retries: 5, shouldRetry: () => false }),
      (e) => e === original,          // 必须是同一个对象，不是包装后的新错误
    );
    assert.equal(calls, 1);           // 一次都没重试
  });

  await test('isRetryable 的判定符合预期', () => {
    assert.equal(isRetryable(new TimeoutError('x')), true);
    assert.equal(isRetryable(new AbortError('x')), false);
    assert.equal(isRetryable(new Error('x')), false);
  });

  group('4. ResultCache（有界 LRU）');

  await test('超过上限时淘汰最久未用的（课 9 Map 保序）', () => {
    const cache = new ResultCache({ max: 2 });
    cache.set('a', 1);
    cache.set('b', 2);
    // 此时顺序是 [a, b]，b 最新
    cache.get('a');
    // 命中后 a 挪到队尾 → 顺序变成 [b, a]，于是 **b 成了最久未用的**
    cache.set('c', 3);
    // 超上限 → 淘汰队首的 b，留下 a 和 c
    assert.equal(cache.size, 2);
    assert.equal(cache.has('a'), true);    // a 刚被访问过，保住
    assert.equal(cache.has('b'), false);   // b 最久未用，被淘汰
    assert.equal(cache.has('c'), true);
  });

  await test('缓存不会无界增长（课 12 泄漏 ④）', () => {
    const cache = new ResultCache({ max: 5 });
    for (let i = 0; i < 1000; i += 1) cache.set(`k${i}`, i);
    assert.equal(cache.size, 5);
  });

  await test('可被 for...of 遍历（课 9 Symbol.iterator）', () => {
    const cache = new ResultCache({ max: 3 });
    cache.set('x', 1); cache.set('y', 2);
    const keys = [...cache].map(([k]) => k);
    assert.deepEqual(keys, ['x', 'y']);
  });

  group('5. TaskQueue（编排器整合）');

  await test('并发上限生效（跨阶段整合）', async () => {
    const queue = new TaskQueue({ concurrency: 3 });
    let active = 0;
    let peak = 0;
    const task = async () => {
      active += 1;
      peak = Math.max(peak, active);
      await sleep(20);
      active -= 1;
      return 'ok';
    };
    await queue.runAll(Array.from({ length: 9 }, () => ({ task })));
    assert.equal(peak, 3);
  });

  await test('runAll 一个失败不影响其他（课 8 allSettled）', async () => {
    const queue = new TaskQueue({ concurrency: 2 });
    const results = await queue.runAll([
      { task: async () => '好', id: '好' },
      { task: async () => { throw new Error('坏'); }, id: '坏' },
      { task: async () => '也好', id: '也好' },
    ]);
    assert.equal(results.filter((r) => r.status === 'fulfilled').length, 2);
    assert.equal(results.filter((r) => r.status === 'rejected').length, 1);
  });

  await test('相同 cacheKey 第二次命中缓存（课 9 Map）', async () => {
    const queue = new TaskQueue({ concurrency: 1, cacheMax: 10 });
    let calls = 0;
    const task = async () => { calls += 1; return `结果#${calls}`; };
    const first = await queue.run(task, { id: 't', cacheKey: 'k' });
    const second = await queue.run(task, { id: 't', cacheKey: 'k' });
    assert.equal(first.fromCache, false);
    assert.equal(second.fromCache, true);
    assert.equal(calls, 1);                 // 底层只真的跑了一次
    assert.equal(second.value, '结果#1');
  });

  await test('stream 按完成顺序产出（课 9 生成器 / 课 4 控制反转）', async () => {
    const queue = new TaskQueue({ concurrency: 3 });
    const entries = [
      { task: () => sleep(120).then(() => '慢'), id: '慢' },
      { task: () => sleep(20).then(() => '快'), id: '快' },
      { task: () => sleep(60).then(() => '中'), id: '中' },
    ];
    const order = [];
    for await (const r of queue.stream(entries)) order.push(r.value);
    assert.deepEqual(order, ['快', '中', '慢']);   // 不是提交顺序 慢/快/中
  });

  await test('stats 反映当前状态', async () => {
    const queue = new TaskQueue({ concurrency: 1, cacheMax: 2 });
    assert.deepEqual(queue.stats, { active: 0, pending: 0, cacheSize: 0 });
    await queue.run(async () => 'x', { id: 'a', cacheKey: 'a' });
    assert.equal(queue.stats.cacheSize, 1);
  });

  group('6. 错误对象本身的性质（课 11）');

  await test('自定义错误的 name 出现在 stack 首行（课 11 实测结论）', () => {
    const e = new TimeoutError('超时啦', { taskId: 't1' });
    assert.equal(e.name, 'TimeoutError');
    assert.ok(e.stack.startsWith('TimeoutError: 超时啦'), `实际: ${e.stack.split('\n')[0]}`);
    assert.equal(e.taskId, 't1');
  });

  await test('message / stack / cause 都不可枚举（课 11 JSON.stringify 坑）', () => {
    const e = new TaskError('外层', { cause: new Error('根因') });
    assert.deepEqual(Object.keys(e), ['name', 'taskId']);
    assert.equal(JSON.stringify(e).includes('根因'), false);
    assert.equal(e.cause.message, '根因');
  });

  group('7. this 绑定（课 5）');

  await test('方法提取出来后 this 丢失 —— 必须用 bind 修复', async () => {
    const queue = new TaskQueue({ concurrency: 1 });
    const ok = await queue.run(async () => '正常', { id: 'x' });
    assert.equal(ok.value, '正常');

    await assert.rejects(
      () => {
        const run = queue.run;          // 「点」没了 → this 丢失
        return run(async () => '应该失败', { id: 'y' });
      },
      TypeError,
    );

    // 修复方式
    const bound = queue.run.bind(queue);
    const fixed = await bound(async () => '修好了', { id: 'z' });
    assert.equal(fixed.value, '修好了');
  });

  console.log(`\n===== 结果：${passed} 通过 / ${failed} 失败 =====`);
  if (failed > 0) process.exitCode = 1;
}

main();
