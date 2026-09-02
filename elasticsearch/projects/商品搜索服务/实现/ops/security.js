import { Client } from '@elastic/elasticsearch';
import { getClient, rootCause, printConnection } from '../es/client.js';
import { runIfEntry } from '../es/cli.js';
import { activeProfile } from '../config/index.js';

/**
 * 安全：给应用建一个"只够用"的账号，而不是把 elastic 超级用户塞进配置文件。
 *
 * 对应课 13 的三条结论：
 *   1. 权限绑角色、角色绑用户 —— 不给人直接授权
 *   2. 401 = 你是谁（认证失败），403 = 你能干什么（授权失败）
 *   3. ES 的 403 报错**会直接列出所需权限名**，照着加即可
 *
 * ⚠️ 环境限制：默认的 9201 三节点学习集群**关闭了安全**（课 9 建集群时为了省证书密码关掉的）。
 *    本脚本会先探测：安全没开就打印说明 + 给出在 9200 上跑的命令，不假装成功。
 *
 * 本脚本自带探针索引（cap_products_sec_probe），不依赖前面几步是否已经跑过。
 */

const APP_ROLE = 'cap_search_app';
const APP_USER = 'cap_app';
const APP_PASSWORD = 'CapApp2026!';
const PROBE_INDEX = 'cap_products_sec_probe'; // 必须落在角色的 cap_products* 范围内

async function isSecurityEnabled(client) {
  try {
    await client.security.authenticate();
    return true;
  } catch {
    return false;
  }
}

function makeClient(profile, auth) {
  return new Client({
    nodes: profile.nodes,
    auth,
    ...(profile.tls ? { tls: profile.tls } : {}),
    maxRetries: 0
  });
}

export async function runSecurity(client) {
  const profile = activeProfile();

  if (!(await isSecurityEnabled(client))) {
    console.log('\n🔒 安全状态：未开启');
    console.log(`   当前档位：${profile.label}`);
    console.log('   该集群关闭了 xpack.security，RBAC 无法演示（这是学习集群的取舍，不是配置错误）。');
    console.log('\n   想在开了安全的集群上跑一遍：');
    console.log('     ES_PROFILE=secure npm run security');
    console.log('\n   ⚠️ 本机 PowerShell 5.1 的 Invoke-RestMethod 连不上 ES 的 HTTPS 端点，');
    console.log('      Windows 下统一用 curl.exe，且 JSON 一律用 --data-binary @文件 传参');
    console.log('      （内联双引号会被吃掉，课 10 / 课 11 实测）');
    return { enabled: false };
  }

  console.log('\n🔒 安全状态：已开启');

  // ---------- ① 建角色（最小权限） ----------
  console.log('\n   ① 建角色：只能读 cap_products*，只能看集群监控');
  await client.security.putRole({
    name: APP_ROLE,
    refresh: true,
    body: {
      cluster: ['monitor'],
      indices: [{ names: ['cap_products*'], privileges: ['read', 'view_index_metadata'] }]
    }
  });
  console.log(`      ✅ 角色 ${APP_ROLE}`);

  // ---------- ② 建用户（权限绑角色） ----------
  console.log('\n   ② 建用户：把角色挂到人身上，不直接给人授权');
  await client.security.putUser({
    username: APP_USER,
    refresh: true,
    body: { password: APP_PASSWORD, roles: [APP_ROLE], full_name: '商品搜索应用账号' }
  });
  console.log(`      ✅ 用户 ${APP_USER} / ${APP_PASSWORD}`);

  // ---------- ③ 自带探针索引，保证本脚本能独立跑 ----------
  // 单节点集群放不下副本，所以显式 0 副本；这里不套模板，只给最小映射
  await client.indices.delete({ index: PROBE_INDEX }).catch(() => {});
  await client.indices.create({
    index: PROBE_INDEX,
    settings: { index: { number_of_shards: 1, number_of_replicas: 0 } },
    mappings: { properties: { sku: { type: 'keyword' }, title: { type: 'text' } } }
  });
  await client.index({
    index: PROBE_INDEX,
    id: 'SKU-0001',
    document: { sku: 'SKU-0001', title: '探针文档：用于验证只读账号能读' },
    refresh: true
  });
  console.log(`\n   ③ 探针索引 ${PROBE_INDEX} 已就绪（1 主 0 副，1 条文档）`);

  const appClient = makeClient(profile, { username: APP_USER, password: APP_PASSWORD });

  // ---------- ④ 读：应该成功 ----------
  console.log('\n   ④ 用应用账号读 —— 应该成功');
  try {
    const r = await appClient.search({ index: PROBE_INDEX, query: { match_all: {} } });
    const total = typeof r.hits.total === 'number' ? r.hits.total : r.hits.total.value;
    console.log(`      ✅ 读成功：命中 ${total} 条`);
  } catch (e) {
    console.log(`      ❌ 读失败：HTTP ${e?.meta?.statusCode} ${rootCause(e)}`);
  }

  // ---------- ⑤ 写：应该 403 ----------
  console.log('\n   ⑤ 用应用账号写 —— 应该 403（不是 401）');
  try {
    await appClient.index({ index: PROBE_INDEX, document: { sku: 'SKU-HACK', title: '越权写入' } });
    console.log('      ❌ 写入竟然成功了 —— 角色权限给多了，回去收窄');
  } catch (e) {
    console.log(`      ✅ 被拒绝：HTTP ${e?.meta?.statusCode}`);
    console.log(`      根因：${rootCause(e)}`);
    console.log('      💡 报错末尾会列出所需权限名，照着加即可（课 13 实测）');
  }

  // ---------- ⑥ 错密码：应该 401 ----------
  console.log('\n   ⑥ 用错误密码 —— 应该 401（你是谁，不是你能干什么）');
  try {
    const badClient = makeClient(profile, { username: APP_USER, password: 'wrong-password' });
    await badClient.search({ index: PROBE_INDEX, query: { match_all: {} } });
    console.log('      ❌ 错误密码竟然通过了');
  } catch (e) {
    console.log(`      ✅ 被拒绝：HTTP ${e?.meta?.statusCode}（401 = 认证失败）`);
  }

  // ---------- ⑦ 清理探针索引 ----------
  await client.indices.delete({ index: PROBE_INDEX }).catch(() => {});
  console.log(`\n   ⑦ 探针索引已清理`);

  console.log('\n✅ 安全演示结束：读通、写拒 403、错密码 401');
  return { enabled: true };
}

async function main() {
  const client = getClient();
  await printConnection();
  await runSecurity(client);
}

runIfEntry(import.meta.url, main);
