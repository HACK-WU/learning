// 课13 实测 3：RAG 最小闭环（无外部大模型版）
// 目标：证明 RAG = 检索（ES 负责）+ 生成（LLM 负责）
// 本课只用 ES 做"检索"这一半，把"生成"这一步用模板模拟出来
// 这样你能看清 RAG 的骨架，而不用先去申请一个大模型 API Key
const { Client } = require('@elastic/elasticsearch')

const client = new Client({ node: 'http://localhost:9201' })
const IDX = 'l13_rag_kb'

async function main() {
  console.log('===== 第 1 步：准备知识库（把文档切成 chunk）=====')
  await client.indices.delete({ index: IDX }, { ignore: [404] })
  await client.indices.create({
    index: IDX,
    settings: { number_of_shards: 1, number_of_replicas: 0 },
    mappings: {
      properties: {
        // chunk 的文本
        content: { type: 'text', analyzer: 'standard' },
        // chunk 的向量（真实场景由 embedding 模型生成）
        content_vector: { type: 'dense_vector', dims: 3, similarity: 'cosine' },
        source: { type: 'keyword' },
      },
    },
  })

  // 模拟一份"内部知识库"，已经被切成 5 个 chunk
  // 向量空间：维度1≈退款政策，维度2≈物流配送，维度3≈账号安全
  const chunks = [
    { id: 'c1', content: '退款政策：商品签收后 7 天内可申请无理由退货，15 天内可换货。', vec: [0.95, 0.05, 0.0], source: 'policy.md' },
    { id: 'c2', content: '退款到账时间：审核通过后 3-5 个工作日退回原支付账户。', vec: [0.9, 0.1, 0.0], source: 'policy.md' },
    { id: 'c3', content: '配送范围：全国包邮，偏远地区（新疆、西藏）需加收 20 元运费。', vec: [0.05, 0.92, 0.0], source: 'shipping.md' },
    { id: 'c4', content: '配送时效：一线城市次日达，其他城市 2-3 天。', vec: [0.0, 0.95, 0.05], source: 'shipping.md' },
    { id: 'c5', content: '账号安全：建议开启两步验证，密码需包含大小写字母和数字。', vec: [0.0, 0.05, 0.95], source: 'security.md' },
  ]
  const ops = []
  chunks.forEach(c => {
    ops.push({ index: { _index: IDX, _id: c.id } })
    ops.push({ content: c.content, content_vector: c.vec, source: c.source })
  })
  await client.bulk({ refresh: true, operations: ops })
  console.log('知识库已建，共 ' + chunks.length + ' 个 chunk')

  // ===== 下面模拟 RAG 的完整流程 =====
  const question = '我买的东西什么时候能退钱？'
  console.log('\n===== 第 2 步：用户提问 =====')
  console.log('问题: "' + question + '"')

  console.log('\n===== 第 3 步：把问题转成向量（Embedding）=====')
  // 真实场景：调用 embedding 模型把问题转成向量
  // 这里我们手工指定：这个问题明显偏"退款"语义
  const queryVector = [0.92, 0.1, 0.0]
  console.log('问题向量:', JSON.stringify(queryVector), '（真实场景由 embedding 模型生成）')

  console.log('\n===== 第 4 步：向量检索，召回最相关的 chunk（Retrieval）=====')
  const retrieved = await client.search({
    index: IDX,
    knn: {
      field: 'content_vector',
      query_vector: queryVector,
      k: 2,
      num_candidates: 10,
    },
    _source: ['content', 'source'],
  })
  console.log('召回 ' + retrieved.hits.hits.length + ' 个 chunk:')
  const contexts = []
  retrieved.hits.hits.forEach((h, i) => {
    console.log(`  [${i + 1}] (score ${h._score.toFixed(4)}) [${h._source.source}]`)
    console.log(`      ${h._source.content}`)
    contexts.push(h._source.content)
  })

  console.log('\n===== 第 5 步：拼 Prompt（Augmentation）=====')
  const prompt = `你是客服助手。请只根据下面提供的资料回答用户问题，不要编造。\n\n【参考资料】\n${contexts.map((c, i) => `${i + 1}. ${c}`).join('\n')}\n\n【用户问题】${question}\n\n【回答】`
  console.log('--- 即将发给大模型的 Prompt ---')
  console.log(prompt)
  console.log('-------------------------------')

  console.log('\n===== 第 6 步：大模型生成（Generation）—— 本课用模板模拟 =====')
  console.log('（真实场景这里调用 LLM API；本课模拟输出）')
  console.log('')
  console.log('  >> 模拟回答：')
  console.log('     审核通过后 3-5 个工作日退回原支付账户。')
  console.log('     另外，商品签收后 7 天内可申请无理由退货，15 天内可换货。')

  console.log('\n===== 第 7 步：关键对照 —— 不检索会怎样 =====')
  console.log('如果直接问大模型、不给资料，它可能：')
  console.log('  1. 用通用常识回答（"一般 7 个工作日"）→ 与你公司真实政策不符')
  console.log('  2. 编造一个看似合理的数字 → 这就是"幻觉"（hallucination）')
  console.log('  3. 无法回答你公司内部独有的政策 → 因为训练数据里没有')
  console.log('')
  console.log('RAG 的价值：让回答有据可依，且能引用来源。')

  console.log('\n===== 第 8 步：换个问题，看检索如何切换 =====')
  const q2vec = [0.0, 0.93, 0.0] // 物流语义
  const r2 = await client.search({
    index: IDX,
    knn: { field: 'content_vector', query_vector: q2vec, k: 2, num_candidates: 10 },
    _source: ['content', 'source'],
  })
  console.log('问题换成"多久能送到" → 召回:')
  r2.hits.hits.forEach((h, i) => console.log(`  [${i + 1}] [${h._source.source}] ${h._source.content}`))
}

main().catch(e => {
  console.log('!!! 出错:', e.message)
  console.log(JSON.stringify(e.meta?.body?.error?.root_cause || {}, null, 2))
})
