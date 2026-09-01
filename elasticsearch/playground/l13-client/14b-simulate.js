// 课 15 补测：_simulate_index 返回体结构探测
const { Client } = require('@elastic/elasticsearch')
const client = new Client({ node: 'http://localhost:9201' })

async function main() {
  const r = await client.indices.simulateIndexTemplate({ name: 'l15-tpl-x-0001' })
  console.log('顶层字段 =', Object.keys(r))
  console.log('---完整返回（截断 4000 字符）---')
  console.log(JSON.stringify(r, null, 2).slice(0, 4000))
  console.log('\n---raw body 顶层字段 =', Object.keys(r.body || r))
}
main().catch(e => console.error('FAILED:', e.meta?.body?.error?.reason || e.message))
