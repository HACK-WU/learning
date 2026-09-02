import { getClient, itemError, isRetryable, printConnection } from '../es/client.js';
import { runIfEntry } from '../es/cli.js';
import { naming, bulkCfg, sleep } from '../config/index.js';
import { generateProducts, dirtyProducts } from './products.js';

/**
 * 同步：把"原始账本"（products.js）批量写进 ES。
 *
 * 三条硬要求（分别来自课 12 的实测结论）：
 * 1. **幂等**：用业务主键 sku 当 _id —— 重复同步 = 覆盖，失败重跑安全自愈
 * 2. **不能只看 errors**：errors=true 时成功项**已经落库了**，必须遍历 items 逐项处理
 * 3. **分类处置**：429/503 是可恢复的（退避重试）；
 *    mapper_parsing / strict_dynamic_mapping 是数据本身的病，重试一万次也没用，直接进死信
 */

/**
 * 执行一批 bulk，并按上面的策略重试。
 * @param operations 扁平数组：[{index:{...}}, doc, {index:{...}}, doc, ...]
 */
async function bulkWithRetry(client, operations, round = 0) {
  const res = await client.bulk({ operations, refresh: false });

  const failed = [];
  if (res.errors) {
    res.items.forEach((item, i) => {
      const e = itemError(item);
      if (e) {
        failed.push({ ...e, op: operations[i * 2], doc: operations[i * 2 + 1] });
      }
    });
  }

  const total = operations.length / 2;
  if (failed.length === 0) {
    return { ok: total, dead: [] };
  }

  const retryable = failed.filter((f) => isRetryable(f.status));
  const dead = failed.filter((f) => !isRetryable(f.status));

  if (retryable.length > 0 && round < bulkCfg.maxRetries) {
    const delay = bulkCfg.baseDelayMs * 2 ** round;
    const statuses = [...new Set(retryable.map((r) => r.status))].join('/');
    console.log(`   ⏳ ${retryable.length} 条可重试（HTTP ${statuses}），${delay}ms 后第 ${round + 1} 次重试`);
    await sleep(delay);
    const retryOps = retryable.flatMap((f) => [f.op, f.doc]);
    const retried = await bulkWithRetry(client, retryOps, round + 1);
    return { ok: total - failed.length + retried.ok, dead: [...dead, ...retried.dead] };
  }

  return { ok: total - failed.length, dead: [...dead, ...retryable] };
}

/** 把商品数组分批写进 ES，返回成功数与死信列表 */
async function writeAll(client, products, label) {
  let ok = 0;
  const dead = [];

  for (let i = 0; i < products.length; i += bulkCfg.batchSize) {
    const batch = products.slice(i, i + bulkCfg.batchSize);
    const operations = batch.flatMap((p) => [
      { index: { _index: naming.writeAlias, _id: p.sku } },
      p
    ]);
    const r = await bulkWithRetry(client, operations);
    ok += r.ok;
    dead.push(...r.dead);
    process.stdout.write(`   ${label} 批次 ${Math.floor(i / bulkCfg.batchSize) + 1}：成功 ${r.ok}/${batch.length}\r`);
  }
  process.stdout.write('\n');

  return { ok, dead };
}

/** 同步主流程：跑两遍，第二遍用来验证幂等 */
export async function runSync({ withDirty = false, refresh = true } = {}) {
  const client = getClient();
  const products = generateProducts();
  if (withDirty) products.push(...dirtyProducts());

  console.log(`\n📦 第一遍同步：${products.length} 条（_id = 业务主键 sku）`);
  const first = await writeAll(client, products, '写入');

  if (refresh) {
    await client.indices.refresh({ index: naming.alias });
  }

  const countAfterFirst = await client.count({ index: naming.alias });
  console.log(`   ✅ 第一遍结束：成功 ${first.ok} 条，索引内共 ${countAfterFirst.count} 条`);

  if (first.dead.length > 0) {
    console.log(`\n☠️  死信 ${first.dead.length} 条（不可重试，需人工修数据后重跑）：`);
    for (const d of first.dead) {
      console.log(`   - ${d.id} ｜ HTTP ${d.status} ｜ ${d.type}`);
      console.log(`     ${(d.reason ?? '').slice(0, 160)}`);
    }
  }

  // ---- 第二遍：原样再跑一次，验证幂等 ----
  console.log(`\n🔁 第二遍同步：同样的 ${products.length} 条再写一遍（验证 _id 幂等）`);
  // 幂等验证只针对干净数据：脏数据第二遍仍然会失败，混进来会干扰结论
  const clean = generateProducts();
  const second = await writeAll(client, clean, '重写');
  if (refresh) {
    await client.indices.refresh({ index: naming.alias });
  }
  const countAfterSecond = await client.count({ index: naming.alias });

  const idempotent = countAfterFirst.count === countAfterSecond.count;
  console.log(
    idempotent
      ? `   ✅ 幂等成立：重写后文档数仍为 ${countAfterSecond.count}（全都是 updated，没有新增）`
      : `   ❌ 幂等被破坏：${countAfterFirst.count} → ${countAfterSecond.count}，检查 _id 是否用了业务主键`
  );

  return { first, second, countAfterFirst: countAfterFirst.count, countAfterSecond: countAfterSecond.count, idempotent };
}

// ---------- CLI ----------
async function main() {
  const withDirty = process.argv.includes('--with-dirty');
  const client = getClient();
  await printConnection();
  const r = await runSync({ withDirty });
  console.log(`\n🎉 同步完成。成功 ${r.first.ok + r.second.ok} 次写入，死信 ${r.first.dead.length + r.second.dead.length} 条`);
  if (!withDirty) {
    console.log('💡 想看「bulk 部分失败」怎么处理：npm run sync:dirty');
  }
}

runIfEntry(import.meta.url, main);
