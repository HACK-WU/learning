const { Client } = require('@elastic/elasticsearch');
const client9201 = new Client({ node: 'http://localhost:9201' });
const client9200 = new Client({
  node: 'https://localhost:9200',
  auth: { username: 'elastic', password: '9PvhcGNNc86uFZb_ePAN' },
  tls: { rejectUnauthorized: false },
});

async function probe(name, fn) {
  try {
    const r = await fn();
    console.log(`  ✅ ${name.padEnd(42)} → ${r}`);
  } catch (e) {
    const err = e.meta?.body?.error;
    const type = err?.type || e.message;
    console.log(`  ❌ ${name.padEnd(42)} → ${type}`);
  }
}

async function main() {
  console.log('===== 9.3 新考纲考点 × 本机环境（9201 basic license）=====\n');

  console.log('【新增考点 *】');
  await probe('Architecture：节点角色', async () => {
    const r = await client9201.cat.nodes({ h: 'name,node.role', format: 'json' });
    return JSON.stringify(r.body ?? r);
  });

  await probe('Architecture：分片分配策略（allocation）', async () => {
    const r = await client9201.cluster.getSettings({ include_defaults: true, flat_settings: true });
    const s = r.defaults || r.persistent || {};
    const keys = Object.keys(s).filter(k => k.includes('allocation'));
    return keys.length ? keys.slice(0, 3).join(', ') : '(有设置项)';
  });

  await probe('ES|QL 查询', async () => {
    const r = await client9201.esql.query({ format: 'json', query: 'FROM l9_orders | LIMIT 2 | KEEP amount' });
    return `返回 ${r.values?.length ?? 0} 行`;
  });

  await probe('semantic search（kNN 向量检索）', async () => {
    const r = await client9201.search({
      index: 'l13_vector_demo', size: 2,
      knn: { field: 'my_vector', query_vector: [1.0, 0.0, 0.0], k: 2, num_candidates: 10 },
    });
    return `命中 ${r.hits.total.value ?? r.hits.hits.length} 条`;
  });

  await probe('semantic_text 字段（自动推理）', async () => {
    await client9201.indices.create({
      index: 'l14_sem_probe',
      mappings: { properties: { content: { type: 'semantic_text' } } },
    });
    try {
      await client9201.index({ index: 'l14_sem_probe', id: '1', document: { content: '测试内容' } });
      return '建索引+写入都成功';
    } catch (e) {
      const reason = (e.meta?.body?.error?.reason || e.message || '');
      await client9201.indices.delete({ index: 'l14_sem_probe' }).catch(() => {});
      throw Object.assign(new Error('x'), { meta: { body: { error: { type: reason.slice(0, 60) + '…' } } } });
    }
  });

  await probe('Streams（9.x 新数据接入方式）', async () => {
    try {
      await client9201.transport.request({ method: 'GET', path: '/_streams' });
      return '可用';
    } catch (e) {
      const t = e.meta?.body?.error?.type || `HTTP ${e.statusCode}`;
      throw Object.assign(new Error('x'), { meta: { body: { error: { type: t } } } });
    }
  });

  console.log('\n【保留考点 · 本机可用性】');
  await probe('Index aliases（别名，9.3 移到 Data Mgmt）', async () => {
    const r = await client9201.cat.aliases({ format: 'json' });
    return `现有 ${(r.body ?? []).length} 个别名，API 可用`;
  });

  await probe('Ingest pipeline', async () => {
    const r = await client9201.ingest.getPipeline({});
    return 'API 可用';
  });

  await probe('ILM policy', async () => {
    const r = await client9201.transport.request({ method: 'GET', path: '/_ilm/policy' });
    return `现有 ${Object.keys(r).length} 个策略`;
  });

  await probe('Index template（含 data stream）', async () => {
    const r = await client9201.indices.getIndexTemplate({ name: 'l13_logs_template' });
    return `l13_logs_template 存在，data_stream=${!!r.index_templates?.[0]?.index_template?.data_stream}`;
  });

  await probe('Async search', async () => {
    const r = await client9201.asyncSearch.submit({
      index: 'l9_orders', wait_for_completion_timeout: '1s',
      query: { match_all: {} },
    });
    return `可用，is_running=${r.is_running}`;
  });

  await probe('Snapshot / SLM（备份）', async () => {
    const r = await client9201.snapshot.getRepository({ repository: 'l11_repo' });
    return `l11_repo 存在：${Object.keys(r)[0]}`;
  });

  console.log('\n【9.3 已移除考点 · 本机实际表现】');
  await probe('runtime fields（9.3 已移除，本机仍可跑）', async () => {
    const r = await client9201.search({
      index: 'l9_orders', size: 1,
      runtime_mappings: { amount_doubled: { type: 'long', script: { source: "emit(doc['amount'].value * 2)" } } },
      fields: ['amount_doubled'],
    });
    const v = r.hits.hits[0]?.fields?.amount_doubled?.[0];
    return `能跑（amount_doubled=${v}）—— API 还在，只是不考了`;
  });

  await probe('cross-cluster search（9.3 已移除）', async () => {
    const r = await client9201.cluster.remoteInfo({});
    return `远程集群 ${Object.keys(r).length} 个，API 可访问`;
  });

  await probe('searchable snapshot（9.3 已移除）', async () => {
    const r = await client9201.transport.request({ method: 'GET', path: '/_license' });
    return `license=${r.license?.type}（searchable snapshot 需 enterprise）`;
  });

  console.log('\n===== 9200 单节点（有安全，验证 Security 考点）=====');
  await probe('RBAC：创建角色', async () => {
    const r = await client9200.security.getRole({ name: 'l13_readonly' });
    return `l13_readonly 存在，权限索引 ${Object.keys(r.l13_readonly?.indices || {}).length} 个`;
  });

  await probe('RBAC：只读用户可用', async () => {
    const c = new Client({ node: 'https://localhost:9200', auth: { username: 'l13_reader', password: 'l13Readonly2026' }, tls: { rejectUnauthorized: false } });
    const r = await c.search({ index: 'l8_orders', size: 0 });
    return `l13_reader 读 l8_orders 命中 ${r.hits.total.value} 条`;
  });

  await probe('IK 分词（中文，本机特色）', async () => {
    const r = await client9200.indices.analyze({ index: 'news_ik', analyzer: 'ik_max_word', text: '苹果手机' });
    return r.tokens.map(t => t.token).join(' / ');
  });
}

main().catch(e => console.log('未捕获：', e.message));
