// ⚠️ 反面教材：能跑通 happy path，但处处是坑。
// 运行：node examples/bad-queue.js
// 逐条对照见 ../反例对照.md
//
// 这个文件的每一个 BAD 标记，都对应课程里的一个知识点。

// 先装一个兜底 —— 否则这个脚本在第 2 步就会直接崩溃（退出码 1）。
// 这正是课 11 知识点 2 ④ 讲的两套全局兜底之一。
let caughtByGuard = null;
process.on('unhandledRejection', (reason) => { caughtByGuard = reason; });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  console.log('===== 反例：一个「能跑」的任务队列 =====\n');

  const jobs = [['A', 60], ['B', 30], ['C', 90], ['D', 20]];
  const results = [];

  console.log('--- BAD 1~3：并发、错误捕获、抛什么 ---');

  // ❌ BAD 1：没有并发上限，一次性全部发出去。
  //    4 个任务就是 4 个并发；4 万个任务就是 4 万个 —— 直接把下游打崩。
  try {
    // ❌ BAD 2：try/catch 包在 forEach 外面，自以为能接住错误。
    //    forEach 只是同步地把回调挨个调一遍，它不 await 任何东西；
    //    错误发生在回调里的 await 之后，那时 try 所在的函数早就跑完了（课 11 知识点 2）。
    jobs.forEach(async ([id, ms]) => {
      if (ms > 80) {
        // ❌ BAD 3：抛的是字符串，不是 Error —— 没有 message、没有 stack
        throw `${id} 太慢了`;
      }
      await sleep(ms);
      results.push(id);
    });
  } catch (e) {
    console.log('  接住了：', e);   // ← 永远不会执行
  }

  await sleep(200);

  console.log('  完成的（顺序随机）:', results.join(', ') || '(空)');
  console.log('  兜底接到的:', caughtByGuard === null ? '(无)' : String(caughtByGuard));
  console.log('  ↑ C 失败了，但主流程毫发无伤地继续跑完 —— 错误被静默吞掉。');
  console.log('    更糟的是：如果没装 unhandledRejection 兜底，进程在这里就退出了（退出码 1）。');
  console.log('    而且兜底接到的只是一个字符串，没有 stack，查不到是哪一行。\n');

  console.log('--- BAD 4：用 sleep 猜时间，而不是真的等任务完成 ---');
  console.log('  上面靠 `await sleep(200)` 猜「应该都跑完了」。');
  console.log('  任务一变慢就漏数据；任务一变快就白等。正确做法是 Promise.allSettled。\n');

  console.log('--- BAD 5：无界缓存 + 用普通对象当 Map ---');
  const cache = {};
  for (let i = 0; i < 3; i += 1) cache[`key-${i}`] = new Array(1000).fill(i);
  console.log(`  缓存条目数: ${Object.keys(cache).length}（并且只增不减）`);
  console.log(`  cache['constructor'] 的类型: ${typeof cache.constructor}`);
  console.log(`  ↑ 普通对象的键会撞上原型链；也拿不到 size。应该用 Map（课 9）。`);
  console.log(`  ↑ 更要命的是「只增不减」—— 这就是课 12 讲的泄漏 ④。\n`);

  console.log('--- BAD 6：定时器不清理 ---');
  const timers = [];
  for (let i = 0; i < 2; i += 1) {
    timers.push(setInterval(() => { void i; }, 1000));
  }
  console.log(`  已启动 ${timers.length} 个 setInterval，一个都没 clearInterval。`);
  console.log(`  → 不清理的话，事件循环永远有事可做，进程退不出去（课 12 泄漏 ②）。`);
  for (const t of timers) clearInterval(t);      // 赶紧清掉，别把演示脚本挂死
  console.log(`  → 清理完，进程就能正常退出了。\n`);

  console.log('--- BAD 7：把方法提取出来传进回调 —— this 丢了 ---');
  const counter = {
    n: 0,
    inc() { this.n += 1; },        // ❌ 普通方法：this 看调用点，不看出生地
  };
  const inc = counter.inc;
  try {
    inc();          // 严格模式下 this 是 undefined → 这里会 TypeError
  } catch (e) {
    console.log(`  裸调用 counter.inc → ${e.name}: ${e.message}`);
  }
  console.log(`  counter.n = ${counter.n}（本该是 1）`);
  console.log(`  → 回扣课 5 隐式丢失；修复：counter.inc.bind(counter) 或写成箭头函数属性\n`);

  console.log('===== 反例结束 =====');
}

main();
