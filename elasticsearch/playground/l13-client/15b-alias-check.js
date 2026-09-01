// 课 15 复核：对别名做索引级操作的真实行为
// 疑点：对别名 putSettings 竟然"成功"了。别名到底能不能承载写设置？
const { Client } = require('@elastic/elasticsearch')
const client = new Client({ node: 'http://localhost:9201' })
const log = (...a) => console.log(...a)
const sep = (t) => log('\n===== ' + t + ' =====')

async function cleanup() {
  for (const p of ['l15_chk_a', 'l15_chk_b']) {
    try { await client.indices.delete({ index: p }) } catch (e) {}
  }
}

async function main() {
  await cleanup()
  await client.indices.create({ index: 'l15_chk_a', settings: { number_of_shards: 1, number_of_replicas: 0 } })
  await client.indices.create({ index: 'l15_chk_b', settings: { number_of_shards: 1, number_of_replicas: 0 } })
  await client.indices.updateAliases({
    actions: [
      { add: { index: 'l15_chk_a', alias: 'l15_one_to_one' } },
      { add: { index: 'l15_chk_a', alias: 'l15_multi_alias' } },
      { add: { index: 'l15_chk_b', alias: 'l15_multi_alias' } },
    ],
  })

  sep('1. 别名指向单个索引时，对它改设置')
  try {
    const r = await client.indices.putSettings({ index: 'l15_one_to_one', settings: { 'index.refresh_interval': '13s' } })
    log('返回 =', JSON.stringify(r))
    const a = await client.indices.get({ index: 'l15_chk_a' })
    log('真实索引 l15_chk_a 的 refresh_interval 变成 =', a['l15_chk_a'].settings.index.refresh_interval)
    log('结论：别名指向单个索引时，改设置 = 穿透到那个索引')
  } catch (e) {
    log('报错：', e.meta?.body?.error?.type, '→', e.meta?.body?.error?.reason)
  }

  sep('2. 别名指向多个索引时，对它改设置')
  try {
    const r = await client.indices.putSettings({ index: 'l15_multi_alias', settings: { 'index.refresh_interval': '17s' } })
    log('返回 =', JSON.stringify(r))
    log('居然成功了？检查两个索引各自的值：')
    for (const i of ['l15_chk_a', 'l15_chk_b']) {
      const g = await client.indices.get({ index: i })
      log(`  ${i} refresh_interval =`, g[i].settings.index.refresh_interval)
    }
  } catch (e) {
    log('报错：', e.meta?.body?.error?.type)
    log('  →', e.meta?.body?.error?.reason)
  }

  sep('3. 对别名做 close 操作（明确要求单索引的操作）')
  try {
    await client.indices.close({ index: 'l15_multi_alias' })
    log('close 成功')
  } catch (e) {
    log('close 报错：', e.meta?.body?.error?.type)
    log('  →', e.meta?.body?.error?.reason)
  }

  sep('4. 对别名做 delete 操作')
  try {
    await client.indices.delete({ index: 'l15_multi_alias' })
    log('delete 成功（危险！会把别名下所有真实索引一起删掉）')
  } catch (e) {
    log('delete 报错：', e.meta?.body?.error?.type)
    log('  →', e.meta?.body?.error?.reason)
    log('  → 这正说明：删别名要用 _aliases 的 remove，不能用 DELETE /<别名>')
  }

  sep('5. 查一下别名目前还剩什么')
  try {
    const al = await client.indices.getAlias({ name: '*' })
    log('仍存在的别名（l15 开头）：', Object.keys(al).length ? '见下' : '无')
  } catch (e) {
    log('查别名报错：', e.meta?.body?.error?.reason || e.message)
  }

  sep('实测结论')
  log('别名在"写"这条路上是半透的：读写文档可以，索引级操作会穿透或报错，取决于指向几个索引')
}

main().catch(e => { console.error('FAILED:', e.meta?.body?.error?.reason || e.message); process.exit(1) })
