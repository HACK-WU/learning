// 课12 实测 2：bulk 批量写入 + 局部失败 + 重试幂等
// 目标：证明 bulk 是"逐条独立成功/失败"，不是整体的事务
const { Client } = require('@elastic/elasticsearch')

const client = new Client({ node: 'http://localhost:9201' })

const IDX = 'l12_bulk_test'

async function main() {
  // 准备索引：price 定义为 long（数字），用于制造"类型不匹配"的失败
  await client.indices.delete({ index: IDX }, { ignore: [404] })
  await client.indices.create({
    index: IDX,
    settings: { number_of_shards: 1, number_of_replicas: 0 },
    mappings: { properties: { title: { type: 'text' }, price: { type: 'long' } } },
  })
  console.log('索引已重建: ' + IDX + ' (price = long)')

  console.log('\n===== 1. bulk 写入：3 条正常 + 1 条类型错误 =====')
  // 第 4 条故意写 "abc" 给 long 字段，制造失败
  const res = await client.bulk({
    refresh: true,
    operations: [
      { index: { _index: IDX, _id: '1' } },
      { title: '正常文档一', price: 100 },
      { index: { _index: IDX, _id: '2' } },
      { title: '正常文档二', price: 200 },
      { index: { _index: IDX, _id: '3' } },
      { title: '正常文档三', price: 300 },
      { index: { _index: IDX, _id: '4' } },
      { title: '类型错误文档', price: 'abc' }, // ← 这行会失败
    ],
  })

  console.log('bulk 顶层结果: errors =', res.errors, '| took =', res.took, 'ms')
  console.log('\n--- 逐条 items 结果 ---')
  res.items.forEach((it, i) => {
    const op = it.index
    if (op.error) {
      console.log(`  [${i}] FAILED  _id=${op._id}  status=${op.status}`)
      console.log(`         type   : ${op.error.type}`)
      console.log(`         reason : ${op.error.reason}`)
    } else {
      console.log(`  [${i}] OK      _id=${op._id}  result=${op.result}  status=${op.status}`)
    }
  })

  console.log('\n===== 2. 验证：失败的那条到底写进去没有 =====')
  const cnt = await client.count({ index: IDX })
  console.log('索引实际文档数:', cnt.count, '（写了 4 条，成功的应该只有 3 条）')
  const got4 = await client.exists({ index: IDX, id: '4' })
  console.log('_id=4 是否存在:', got4)

  console.log('\n===== 3. 幂等性验证：重复写入同一 _id =====')
  // 同一个 _id 反复写，观察 result 与 _version 的变化
  for (let i = 1; i <= 3; i++) {
    const r = await client.index({
      index: IDX,
      id: '1', // 固定 _id
      refresh: true,
      document: { title: '第' + i + '次覆盖', price: i * 1000 },
    })
    console.log(`  第 ${i} 次: result=${r.result}  _version=${r._version}  _seq_no=${r._seq_no}`)
  }
  console.log('  → result 从 created 变 updated，_version 递增；文档总数不变 = 幂等')

  const cnt2 = await client.count({ index: IDX })
  console.log('  覆盖 3 次后文档总数:', cnt2.count, '（仍是 3，没有变多）')

  console.log('\n===== 4. 不指定 _id 时 ES 自动生成 =====')
  const a = await client.index({ index: IDX, refresh: true, document: { title: '无ID文档', price: 1 } })
  console.log('  自动生成的 _id:', a._id, '| 长度:', a._id.length)
}

main().catch(e => {
  console.log('!!! 出错:', e.message)
  console.log(JSON.stringify(e.meta?.body || {}, null, 2))
})
