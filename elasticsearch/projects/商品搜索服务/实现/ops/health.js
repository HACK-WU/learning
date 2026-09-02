import { getClient, rootCause, printConnection } from '../es/client.js';
import { runIfEntry } from '../es/cli.js';
import { naming } from '../config/index.js';

/**
 * 巡检：把集群 / 索引 / 分片 / 段 / ILM 的健康状况一次性看清楚。
 *
 * 对应课 10 的生产检查清单，以及那句最容易被忘的教训：
 *   **只看颜色会漏** —— 每次故障转移后必须核对 docs.count（课 10 实测：
 *   反复故障转移会让分片"静默消失"，集群照样显示 green）。
 */

const kb = (v) => (v == null ? '-' : `${(Number(v) / 1024).toFixed(1)} kb`);

export async function runHealth(client) {
  const report = {};

  // ---------- 1. 集群健康 ----------
  const health = await client.cluster.health({});
  report.health = health;
  console.log('\n🏥 集群健康');
  console.log(`   状态 ${health.status.toUpperCase()} ｜ 节点 ${health.number_of_nodes} ｜ 数据节点 ${health.number_of_data_nodes}`);
  console.log(`   主分片 ${health.active_primary_shards} ｜ 总分片 ${health.active_shards} ｜ 未分配 ${health.unassigned_shards}（其中主分片 ${health.unassigned_primary_shards}）`);

  if (health.unassigned_primary_shards > 0) {
    console.log('   🔴 有主分片未分配 —— 这是真的读不到数据，立刻用 _cluster/allocation/explain 查原因');
  } else if (health.unassigned_shards > 0) {
    console.log('   🟡 只有副本未分配 —— 数据一条不少，只是副本没地方放（单节点集群有副本时这是物理必然）');
  } else {
    console.log('   ✅ 全部分片已分配');
  }

  // ---------- 2. 索引清单 ----------
  // bytes: 'b' 很关键：不加的话 store.size 返回的是 "7.9kb" 这类人类可读字符串，
  // 直接 Number() 会得到 NaN
  const indices = await client.cat.indices({
    index: 'cap_*',
    format: 'json',
    bytes: 'b',
    h: ['index', 'status', 'pri', 'rep', 'docs.count', 'store.size']
  });
  report.indices = indices;
  console.log('\n📇 项目索引');
  for (const i of indices) {
    console.log(
      `   ${i.index.padEnd(34)} ${String(i.status).padEnd(6)} 主${i.pri} 副${i.rep} 文档 ${String(i['docs.count']).padStart(4)} 占用 ${kb(i['store.size'])}`
    );
  }
  if (indices.length === 0) console.log('   （没有 cap_* 索引，先跑 npm run init && npm run sync）');

  // ---------- 3. 分片分布：验证"主副本不同节点"铁律 ----------
  const shards = await client.cat.shards({
    index: 'cap_*',
    format: 'json',
    h: ['index', 'shard', 'prirep', 'state', 'node', 'docs']
  });
  report.shards = shards;
  console.log('\n🧩 分片分布');
  const byIndex = {};
  for (const s of shards) {
    byIndex[s.index] ??= {};
    byIndex[s.index][s.shard] ??= {};
    byIndex[s.index][s.shard][s.prirep] = s.node;
  }
  let coLocated = 0;
  for (const [idx, shardsMap] of Object.entries(byIndex)) {
    const nodes = [];
    for (const [shardNo, roles] of Object.entries(shardsMap)) {
      nodes.push(`   片${shardNo}: 主@${roles.p ?? '-'} 副@${roles.r ?? '无副本'}`);
      if (roles.p && roles.r && roles.p === roles.r) coLocated += 1;
    }
    console.log(`   ${idx}`);
    for (const n of nodes) console.log(`  ${n}`);
  }
  console.log(
    coLocated === 0
      ? '   ✅ 没有主副本同节点的情况（铁律：副本绝不与自己的主分片待在同一节点）'
      : `   ❌ 有 ${coLocated} 个分片的主副本在同一节点 —— 节点一挂主副本同归于尽`
  );

  // ---------- 4. 段数量：段太碎会拖慢查询 ----------
  console.log('\n🧱 段（Segment）数量');
  for (const name of [naming.v1, naming.v2]) {
    try {
      const seg = await client.cat.segments({ index: name, format: 'json' });
      const searchable = seg.filter((s) => s.segment && s.searchable === 'true');
      console.log(`   ${name}：可搜索段 ${searchable.length} 个${searchable.length > 5 ? '（偏多，可用 forcemerge 合并，但只对不再写入的索引做）' : ''}`);
    } catch {
      /* 索引不存在，跳过 */
    }
  }

  // ---------- 5. ILM 与数据流 ----------
  console.log('\n♻️  ILM 与数据流');
  try {
    const ds = await client.indices.getDataStream({ name: naming.logsStream });
    const streams = ds.data_streams ?? [];
    if (streams.length === 0) {
      console.log('   （还没有数据流，跑一次 npm run search 就会自动创建）');
    }
    for (const s of streams) {
      // 两个坑：
      // ① 后备索引字段是 indices，不是 backing_indices（写错会静默走进 catch 分支）
      // ② 客户端会把 managed_by 转成驼峰 managedBy，两种写法都要兜住
      // 两个坑：
      // ① 后备索引字段是 indices，不是 backing_indices（写错会静默走进 catch 分支）
      // ② 判断 ILM 是否挂上，看 ilm_policy 而不是 managed_by ——
      //    客户端返回的这个对象里根本没有 managed_by 字段（实测），只有 ilm_policy
      const backing = s.indices ?? [];
      const ilmPolicy = s.ilm_policy ?? s.ilmPolicy;
      console.log(`   数据流 ${s.name}：后备索引 ${backing.length} 个 ｜ 状态 ${s.status} ｜ ILM 策略 ${ilmPolicy ?? '未挂载'}`);
      for (const b of backing) console.log(`     - ${b.index_name ?? b.indexName}`);
      if (!ilmPolicy) {
        console.log('     ⚠️  ILM 策略没挂上 —— 检查模板 settings 里有没有 index.lifecycle.name');
      }
    }
  } catch (e) {
    console.log(`   （读数据流失败：${rootCause(e)}）`);
  }

  try {
    const policy = await client.ilm.getLifecycle({ name: naming.logsPolicy });
    const raw = Object.keys(policy[naming.logsPolicy]?.policy?.phases ?? {});
    // JSON 里阶段顺序不保证，按生命周期的自然顺序排一遍再展示
    const order = ['hot', 'warm', 'cold', 'frozen', 'delete'];
    const phases = raw.sort((a, b) => order.indexOf(a) - order.indexOf(b));
    console.log(`   ILM 策略 ${naming.logsPolicy}：阶段 ${phases.join(' → ')}`);
    console.log('   ⚠️  ILM 默认每 10 分钟轮询一次（indices.lifecycle.poll_interval 是集群级设置），配完不会立刻生效');
  } catch {
    console.log(`   （ILM 策略 ${naming.logsPolicy} 还未创建，跑 npm run init）`);
  }

  // ---------- 6. 别名指向 ----------
  console.log('\n🏷  别名指向');
  try {
    const alias = await client.indices.getAlias({ name: naming.alias });
    for (const [idx, meta] of Object.entries(alias)) {
      const isWrite = meta.aliases?.[naming.alias]?.is_write_index ? '（is_write_index）' : '';
      console.log(`   ${naming.alias} → ${idx} ${isWrite}`);
    }
  } catch {
    console.log(`   （别名 ${naming.alias} 还不存在，跑 npm run init）`);
  }

  console.log('\n✅ 巡检结束');
  return report;
}

async function main() {
  const client = getClient();
  await printConnection();
  await runHealth(client);
}

runIfEntry(import.meta.url, main);
