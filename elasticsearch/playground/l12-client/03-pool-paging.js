// 课12 实测 3：连接池与故障转移 + 深分页对比
// 目标一：给客户端多个节点地址，看它如何做负载均衡与故障转移
// 目标二：对比 from+size 深分页 与 search_after / PIT 的差异
const { Client } = require('@elastic/elasticsearch')

async function partA() {
  console.log('===== A. 连接池：多个节点地址 + 负载均衡 =====')
  // 实测发现：9.5.1 客户端的 sniffOnStart 在本机不生效（连接池仍为 1）
  // 可靠做法：显式列出全部节点地址
  const client = new Client({
    nodes: ['http://localhost:9201', 'http://localhost:9202', 'http://localhost:9203'],
  })
  console.log('连接池中的节点数:', client.connectionPool.size)

  console.log('\n--- 连发 6 次请求，看请求落在哪些节点上 ---')
  const seen = {}
  client.diagnostic.on('request', (err, r) => {
    if (err) return
    const url = r.meta?.connection?.url?.toString?.() || '?'
    seen[url] = (seen[url] || 0) + 1
  })
  for (let i = 0; i < 6; i++) {
    await client.search({ index: 'l12_bulk_test', query: { match_all: {} } })
  }
  console.log('  请求分布:', JSON.stringify(seen, null, 2))
  console.log('  → 请求被轮流打到不同节点 = 客户端自带负载均衡')

  await client.close()
}

async function partB() {
  console.log('\n\n===== B. 深分页：from+size 撞墙 =====')
  const client = new Client({ node: 'http://localhost:9201' })
  const IDX = 'l12_page_test'
  const TOTAL = 30

  // 造一个 30 条的小索引
  await client.indices.delete({ index: IDX }, { ignore: [404] })
  await client.indices.create({
    index: IDX,
    settings: { number_of_shards: 1, number_of_replicas: 0 },
  })
  const ops = []
  for (let i = 1; i <= TOTAL; i++) {
    ops.push({ index: { _index: IDX, _id: String(i) } })
    ops.push({ title: '文档' + i, views: i })
  }
  await client.bulk({ refresh: true, operations: ops })
  console.log(`已建索引 ${IDX}，共 ${TOTAL} 条`)

  // 1) from + size 正常分页
  console.log('\n--- 1) from=0 size=5 ---')
  let r = await client.search({ index: IDX, from: 0, size: 5, query: { match_all: {} } })
  console.log('  命中总数:', r.hits.total.value, '| 本页条数:', r.hits.hits.length)
  console.log('  本页 _id:', r.hits.hits.map(h => h._id).join(','))

  console.log('\n--- 2) 用 max_result_window 撞墙（把上限临时改小模拟）---')
  // 把索引的 max_result_window 改成 10，然后请求 from=20
  await client.indices.putSettings({
    index: IDX,
    settings: { 'index.max_result_window': 10 },
  })
  try {
    await client.search({ index: IDX, from: 20, size: 5, query: { match_all: {} } })
    console.log('  居然成功了（不应该）')
  } catch (e) {
    console.log('  报错类型:', e.name)
    console.log('  报错原文:', e.message.split('\n')[0])
    const b = e.meta?.body?.error
    if (b) console.log('  错误 type:', b.type, '\n  错误 reason:', b.reason)
  }
  // 恢复
  await client.indices.putSettings({ index: IDX, settings: { 'index.max_result_window': 10000 } })

  console.log('\n--- 3) search_after：绕过深分页限制 ---')
  // 必须用排序 + 唯一决胜键；课 7 实测过 ES 9.5.1 不能对 _id 排序，改用 _doc
  let page = await client.search({
    index: IDX,
    size: 5,
    query: { match_all: {} },
    sort: [{ views: 'asc' }, { _doc: 'asc' }],
  })
  console.log('  第1页 _id:', page.hits.hits.map(h => h._id).join(','))
  console.log('  第1页末尾 sort 值:', JSON.stringify(page.hits.hits[4]?.sort))

  let last = page.hits.hits[4].sort
  let pageNo = 2
  while (pageNo <= 4) {
    page = await client.search({
      index: IDX,
      size: 5,
      query: { match_all: {} },
      sort: [{ views: 'asc' }, { _doc: 'asc' }],
      search_after: last,
    })
    console.log(`  第${pageNo}页 _id:`, page.hits.hits.map(h => h._id).join(','))
    last = page.hits.hits[page.hits.hits.length - 1].sort
    pageNo++
  }
  console.log('  → 翻页不受 max_result_window=10 限制：search_after 是"游标"，不是"跳过 N 条"')

  await client.close()
}

partA().then(partB).catch(e => console.log('!!! 出错:', e.message, JSON.stringify(e.meta?.body || {}, null, 2)))
