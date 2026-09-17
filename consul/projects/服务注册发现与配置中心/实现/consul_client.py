"""Consul 客户端封装（基于标准库 urllib，零第三方依赖）

对应知识点：
- 课 2 架构角色：所有交互都走本地 Client agent 的 HTTP 接口（而非直连 Server）
- 课 5 读模式：default / consistent / stale 三种读模式由调用方按需选择
- 课 6 阻塞查询：所有 watch 类方法基于 X-Consul-Index 实现
- 非功能约束（错误处理）：区分「网络层异常」与「HTTP 层错误」，并做超时控制
"""

import json
import urllib.error
import urllib.parse
import urllib.request

# 本地 Client agent 的 HTTP 接口地址。
# 知识点回指（课 2）：agent 分 Server / Client 两种角色，应用永远只和本机 Client agent 说话，
# 由 agent 负责与 Server 集群通信——应用代码里不该出现任何 Server 地址。
DEFAULT_ADDR = 'http://127.0.0.1:8500'


class ConsulError(Exception):
    """Consul 返回了非 2xx 响应。保留状态码，便于调用方按码分支处理。"""
    def __init__(self, status, body):
        super().__init__(f'Consul HTTP {status}: {body[:200]}')
        self.status = status
        self.body = body


class Consul:
    def __init__(self, addr=DEFAULT_ADDR, timeout=5.0):
        self.addr = addr.rstrip('/')
        self.timeout = timeout

    # ---------- 底层：一次 HTTP 请求 ----------
    def _request(self, method, path, params=None, body=None, timeout=None):
        """发一次 HTTP 请求。

        timeout 参数为什么存在（本项目实测踩坑）：
        urllib 的 timeout 是「整个请求的总耗时上限」，不是「连接超时」。
        阻塞查询会让服务端挂起请求直到配置变更（比如 wait=60s），
        如果沿用默认的 5 秒超时，请求必然在变更到达前就 TimeoutError。
        所以阻塞查询类请求必须单独传入大于 wait 的超时。
        """
        url = self.addr + path
        if params:
            # 空值参数（如 index=None）不拼进 URL，避免 ?index= 这种脏参数
            clean = {k: v for k, v in params.items() if v is not None}
            if clean:
                url += '?' + urllib.parse.urlencode(clean)

        data = None
        if body is not None:
            data = body.encode('utf-8') if isinstance(body, str) else body

        req = urllib.request.Request(url, data=data, method=method)
        try:
            with urllib.request.urlopen(req, timeout=timeout or self.timeout) as resp:
                raw = resp.read().decode('utf-8')
                # 阻塞查询靠响应头拿 index，所以把头一起返回。
                # 2026-09-17 补充：一并带上 X-Consul-LastContact 与 X-Consul-KnownLeader。
                # 这两个头是「stale 读有多旧」的唯一量化来源（实战篇 A 实测）：
                #   LastContact 单位为毫秒，0 表示数据就是 leader 上的最新值；
                #   stale 读时实测为 15~45ms，default/consistent 恒为 0。
                # 不返回它们，调用方就无法判断"我读到的东西新不新"。
                return {
                    'status': resp.status,
                    'index': resp.headers.get('X-Consul-Index'),
                    'last_contact': resp.headers.get('X-Consul-LastContact'),
                    'known_leader': resp.headers.get('X-Consul-KnownLeader'),
                    'body': json.loads(raw) if raw.strip() else None,
                }
        except urllib.error.HTTPError as e:
            # 4xx/5xx 也是「有效响应」——比如 kv 键不存在返回 404，是正常业务分支不是异常
            raw = e.read().decode('utf-8', 'replace')
            raise ConsulError(e.code, raw) from None

    # ---------- 服务注册 ----------
    def register(self, payload):
        """注册服务。payload 为服务定义字典（含可选的 check / checks 健康检查）。

        知识点回指（课 4）：健康检查随服务一起注册，由 agent 本地执行，
        检查失败后服务在本 agent 视角变为 critical，但不会立刻从 catalog 消失。
        """
        return self._request('PUT', '/v1/agent/service/register', body=json.dumps(payload))

    def deregister(self, service_id):
        return self._request('PUT', f'/v1/agent/service/deregister/{service_id}')

    # ---------- 服务发现 ----------
    def health_service(self, name, passing=True, dc=None, consistency=None):
        """查健康的服务实例。

        知识点回指（课 4）：/v1/health/service 返回的是 agent 本地视角的健康状态，
        与 /v1/catalog/service（目录视角）不同——只有前者带健康过滤。

        consistency 参数（课 5 + 实战篇 A 实测）：
          None          default 模式，走 leader
          'consistent'  走 leader 并额外做一次 quorum 确认
          'stale'       任意节点（含 follower）直接应答，可能读到旧值

        实战篇 A 的三节点实测结论：
          - 服务发现这类场景**推荐 stale**：少一个实例晚几毫秒被发现无所谓，
            而 leader 选举期间（实测约 9.5 秒）default/consistent 会直接 500，
            stale 仍能返回旧列表——可用性换新鲜度，这笔交易对服务发现是划算的。
          - 但要注意：quorum 丢失时（三节点挂两个）stale **同样不可用**（实测 404）。
            stale 换的是"选举期间可用"，不是"灾备能力"。
        """
        params = {'passing': 'true' if passing else 'false', 'dc': dc}
        if consistency:
            params[consistency] = 'true'
        return self._request('GET', f'/v1/health/service/{name}', params)

    # ---------- KV ----------
    def kv_get(self, key, index=None, wait=None, recurse=False, dc=None, timeout=None,
               consistency=None):
        """读 KV，支持阻塞查询。

        知识点回指（课 6）：阻塞查询必须用响应头 X-Consul-Index 的值作为下一次的 index 参数。
        用 body 里的 ModifyIndex 会导致「秒回旧值」——课 6 实测踩过的坑。

        另外：发起阻塞查询时 timeout 必须大于 wait，否则客户端先超时（本项目实测）。

        consistency 参数（课 5 + 实战篇 A）：
          None          default 模式
          'consistent'  走 leader + quorum 确认，适合读配置这类要求准确的场景
          'stale'       任意节点应答；**不要用在阻塞查询上**——stale 读不保证
                        单调，可能让你错过变更或读到回退的值（实战篇 A 实测
                        写后立即读 stale 稳定落后一个版本）。
        """
        params = {'index': index, 'wait': wait, 'recurse': 'true' if recurse else 'false', 'dc': dc}
        if consistency:
            params[consistency] = 'true'
        return self._request('GET', f'/v1/kv/{key}', params, timeout=timeout)

    def kv_put(self, key, value):
        return self._request('PUT', f'/v1/kv/{key}', body=value)

    def kv_delete(self, key, recurse=False):
        params = {'recurse': 'true' if recurse else 'false'}
        return self._request('DELETE', f'/v1/kv/{key}', params)

    # ---------- 会话与锁 ----------
    def session_create(self, name=None, ttl='30s', behavior='release'):
        """创建会话。

        知识点回指（课 6）：会话是分布式锁的「租约凭证」，TTL 到期或会话被销毁，
        它持有的锁会自动释放——这是锁不会变成死锁的关键。
        """
        payload = {'TTL': ttl, 'Behavior': behavior}
        if name:
            payload['Name'] = name
        return self._request('PUT', '/v1/session/create', body=json.dumps(payload))

    def session_renew(self, session_id):
        return self._request('PUT', f'/v1/session/renew/{session_id}')

    def session_destroy(self, session_id):
        return self._request('PUT', f'/v1/session/destroy/{session_id}')

    def kv_acquire(self, key, session_id, value=''):
        """用会话抢占锁（对 KV 键加锁）。返回 True 表示抢到。"""
        params = {'acquire': session_id}
        return self._request('PUT', f'/v1/kv/{key}', params, body=value)

    def kv_release(self, key, session_id):
        params = {'release': session_id}
        return self._request('PUT', f'/v1/kv/{key}', params)

    # ---------- 集群观测 ----------
    def leader(self):
        """当前 Raft leader。

        知识点回指（课 5）：写请求必须由 leader 处理；leader 不存在（空字符串）
        通常意味着 quorum 丢失，此时写操作会 500。
        """
        return self._request('GET', '/v1/status/leader')['body']

    def peers(self):
        return self._request('GET', '/v1/status/peers')['body']
