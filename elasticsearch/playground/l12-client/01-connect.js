// 课12 实测 1：官方 JS 客户端连通性 + 版本协商证据
// 重点：抓 Accept / Content-Type 请求头里的 compatible-with 版本，证明客户端做了版本协商
const { Client } = require('@elastic/elasticsearch')

// 连接本机 9201 三节点学习集群（无安全认证，http）
// 只给一个节点地址，客户端会自动做节点发现（sniffing）
const client = new Client({
  node: 'http://localhost:9201',
  // 打开请求/响应的事件监听，用来观察客户端底层行为
})

// 监听 request 事件，打印真实的请求头
// 注意：9.x 客户端的事件接口是 client.diagnostic（不是 client.on）
client.diagnostic.on('request', (err, result) => {
  if (err) {
    console.log('[请求失败]', err.message)
    return
  }
  const h = (result.meta && result.meta.request && result.meta.request.options && result.meta.request.options.headers) || {}
  console.log('--- 客户端发出的请求头 ---')
  console.log('路径        :', result.meta?.request?.options?.path)
  console.log('Accept      :', h.accept)
  console.log('Content-Type:', h['content-type'])
  console.log('User-Agent  :', h['user-agent'])
})

async function main() {
  console.log('===== 1. 连通性：客户端版本 =====')
  const pkg = require('@elastic/elasticsearch/package.json')
  console.log('客户端版本:', pkg.version)

  console.log('\n===== 2. info() 拿服务端信息 =====')
  const info = await client.info()
  console.log('服务端版本:', info.version.number)
  console.log('集群名    :', info.cluster_name)

  console.log('\n===== 3. 节点发现（sniffing）验证 =====')
  const nodes = await client.nodes.info()
  console.log('客户端发现的节点数:', Object.keys(nodes).length)
  for (const [id, n] of Object.entries(nodes)) {
    console.log('  -', n.name, n.http?.publish_address)
  }

  console.log('\n===== 4. 写一条文档（索引 l12_client_test）=====')
  const idx = 'l12_client_test'
  await client.indices.create({
    index: idx,
    settings: { number_of_shards: 1, number_of_replicas: 0 },
  }, { ignore: [400] }) // 已存在则忽略
  const write = await client.index({
    index: idx,
    id: '1',
    document: { title: '客户端写入的第一条', views: 100, ts: new Date().toISOString() },
    refresh: true,
  })
  console.log('写入结果:', write.result, '| _version:', write._version, '| _shards:', JSON.stringify(write._shards))

  console.log('\n===== 5. 立刻搜索（验证 refresh=true 生效）=====')
  const search = await client.search({
    index: idx,
    query: { match: { title: '客户端' } },
  })
  console.log('命中数:', search.hits.total.value)
  console.log('文档  :', JSON.stringify(search.hits.hits[0]?._source))

  console.log('\n===== 6. 客户端把请求打到了哪个节点（负载均衡观察）=====')
  for (let i = 0; i < 6; i++) {
    await client.search({ index: idx, query: { match_all: {} } })
  }
}

main().catch(e => {
  console.log('!!! 出错:', e.name)
  console.log('!!! 消息:', e.message)
  console.log('!!! 详情:', JSON.stringify(e.meta?.body || e.body || {}, null, 2))
})
