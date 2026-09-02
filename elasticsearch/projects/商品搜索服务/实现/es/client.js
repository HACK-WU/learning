import { Client } from '@elastic/elasticsearch';
import { activeProfile } from '../config/index.js';

// 单例：整个进程共用一个客户端，连接池会在多个节点间轮询（课 12 实测均摊 2/2/2）
let client = null;

/**
 * 取（并缓存）ES 客户端
 *
 * 课 12 的两条结论在这里落地：
 * 1. 显式列出全部节点 → 连接池把它们都纳进来，请求自动均摊，节点挂了自动绕开
 * 2. sniffOnStart 在本机实测不生效（连接池仍为 1），所以不靠它，改由显式列表保证
 */
export function getClient() {
  if (client) return client;
  const p = activeProfile();
  client = new Client({
    nodes: p.nodes,
    ...(p.auth ? { auth: p.auth } : {}),
    ...(p.tls ? { tls: p.tls } : {}),
    maxRetries: 3, // 传输层自动重试（网络抖动）
    requestTimeout: 30000,
    sniffOnStart: false
  });
  return client;
}

/**
 * 从异常里挖出真正的根因。
 *
 * 课 12 / 13 / 14 反复验证过的教训：ES 外层报错常是包装，
 * 例如外层是 search_phase_execution_exception / all shards failed，
 * 真因藏在 error.root_cause 里。打印外层等于什么都没说。
 */
export function rootCause(err) {
  const body = err?.meta?.body ?? err?.body;
  if (body?.error) {
    const rc = body.error.root_cause;
    if (Array.isArray(rc) && rc.length) {
      return rc.map((r) => `${r.type}: ${r.reason}`).join(' ｜ ');
    }
    return `${body.error.type ?? 'error'}: ${body.error.reason ?? JSON.stringify(body.error)}`;
  }
  if (body) return JSON.stringify(body).slice(0, 300);
  return err?.message ?? String(err);
}

/** 从 bulk 的单个 item 里取出错误信息（成功时返回 null） */
export function itemError(item) {
  const op = item.index ?? item.create ?? item.update ?? item.delete;
  if (!op || !op.error) return null;
  return {
    id: op._id,
    status: op.status,
    type: op.error.type,
    reason: op.error.reason
  };
}

/** 判断 bulk 失败项是否值得重试（限流/不可用是可恢复的，数据本身有问题重试一万次也没用） */
export function isRetryable(status) {
  return status === 429 || status === 503;
}

/** 打印当前连接信息，让每次运行都先说清"我连的是谁" */
export async function printConnection() {
  const p = activeProfile();
  const c = getClient();
  const info = await c.info();
  console.log(`🔌 连接档位：${p.label}`);
  console.log(`   ES 版本 ${info.version.number} ｜ 节点 ${p.nodes.length} 个 ｜ 集群 ${info.cluster_name}`);
  return info;
}
