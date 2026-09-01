// 课 15 评审 · A 视角：数据事实核查
// 逐字执行讲义中的命令，核对每个数字与结论
const { Client } = require('@elastic/elasticsearch')
const fs = require('fs')
const path = require('path')

const client = new Client({ node: 'http://localhost:9201' })
const log = (...a) => console.log(...a)
const LESSON = 'D:/projects/learning/elasticsearch/stages/4-分布式与工程实践/lessons/lesson-15-索引管理与生命周期策略.md'
const issues = []
const P0 = (s) => { issues.push(['P0', s]); log('  ❌ P0:', s) }
const P1 = (s) => { issues.push(['P1', s]); log('  ⚠️ P1:', s) }
const P2 = (s) => { issues.push(['P2', s]); log('  ⚪ P2:', s) }
const ok = (s) => log('  ✅', s)

async function main() {
  const md = fs.readFileSync(LESSON, 'utf8')
  log('讲义字数 =', md.length)

  // ---- 1. 环境前提核对 ----
  log('\n[1] 环境前提：9201 三节点、green、无安全')
  const h = await client.cluster.health()
  if (h.number_of_nodes === 3) ok('节点数 = 3') ; else P1(`讲义说 3 节点，实测 ${h.number_of_nodes}`)
  if (h.status === 'green') ok('status = green') ; else P1(`讲义说 green，实测 ${h.status}`)
  if (h.cluster_name === 'l9-cluster') ok('cluster.name = l9-cluster') ; else P1(`cluster_name 实测 ${h.cluster_name}`)

  // ---- 2. 组件模板 + 索引模板核心结论 ----
  log('\n[2] 模板：priority 覆盖 + 改模板不影响已有索引')
  await client.cluster.putComponentTemplate({
    name: 'rv_ct', template: { settings: { number_of_shards: 2, number_of_replicas: 0, 'index.refresh_interval': '5s' } },
  })
  await client.indices.putIndexTemplate({
    name: 'rv_tpl_lo', index_patterns: ['rv-a-*'], priority: 100, composed_of: ['rv_ct'],
  })
  await client.indices.create({ index: 'rv-a-1' })
  let g = await client.indices.get({ index: 'rv-a-1' })
  const v1 = g['rv-a-1'].settings.index.refresh_interval
  if (v1 === '5s') ok(`低优先级模板生效，refresh_interval=${v1}`) ; else P0(`讲义说 5s，实测 ${v1}`)

  await client.cluster.putComponentTemplate({
    name: 'rv_ct', template: { settings: { number_of_shards: 2, number_of_replicas: 0, 'index.refresh_interval': '77s' } },
  })
  g = await client.indices.get({ index: 'rv-a-1' })
  const v1after = g['rv-a-1'].settings.index.refresh_interval
  if (v1after === '5s') ok(`改组件模板后已有索引仍为 ${v1after}（讲义核心结论成立）`) ; else P0(`讲义说旧索引不变，实测变成 ${v1after}`)
  await client.indices.create({ index: 'rv-a-2' })
  g = await client.indices.get({ index: 'rv-a-2' })
  const v2 = g['rv-a-2'].settings.index.refresh_interval
  if (v2 === '77s') ok(`新建索引取新值 ${v2}（讲义核心结论成立）`) ; else P0(`讲义说新索引 77s，实测 ${v2}`)

  // priority 覆盖：只覆盖冲突项，其余合并
  await client.indices.putIndexTemplate({
    name: 'rv_tpl_hi', index_patterns: ['rv-a-*'], priority: 200, composed_of: ['rv_ct'],
    template: { settings: { 'index.refresh_interval': '30s' } },
  })
  await client.indices.create({ index: 'rv-a-3' })
  g = await client.indices.get({ index: 'rv-a-3' })
  const b = g['rv-a-3']
  if (b.settings.index.refresh_interval === '30s') ok('priority=200 覆盖 refresh_interval = 30s') ; else P0(`讲义说 30s，实测 ${b.settings.index.refresh_interval}`)
  if (b.settings.index.number_of_shards === '2') ok('组件模板的 number_of_shards=2 被保留（合并而非替换）') ; else P0(`讲义说保留 2，实测 ${b.settings.index.number_of_shards}`)

  // ---- 3. 模板只对新建索引生效 ----
  log('\n[3] 模板只对新建索引生效（不匹配模板的索引取默认值）')
  await client.indices.create({ index: 'rv-nomatch' })
  g = await client.indices.get({ index: 'rv-nomatch' })
  const ns = g['rv-nomatch'].settings.index.number_of_shards
  if (ns === '1') ok(`不匹配模板 → 默认 1 分片（实测 ${ns}）`) ; else P1(`预期默认 1，实测 ${ns}`)

  // ---- 4. 别名：无写索引时写入报错 ----
  log('\n[4] 别名：多索引无 is_write_index 时写入必须报错')
  await client.indices.create({ index: 'rv-m-a', settings: { number_of_shards: 1, number_of_replicas: 0 } })
  await client.indices.create({ index: 'rv-m-b', settings: { number_of_shards: 1, number_of_replicas: 0 } })
  await client.indices.updateAliases({
    actions: [{ add: { index: 'rv-m-a', alias: 'rv-m' } }, { add: { index: 'rv-m-b', alias: 'rv-m' } }],
  })
  let errType = null, errReason = null
  try { await client.index({ index: 'rv-m', document: { a: 1 } }) }
  catch (e) { errType = e.meta?.body?.error?.type; errReason = e.meta?.body?.error?.reason }
  if (errType === 'illegal_argument_exception') ok(`写入报错类型 = ${errType}`) ; else P0(`讲义说 illegal_argument_exception，实测 ${errType}`)
  if (errReason && errReason.includes('no write index is defined')) ok('报错原文含 "no write index is defined"（讲义引用准确）')
  else P0(`报错原文不符：${errReason}`)

  // 指定后只写那一个
  await client.indices.updateAliases({ actions: [{ add: { index: 'rv-m-b', alias: 'rv-m', is_write_index: true } }] })
  await client.index({ index: 'rv-m', document: { a: 1 }, refresh: true })
  const ca = await client.count({ index: 'rv-m-a' })
  const cb = await client.count({ index: 'rv-m-b' })
  if (ca.count === 0 && cb.count === 1) ok('只写到 is_write_index 那个（a=0, b=1）') ; else P0(`讲义说 a=0 b=1，实测 a=${ca.count} b=${cb.count}`)
  const sa = await client.search({ index: 'rv-m', query: { match_all: {} } })
  if (sa.hits.total.value === 1) ok('搜别名仍跨全部索引（命中 1 条）') ; else P1(`搜别名实测 ${sa.hits.total.value} 条`)

  // ---- 5. 别名 delete 必须被拒绝 ----
  log('\n[5] 别名：DELETE /<别名> 必须被拒绝（讲义关键安全结论）')
  let dErr = null
  try { await client.indices.delete({ index: 'rv-m' }) }
  catch (e) { dErr = e.meta?.body?.error }
  if (dErr && dErr.type === 'illegal_argument_exception') ok(`DELETE 别名被拒绝：${dErr.type}`)
  else P0(`讲义说 DELETE 别名会被拒绝，实测 ${dErr ? dErr.type : '成功了'}`)
  if (dErr && /matches an alias/.test(dErr.reason || '')) ok('报错原文含 "matches an alias"（讲义引用准确）')
  else P0(`报错原文不符：${dErr?.reason}`)

  // ---- 6. 别名改 settings 会穿透/广播（推翻常识的结论，必须复验）----
  log('\n[6] 别名：对多索引别名改 settings 会广播到所有索引')
  await client.indices.putSettings({ index: 'rv-m', settings: { 'index.refresh_interval': '17s' } })
  const ga = await client.indices.get({ index: 'rv-m-a' })
  const gb = await client.indices.get({ index: 'rv-m-b' })
  const va = ga['rv-m-a'].settings.index.refresh_interval
  const vb = gb['rv-m-b'].settings.index.refresh_interval
  if (va === '17s' && vb === '17s') ok(`两个索引都变成 17s（讲义"广播"结论成立）`)
  else P0(`讲义说都变 17s，实测 a=${va} b=${vb}`)

  // ---- 7. 过滤别名 ----
  log('\n[7] 过滤别名：别名的过滤先于查询条件生效')
  await client.indices.create({
    index: 'rv-f', settings: { number_of_shards: 1, number_of_replicas: 0 },
    mappings: { properties: { name: { type: 'keyword' }, price: { type: 'scaled_float', scaling_factor: 100 } } },
  })
  await client.bulk({ refresh: true, operations: [
    { index: { _index: 'rv-f', _id: '1' } }, { name: '苹果', price: 5.5 },
    { index: { _index: 'rv-f', _id: '2' } }, { name: '香蕉', price: 3.25 },
    { index: { _index: 'rv-f', _id: '3' } }, { name: '车厘子', price: 88.8 },
  ]})
  await client.indices.updateAliases({
    actions: [{ add: { index: 'rv-f', alias: 'rv-f-cheap', filter: { range: { price: { lt: 10 } } } } }],
  })
  const all = await client.search({ index: 'rv-f', query: { match_all: {} } })
  const cheap = await client.search({ index: 'rv-f-cheap', query: { match_all: {} } })
  if (all.hits.total.value === 3) ok('无过滤命中 3 条') ; else P0(`讲义说 3 条，实测 ${all.hits.total.value}`)
  if (cheap.hits.total.value === 2) ok('过滤别名（price<10）命中 2 条') ; else P0(`讲义说 2 条，实测 ${cheap.hits.total.value}`)
  const names = cheap.hits.hits.map(x => x._source.name + '(' + x._source.price + ')').sort().join(' ')
  ok('过滤结果：' + names)
  const contra = await client.search({ index: 'rv-f-cheap', query: { bool: { filter: [{ range: { price: { gte: 10 } } }] } } })
  if (contra.hits.total.value === 0) ok('再叠加 price>=10 → 0 条（过滤先于查询）') ; else P0(`讲义说 0 条，实测 ${contra.hits.total.value}`)

  // ---- 8. scaled_float 保留两位小数（讲义第 1 步的核心选型建议）----
  log('\n[8] scaled_float(scaling_factor=100) 是否真的保留两位小数')
  const dec = await client.search({ index: 'rv-f', query: { term: { name: '苹果' } } })
  const p = dec.hits.hits[0]._source.price
  if (p === 5.5) ok(`price = 5.5（未被截断，讲义选型建议成立）`) ; else P0(`讲义说 5.5，实测 ${p}`)

  // ---- 9. shrink 三条件 ----
  log('\n[9] shrink：因数约束（4→3 必须报错）')
  await client.indices.create({ index: 'rv-s', settings: { number_of_shards: 4, number_of_replicas: 0 } })
  await client.index({ index: 'rv-s', id: '1', document: { a: 1 }, refresh: true })
  await client.indices.putSettings({ index: 'rv-s', settings: { 'index.routing.allocation.require._name': 'node-1' } })
  for (let i = 0; i < 30; i++) {
    const sh = await client.cat.shards({ index: 'rv-s', h: ['node'], format: 'json' })
    if (new Set(sh.map(s => s.node)).size === 1) break
    await new Promise(r => setTimeout(r, 2000))
  }
  await client.indices.putSettings({ index: 'rv-s', settings: { 'index.blocks.write': true } })
  let sErr = null
  try {
    await client.indices.shrink({ index: 'rv-s', target: 'rv-s3', settings: { 'index.number_of_shards': 3, 'index.number_of_replicas': 0 } })
  } catch (e) { sErr = e.meta?.body?.error }
  if (sErr && /must be a multiple of/.test(sErr.reason || '')) ok(`4→3 报错：${sErr.reason}`)
  else P0(`讲义说 4→3 报 must be a multiple of，实测 ${sErr ? sErr.reason : '成功了'}`)

  const sg = await client.indices.shrink({
    index: 'rv-s', target: 'rv-s1',
    settings: { 'index.number_of_shards': 1, 'index.number_of_replicas': 0, 'index.blocks.write': null, 'index.routing.allocation.require._name': null },
  })
  await new Promise(r => setTimeout(r, 3000))
  const cnt = await client.count({ index: 'rv-s1' })
  if (cnt.count === 1) ok('4→1 成功且数据保留 1 条') ; else P0(`讲义说数据完整，实测 ${cnt.count} 条`)

  // ---- 10. forcemerge 段数下降 ----
  log('\n[10] forcemerge：段数真的下降')
  await client.indices.create({ index: 'rv-fm', settings: { number_of_shards: 1, number_of_replicas: 0 } })
  for (let i = 0; i < 8; i++) {
    await client.index({ index: 'rv-fm', id: String(i), document: { t: 'd' + i } })
    await client.indices.refresh({ index: 'rv-fm' })
  }
  const countSeg = (r, n) => {
    const idx = r.indices[n]; if (!idx) return 0
    let c = 0
    for (const [, arr] of Object.entries(idx.shards)) {
      for (const sh of (Array.isArray(arr) ? arr : [arr])) if (sh.segments) c += Object.keys(sh.segments).length
    }
    return c
  }
  const n0 = countSeg(await client.indices.segments({ index: 'rv-fm' }), 'rv-fm')
  await client.indices.forcemerge({ index: 'rv-fm', max_num_segments: 1 })
  await new Promise(r => setTimeout(r, 2000))
  const n1 = countSeg(await client.indices.segments({ index: 'rv-fm' }), 'rv-fm')
  if (n0 === 8 && n1 === 1) ok(`段数 ${n0} → ${n1}（讲义数据准确）`)
  else P0(`讲义说 8→1，实测 ${n0}→${n1}`)

  // ---- 11. close/open ----
  log('\n[11] close 后不可读写，open 后数据还在')
  await client.indices.close({ index: 'rv-fm' })
  let cErr = null
  try { await client.search({ index: 'rv-fm', query: { match_all: {} } }) } catch (e) { cErr = e.meta?.body?.error?.type }
  if (cErr === 'index_closed_exception') ok(`close 后搜索报 ${cErr}`) ; else P0(`讲义说 index_closed_exception，实测 ${cErr}`)
  await client.indices.open({ index: 'rv-fm' })
  const reopen = await client.count({ index: 'rv-fm' })
  if (reopen.count === 8) ok('open 后数据 8 条还在') ; else P0(`讲义说数据还在，实测 ${reopen.count} 条`)

  // ---- 12. ILM 轮询间隔默认值 ----
  log('\n[12] ILM poll_interval 默认值与层级')
  const st = await client.cluster.getSettings({ include_defaults: true })
  const def = st.defaults?.indices?.lifecycle?.poll_interval
  if (def === '10m') ok(`默认 poll_interval = ${def}`) ; else P0(`讲义说默认 10m，实测 ${def}`)
  let idxErr = null
  try {
    await client.indices.create({ index: 'rv-ilm-bad', settings: { 'index.lifecycle.poll_interval': '5s' } })
  } catch (e) { idxErr = e.meta?.body?.error?.reason }
  if (idxErr && /unknown setting/.test(idxErr)) ok('索引级设 poll_interval 报 unknown setting（讲义结论成立）')
  else P0(`讲义说索引级设置会报 unknown setting，实测 ${idxErr || '成功了'}`)

  // ---- 13. rollover 只能作用于别名/数据流 ----
  log('\n[13] rollover 作用于具体索引必须报错')
  await client.indices.create({ index: 'rv-ro', settings: { number_of_shards: 1, number_of_replicas: 0 } })
  let rErr = null
  try { await client.indices.rollover({ alias: 'rv-ro' }) } catch (e) { rErr = e.meta?.body?.error?.reason }
  if (rErr && /one of \[alias,data_stream\] was expected/.test(rErr)) ok('rollover 具体索引报错（讲义引用准确）')
  else P0(`讲义说 rollover 具体索引会报错，实测 ${rErr || '成功了'}`)

  // ---- 14. 破坏性删除需精确名字 ----
  log('\n[14] 通配符删除被拒（destructive_requires_name）')
  let wErr = null
  try { await client.indices.delete({ index: 'rv-*' }) } catch (e) { wErr = e.meta?.body?.error?.type }
  if (wErr) ok(`通配符删除被拒：${wErr}`) ; else P0('讲义说通配符删除被拒，实测成功了')

  // ---- 清理 ----
  log('\n[清理] 删除本轮评审临时对象')
  for (const n of ['rv-m', 'rv-f-cheap', 'rv-multi']) {
    try {
      const al = await client.indices.getAlias({ name: n })
      await client.indices.updateAliases({ actions: Object.keys(al).map(i => ({ remove: { index: i, alias: n } })) })
    } catch (e) {}
  }
  for (const i of ['rv-a-1','rv-a-2','rv-a-3','rv-nomatch','rv-m-a','rv-m-b','rv-f','rv-s','rv-s1','rv-s3','rv-fm','rv-ro','rv-ilm-bad']) {
    try { await client.indices.delete({ index: i }) } catch (e) {}
  }
  for (const n of ['rv_tpl_lo','rv_tpl_hi']) { try { await client.indices.deleteIndexTemplate({ name: n }) } catch (e) {} }
  try { await client.cluster.deleteComponentTemplate({ name: 'rv_ct' }) } catch (e) {}

  log('\n================ A 视角结论 ================')
  const c0 = issues.filter(i => i[0] === 'P0').length
  const c1 = issues.filter(i => i[0] === 'P1').length
  const c2 = issues.filter(i => i[0] === 'P2').length
  log(`P0=${c0}  P1=${c1}  P2=${c2}`)
  for (const [lv, s] of issues) log(` ${lv}: ${s}`)
}

main().catch(e => { console.error('FAILED:', e.meta?.body?.error?.reason || e.message); process.exit(1) })
