const { Client } = require('@elastic/elasticsearch');
const client = new Client({ node: 'http://localhost:9201' });
const IDX = 'l14_nrt_probe';

async function main() {
  console.log('===== 实测C：ES 的写入不是实时可见的（近实时 NRT）=====\n');

  // 建一个干净的索引
  try { await client.indices.delete({ index: IDX }); } catch (_) {}
  await client.indices.create({ index: IDX, settings: { number_of_shards: 1, number_of_replicas: 0 } });

  const id = 'probe-1';

  // 1. 默认写入（refresh=默认 1s）后立刻查 → 大概率查不到
  await client.index({ index: IDX, id, document: { msg: 'hello', amount: 1 } });
  const immediate = await client.search({ index: IDX, query: { match_all: {} } });
  console.log(`① 默认写入后【立刻】搜索        → 命中 ${immediate.hits.total.value} 条`);
  console.log('   这就是"刚写完却搜不到" —— 默认 refresh_interval=1s\n');

  // 2. 等 1.2 秒再查 → 能查到
  await new Promise(r => setTimeout(r, 1200));
  const afterWait = await client.search({ index: IDX, query: { match_all: {} } });
  console.log(`② 等待 1.2 秒后搜索             → 命中 ${afterWait.hits.total.value} 条 ✅`);
  console.log('   近实时（NRT）的"近"字就是这个意思\n');

  // 3. 用 ?refresh=true 强制刷新 → 立刻可见
  await client.index({ index: IDX, id: 'probe-2', refresh: true, document: { msg: 'forced', amount: 2 } });
  const forced = await client.search({ index: IDX, query: { match_all: {} } });
  console.log(`③ 用 refresh=true 写入后立刻搜  → 命中 ${forced.hits.total.value} 条 ✅`);
  console.log('   代价：每次强制刷新都产生新段，写多读少场景千万别开\n');

  // 4. GET 单文档是实时的（这是关键区别）
  const got = await client.get({ index: IDX, id });
  console.log(`④ 对照：GET 单个文档（按 _id）  → 实时可读，_id=${got._id} ✅`);
  console.log('   GET 走 translog，实时；SEARCH 走 segment，近实时');
  console.log('   这是面试和实操都爱考的一个分界点\n');

  // 5. 演示 refresh_interval=-1（关掉自动刷新，纯写入最快）
  await client.indices.putSettings({ index: IDX, settings: { 'index.refresh_interval': '-1' } });
  await client.index({ index: IDX, id: 'probe-3', document: { msg: 'no-refresh', amount: 3 } });
  await new Promise(r => setTimeout(r, 1500));
  const noRefresh = await client.search({ index: IDX, query: { match_all: {} } });
  console.log(`⑤ refresh_interval=-1 后写 1 条，等 1.5s 搜 → 命中 ${noRefresh.hits.total.value} 条`);
  console.log('   关掉刷新后即使等也搜不到，必须手动 POST /_refresh');
  console.log('   适用场景：批量导入（写多读少），导完再一次性刷新\n');

  console.log('===== 选型含义 =====');
  console.log('如果你要的是"写入后立刻能查到"的强一致读 —— ES 默认给不了。');
  console.log('这不是 bug，是 ES 用"近实时"换取写入吞吐的设计取舍。');
  console.log('所以：ES 适合做搜索/分析，不适合做交易系统的主存储。');

  await client.indices.delete({ index: IDX });
  console.log('\n（已清理探针索引 ' + IDX + '）');
}

main().catch(e => console.log('出错：', e.message, JSON.stringify(e.meta?.body?.error?.root_cause || {}, null, 2)));
