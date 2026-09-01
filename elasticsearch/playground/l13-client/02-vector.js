// 课13 实测 2：向量检索（dense_vector + kNN）
// 目标：不用任何外部大模型，纯手工构造 3 维向量，证明"语义相似 = 向量空间里距离近"
// 这是理解 RAG 的最小可运行模型
const { Client } = require('@elastic/elasticsearch')

const client = new Client({ node: 'http://localhost:9201' })
const IDX = 'l13_vector_demo'

async function main() {
  console.log('===== 1. 建索引：3 维 dense_vector =====')
  await client.indices.delete({ index: IDX }, { ignore: [404] })
  await client.indices.create({
    index: IDX,
    settings: { number_of_shards: 1, number_of_replicas: 0 },
    mappings: {
      properties: {
        title: { type: 'text' },
        // 关键：dims 必须与写入的向量维度一致
        // similarity 用 cosine（余弦相似度），文本语义检索的标配
        embedding: { type: 'dense_vector', dims: 3, similarity: 'cosine' },
      },
    },
  })
  console.log('索引已建: ' + IDX + ' (dims=3, similarity=cosine)')

  console.log('\n===== 2. 手工构造向量（模拟 embedding 模型输出）=====')
  // 真实场景里这些向量由 embedding 模型生成
  // 这里我们手工构造一个"语义可解释"的空间：
  //   维度1 ≈ 动物性，维度2 ≈ 科技性，维度3 ≈ 食物性
  const docs = [
    { id: '1', title: '猫是一种宠物', vec: [0.9, 0.1, 0.0] },
    { id: '2', title: '狗是人类的朋友', vec: [0.85, 0.05, 0.1] },
    { id: '3', title: '手机是通讯工具', vec: [0.05, 0.95, 0.0] },
    { id: '4', title: '笔记本电脑', vec: [0.0, 0.9, 0.05] },
    { id: '5', title: '披萨是意大利美食', vec: [0.05, 0.05, 0.9] },
    { id: '6', title: '汉堡是快餐', vec: [0.0, 0.1, 0.85] },
  ]
  const ops = []
  docs.forEach(d => {
    ops.push({ index: { _index: IDX, _id: d.id } })
    ops.push({ title: d.title, embedding: d.vec })
  })
  const bulk = await client.bulk({ refresh: true, operations: ops })
  console.log('写入 ' + docs.length + ' 条, errors =', bulk.errors)

  console.log('\n===== 3. 关键对比：关键词搜索 vs 向量搜索 =====')
  const queryText = '宠物'
  console.log('查询词: "' + queryText + '"')

  // (a) 传统关键词搜索：text 字段用标准分词器
  console.log('\n--- (a) 关键词 match 搜索 "宠物" ---')
  const kw = await client.search({
    index: IDX,
    query: { match: { title: queryText } },
  })
  console.log('  命中数:', kw.hits.total.value)
  kw.hits.hits.forEach(h => console.log('    -', h._source.title, '| score:', h._score.toFixed(3)))

  // (b) 向量搜索：查询向量代表"动物"语义
  // 注意：真实场景里这个向量由 embedding 模型把"宠物"转成向量
  console.log('\n--- (b) 向量 kNN 搜索（查询向量 = 动物语义 [0.88, 0.05, 0.05]）---')
  const knn = await client.search({
    index: IDX,
    knn: {
      field: 'embedding',
      query_vector: [0.88, 0.05, 0.05], // ← "宠物" 的语义向量
      k: 3,
      num_candidates: 10,
    },
    _source: ['title'],
  })
  console.log('  命中数:', knn.hits.total.value)
  knn.hits.hits.forEach(h => console.log('    -', h._source.title, '| score:', h._score.toFixed(4)))

  console.log('\n===== 4. 换个查询向量：科技语义 =====')
  const knn2 = await client.search({
    index: IDX,
    knn: {
      field: 'embedding',
      query_vector: [0.0, 0.92, 0.0], // ← 科技语义
      k: 3,
      num_candidates: 10,
    },
    _source: ['title'],
  })
  knn2.hits.hits.forEach(h => console.log('    -', h._source.title, '| score:', h._score.toFixed(4)))

  console.log('\n===== 5. 踩坑验证：维度不匹配会怎样 =====')
  try {
    await client.search({
      index: IDX,
      knn: { field: 'embedding', query_vector: [1, 2], k: 1, num_candidates: 10 },
    })
  } catch (e) {
    console.log('  报错:', e.message.split('\n')[0])
    const rc = e.meta?.body?.error?.root_cause?.[0]
    if (rc) console.log('  根因:', rc.reason)
  }

  console.log('\n===== 6. 混合检索：向量 + 关键词过滤 =====')
  const hybrid = await client.search({
    index: IDX,
    knn: {
      field: 'embedding',
      query_vector: [0.88, 0.05, 0.05],
      k: 5,
      num_candidates: 10,
      filter: { term: { title: '猫' } }, // 关键词前置过滤
    },
    _source: ['title'],
  })
  console.log('  向量相似 + 标题含"猫" 的命中数:', hybrid.hits.total.value)
  hybrid.hits.hits.forEach(h => console.log('    -', h._source.title))
}

main().catch(e => {
  console.log('!!! 出错:', e.message)
  console.log(JSON.stringify(e.meta?.body?.error?.root_cause || {}, null, 2))
})
