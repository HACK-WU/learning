const { Client } = require('@elastic/elasticsearch');
const client = new Client({ node: 'http://localhost:9201' });

async function main() {
  console.log('===== 实测A：ES 的"事务"只到单文档（乐观并发控制）=====\n');

  // 1. 取一个真实存在的 _id 及其 _seq_no / _primary_term
  const hit = await client.search({
    index: 'l9_orders', size: 1, seq_no_primary_term: true,
  });
  const h = hit.hits.hits[0];
  console.log(`取到真实文档：_id=${h._id}  _seq_no=${h._seq_no}  _primary_term=${h._primary_term}`);
  console.log('当前内容：', JSON.stringify(h._source), '\n');

  // 2. 用正确的 seq_no 更新 → 应该成功
  try {
    const ok = await client.update({
      index: 'l9_orders', id: h._id,
      if_seq_no: h._seq_no, if_primary_term: h._primary_term,
      doc: { _l14_probe: 'ok' },
    });
    console.log(`✅ 用【正确】的 _seq_no=${h._seq_no} 更新 → 成功，result=${ok.result}，新 _seq_no=${ok._seq_no}`);
  } catch (e) {
    console.log('❌ 正确 seq_no 却失败：', e.message);
  }

  // 3. 故意用【过期的】seq_no 再更新 → 应该 409 冲突
  try {
    await client.update({
      index: 'l9_orders', id: h._id,
      if_seq_no: h._seq_no, if_primary_term: h._primary_term,
      doc: { _l14_probe: 'stale' },
    });
    console.log('❌ 过期 seq_no 竟然成功了（不符合预期）');
  } catch (e) {
    console.log(`✅ 用【过期】的 _seq_no=${h._seq_no} 再更新 → HTTP ${e.statusCode} 冲突`);
    console.log('   错误类型：', e.meta?.body?.error?.type);
    console.log('   这是 ES 唯一的事务保障：单文档乐观锁，没有回滚、没有多文档原子性');
  }

  // 4. 清理探针字段
  try {
    await client.update({ index: 'l9_orders', id: h._id, doc: { _l14_probe: null } });
  } catch (_) {}

  console.log('\n\n===== 实测B：ES 不支持关系型 join =====\n');

  // 1. 经典 SQL JOIN 语法
  try {
    await client.esql.query({
      format: 'txt',
      query: 'FROM l9_orders o JOIN l11_shop_v2 s ON o.shop_id = s.id LIMIT 3',
    });
    console.log('居然支持了？');
  } catch (e) {
    console.log('尝试 SQL 风格 JOIN：');
    console.log('  HTTP', e.statusCode, '|', e.meta?.body?.error?.type || e.message);
    const r = (e.meta?.body?.error?.reason || '').split('\n')[0];
    console.log('  原因：', r);
  }

  // 2. 对照：ES|QL 普通查询是能跑的
  try {
    const res = await client.esql.query({
      format: 'txt',
      query: 'FROM l9_orders | LIMIT 3 | KEEP amount',
    });
    console.log('\n对照：同样用 ES|QL，不带 JOIN 的普通查询能正常跑：');
    console.log(String(res).split('\n').slice(0, 6).join('\n'));
  } catch (e) {
    console.log('普通 ES|QL 也失败：', e.message);
  }

  console.log('\n结论：JOIN 语法不被 ES|QL 接受 —— ES 没有关系型 join。');
  console.log('替代方案只有四种：denormalize（反范式冗余）、nested、');
  console.log('parent-child join（同索引内，有性能代价）、应用层拼。');
  console.log('注：9.x 的 LOOKUP JOIN 要求被 join 的表标记为 lookup 索引，');
  console.log('    且是左连接语义，不能替代任意关系型 join。');
}

main().catch(e => console.log('未捕获错误：', e.message, JSON.stringify(e.meta?.body?.error?.root_cause || {}, null, 2)));
