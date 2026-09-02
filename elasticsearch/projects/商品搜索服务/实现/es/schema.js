import { getClient, printConnection } from './client.js';
import { runIfEntry } from './cli.js';
import { naming } from '../config/index.js';

/**
 * 索引结构管理：组件模板 → 索引模板 → 索引 → 别名 → 日志数据流
 *
 * 贯穿课 5（映射）与课 15（模板 / 别名 / ILM）的三条结论：
 * 1. dynamic: strict —— 生产不让 ES 猜类型，猜错了是"不报错、静默算错"
 * 2. 模板只影响之后新建的索引 —— 改了模板，已存在的 v1 一个字都不会变
 * 3. 应用只认别名 —— 这是零停机切换的技术前提
 */

/**
 * v1 / v2 的唯一差别：title 与 description 的 search_analyzer。
 *
 * v1：不写 search_analyzer → 搜索时沿用索引时的 ik_max_word（最细粒度）
 *     → 搜「小米笔记本」会被切成「小米|笔记|本|笔记本」，那个「本」会召回一堆噪声
 * v2：显式 search_analyzer: ik_smart → 搜索时切成「小米|笔记本」，精确
 *
 * 这个差别**必须重建索引**才能生效（分析器属于映射变更，课 5 实测），
 * 所以它是 ops/reindex-switch.js 演示零停机切换的动机。
 */
function mappings(version) {
  const smartSearch = version === 'v2';
  const searchAnalyzer = smartSearch ? { search_analyzer: 'ik_smart' } : {};
  return {
    dynamic: 'strict',
    properties: {
      sku: { type: 'keyword' },
      title: {
        type: 'text',
        analyzer: 'ik_max_word',
        ...searchAnalyzer,
        fields: {
          std: { type: 'text', analyzer: 'standard' }, // 逐字切分：兜底召回
          raw: { type: 'keyword', ignore_above: 256 } // 整句精确匹配 / 排序
        }
      },
      brand: { type: 'keyword' }, // 分面统计用 keyword（课 8：text 聚合会碎桶）
      category: { type: 'keyword' },
      price: { type: 'scaled_float', scaling_factor: 100 }, // 金额无精度误差（课 5）
      sales: { type: 'integer' },
      rating: { type: 'half_float' },
      tags: { type: 'keyword' },
      description: {
        type: 'text',
        analyzer: 'ik_max_word',
        ...searchAnalyzer
      },
      on_sale: { type: 'boolean' },
      listed_at: { type: 'date' }
    }
  };
}

/** settings 组件模板：分片 / 副本 / 刷新间隔（设计决策 2 的结论落在这里） */
const settingsComponent = {
  index: {
    number_of_shards: 1, // 数据量小：单分片避免聚合误差与长尾延迟（课 10 / 课 14 实测）
    number_of_replicas: 1, // 3 节点集群放得下副本：副本是数据第二份存在，不是性能优化（课 10）
    refresh_interval: '1s',
    max_result_window: 10000
  }
};

const logsSettings = {
  index: {
    number_of_shards: 1,
    number_of_replicas: 1,
    refresh_interval: '5s',
    // ⚠️ ILM 策略必须在这里挂上，否则数据流建出来是 Unmanaged（策略存在但不生效）。
    // 这是"配了 ILM 却完全不动"最常见的根因之一。
    lifecycle: { name: 'cap-search-logs-policy' }
  }
};

/** 搜索日志的映射：@timestamp 是数据流的硬性要求；dynamic:false 让多余字段只进 _source */
const logsMappings = {
  dynamic: 'false',
  properties: {
    '@timestamp': { type: 'date' },
    keyword: { type: 'keyword' },
    brand: { type: 'keyword' },
    category: { type: 'keyword' },
    total: { type: 'integer' },
    took_ms: { type: 'integer' },
    sort: { type: 'keyword' }
  }
};

/** 日志 ILM 策略：热阶段滚动 → 温阶段合段 → 90 天删除（对应「成本」约束） */
const logsPolicy = {
  policy: {
    phases: {
      hot: {
        min_age: '0ms',
        actions: { rollover: { max_primary_shard_size: '50gb', max_age: '30d' } }
      },
      warm: {
        min_age: '7d',
        actions: { forcemerge: { max_num_segments: 1 }, set_priority: { priority: 50 } }
      },
      delete: { min_age: '90d', actions: { delete: {} } }
    }
  }
};

export async function putComponentTemplates(client) {
  await client.cluster.putComponentTemplate({
    name: naming.compSettings,
    template: { settings: settingsComponent },
    _meta: { description: '商品索引的公共 settings：分片 / 副本 / 刷新' }
  });
  await client.cluster.putComponentTemplate({
    name: naming.compMappingsV1,
    template: { mappings: mappings('v1') },
    _meta: { description: 'v1 映射：搜索沿用 ik_max_word（噪声多）' }
  });
  await client.cluster.putComponentTemplate({
    name: naming.compMappingsV2,
    template: { mappings: mappings('v2') },
    _meta: { description: 'v2 映射：搜索改 ik_smart（精确）' }
  });
  console.log('   ✅ 组件模板 × 3（settings / mappings-v1 / mappings-v2）');
}

export async function putProductsTemplate(client, version) {
  const compMappings = version === 'v2' ? naming.compMappingsV2 : naming.compMappingsV1;
  await client.indices.putIndexTemplate({
    name: naming.template,
    // ⚠️ 注意是下划线 `cap_products_*`，不是连字符 `cap_products-*`。
    // 本项目索引名统一用下划线（cap_products_v1 / v2），写成连字符会导致模板一个都匹配不上，
    // 索引照样能建成功、只是 mappings/settings 全空 —— 这种错不报错，最难查。
    index_patterns: ['cap_products_*'],
    priority: 200,
    composed_of: [naming.compSettings, compMappings],
    _meta: { description: `商品索引模板，当前指向 ${version} 映射` }
  });
  console.log(`   ✅ 索引模板 ${naming.template} → ${compMappings}（priority 200）`);
}

/** 用 _simulate_index 预览"假如现在建这个索引，最终映射长什么样"（课 15 实测可用） */
export async function simulate(client, indexName) {
  // simulateIndexTemplate → POST _index_template/_simulate_index/{索引名}（按"新建这个索引会套到什么"预览）
  // ⚠️ 别用 simulateTemplate：那个走 _simulate/{模板名}，按模板名模拟，传索引名会报 does not exist
  const res = await client.indices.simulateIndexTemplate({ name: indexName });
  const tpl = res.template;
  const props = Object.keys(tpl?.mappings?.properties ?? {});
  const titleAnalyzer = tpl?.mappings?.properties?.title?.search_analyzer ?? '(未设置 → 沿用索引分析器)';
  console.log(`   🔍 预览 ${indexName}：字段 ${props.length} 个，title.search_analyzer = ${titleAnalyzer}`);
  return tpl;
}

export async function createIndex(client, name) {
  const exists = await client.indices.exists({ index: name });
  if (exists) {
    console.log(`   ⏭  索引 ${name} 已存在，跳过创建`);
    return false;
  }
  await client.indices.create({ index: name });
  console.log(`   ✅ 索引 ${name} 已创建（由模板自动套用 settings + mappings）`);
  return true;
}

/**
 * 把别名指向目标索引。
 * 关键点：remove 与 add 放在**同一个 _aliases 请求**里 → 原子生效，不存在中间态（课 15 实测）。
 */
export async function pointAlias(client, target) {
  const actions = [];
  let existing = null;
  try {
    existing = await client.indices.getAlias({ name: naming.alias });
  } catch (e) {
    if (e?.meta?.statusCode !== 404) throw e;
  }
  if (existing) {
    for (const idxName of Object.keys(existing)) {
      actions.push({ remove: { index: idxName, alias: naming.alias } });
    }
  }
  actions.push({ add: { index: target, alias: naming.alias, is_write_index: true } });
  await client.indices.updateAliases({ actions });
  const from = existing ? Object.keys(existing).join(',') : '(无)';
  console.log(`   ✅ 别名 ${naming.alias}：${from} → ${target}（is_write_index=true，原子切换）`);
}

export async function ensureLogs(client) {
  await client.ilm.putLifecycle({ name: naming.logsPolicy, ...logsPolicy });
  await client.cluster.putComponentTemplate({
    name: 'cap-logs-settings',
    template: { settings: logsSettings },
    _meta: { description: '搜索日志 settings' }
  });
  await client.cluster.putComponentTemplate({
    name: 'cap-logs-mappings',
    template: { mappings: logsMappings },
    _meta: { description: '搜索日志映射（dynamic:false）' }
  });
  await client.indices.putIndexTemplate({
    name: naming.logsTemplate,
    index_patterns: ['cap_search_logs'],
    data_stream: {},
    priority: 300,
    composed_of: ['cap-logs-settings', 'cap-logs-mappings']
  });
  console.log(`   ✅ 日志 ILM ${naming.logsPolicy} + 数据流模板 ${naming.logsTemplate}（首次写日志时自动创建数据流）`);
}

export async function resetAll(client) {
  const toDelete = [naming.v1, naming.v2, naming.logsStream];
  for (const name of toDelete) {
    try {
      await client.indices.deleteDataStream({ name });
      console.log(`   🗑  已删数据流 ${name}`);
    } catch {
      /* 不是数据流，忽略 */
    }
  }
  for (const name of toDelete) {
    try {
      await client.indices.delete({ index: name });
      console.log(`   🗑  已删索引 ${name}`);
    } catch {
      /* 不存在，忽略 */
    }
  }
  for (const name of [
    naming.template,
    naming.logsTemplate,
    naming.compSettings,
    naming.compMappingsV1,
    naming.compMappingsV2,
    'cap-logs-settings',
    'cap-logs-mappings'
  ]) {
    try {
      await client.indices.deleteIndexTemplate({ name });
    } catch {
      /* 组件模板在另一个命名空间，忽略 */
    }
    try {
      await client.cluster.deleteComponentTemplate({ name });
    } catch {
      /* 不存在，忽略 */
    }
  }
  try {
    await client.ilm.deleteLifecycle({ name: naming.logsPolicy });
  } catch {
    /* 不存在，忽略 */
  }
  console.log('   ✅ 全部 cap_* 索引 / 数据流 / 模板 / ILM 策略已清理');
}

// ---------- CLI ----------
async function main() {
  const argv = process.argv.slice(2);
  const isReset = argv.includes('--reset');
  const toV2 = argv.includes('--to=v2');
  const client = getClient();
  await printConnection();

  if (isReset) {
    console.log('\n🧹 清理环境');
    await resetAll(client);
    return;
  }

  if (toV2) {
    console.log('\n📐 切换到 v2 结构（只改模板 + 建新索引，不动别名）');
    await putProductsTemplate(client, 'v2');
    await simulate(client, naming.v2);
    await createIndex(client, naming.v2);
    return;
  }

  console.log('\n📐 初始化 v1 结构');
  await putComponentTemplates(client);
  await putProductsTemplate(client, 'v1');
  await simulate(client, naming.v1);
  await createIndex(client, naming.v1);
  await pointAlias(client, naming.v1);
  await ensureLogs(client);
  console.log('\n🎉 初始化完成。下一步：npm run sync');
}

runIfEntry(import.meta.url, main);
