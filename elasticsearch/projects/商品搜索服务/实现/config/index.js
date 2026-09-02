// 配置外置：集群连接、索引命名、批量与分页参数集中在这里
// 设计意图：业务代码（sync / search / ops）不写死任何地址与索引名，
//           换环境只改本文件，符合「可维护性」这条非功能约束。

/**
 * 两套连接档位：
 * - cluster：9201 三节点学习集群（默认）——有 IK 分词插件、3 个节点能放副本、未开安全
 * - secure ：9200 单节点集群——开了安全 + TLS（自签证书），用来演示 RBAC
 *
 * 注意：不要把密码写进代码库。真实项目用环境变量注入（这里密码来自本机学习环境，
 * 见 elasticsearch/00-学习档案.md 的环境探测结论）。
 */
export const profiles = {
  cluster: {
    label: '9201 三节点学习集群（默认）',
    nodes: ['http://localhost:9201', 'http://localhost:9202', 'http://localhost:9203'],
    auth: null,
    // 未开安全、HTTP 明文，无需 TLS 配置
    tls: null
  },
  secure: {
    label: '9200 单节点集群（安全 + TLS）',
    nodes: ['https://localhost:9200'],
    auth: { username: 'elastic', password: '9PvhcGNNc86uFZb_ePAN' },
    // 本机 9200 用的是首次启动时自动生成的自签证书，Node 默认会拒绝
    tls: { rejectUnauthorized: false }
  }
};

/** 取当前生效的连接档位（默认 cluster，用 ES_PROFILE=secure 切换） */
export function activeProfile() {
  const name = process.env.ES_PROFILE || 'cluster';
  const profile = profiles[name];
  if (!profile) {
    throw new Error(`未知的连接档位 "${name}"，可选：${Object.keys(profiles).join(' / ')}`);
  }
  return profile;
}

/** 索引 / 模板 / 别名的统一命名（全部 cap_ 前缀，方便一键清理与识别） */
export const naming = {
  alias: 'cap_products', // 应用只认这个别名，永不直连具体索引
  writeAlias: 'cap_products', // 写入与搜索共用一个别名，靠 is_write_index 指定写入目标
  v1: 'cap_products_v1',
  v2: 'cap_products_v2',
  template: 'cap-products', // 索引模板（priority 200，匹配 cap_products-*）
  compSettings: 'cap-products-settings', // 组件模板：settings（分片/副本/刷新）
  compMappingsV1: 'cap-products-mappings-v1', // 组件模板：v1 映射
  compMappingsV2: 'cap-products-mappings-v2', // 组件模板：v2 映射
  logsStream: 'cap_search_logs', // 搜索日志数据流（演示 ILM + 自动滚动）
  logsTemplate: 'cap-search-logs',
  logsPolicy: 'cap-search-logs-policy'
};

/** 批量写入参数 */
export const bulkCfg = {
  batchSize: 20, // 每批多少条（真实项目通常 500-5000，这里数据少取小值便于观察）
  maxRetries: 3, // 可重试错误（429 / 503）的最大重试次数
  baseDelayMs: 300 // 指数退避的基数：300ms → 600ms → 1200ms
};

/** 分页参数 */
export const pageCfg = {
  defaultSize: 10,
  exportSize: 10, // search_after 导出时每页条数
  maxResultWindow: 10000 // 索引默认上限，深分页必须绕开它
};

/** 价格区间分面的边界（与 search/facets.js 里的 range 聚合保持一致） */
export const priceRanges = [
  { key: '千元以下', to: 1000 },
  { key: '1000-3000', from: 1000, to: 3000 },
  { key: '3000-6000', from: 3000, to: 6000 },
  { key: '6000-10000', from: 6000, to: 10000 },
  { key: '万元以上', from: 10000 }
];

/** 小的睡眠工具（退避与等待 ILM 用） */
export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
