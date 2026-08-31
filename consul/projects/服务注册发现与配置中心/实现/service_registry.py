"""服务注册与发现模块

对应知识点：
- 课 1 服务注册与发现：服务启动时自注册、下线时自注销，消费方按名字查实例
- 课 3 注册与查询：agent 本地注册 + 三视图差异
- 课 4 健康检查：TTL 检查由应用主动上报心跳（push 模型）
- 课 5 读模式：发现用 default（走 leader 但省一次往返），配置用 stale（可读 follower）
"""

import time
import urllib.request

from consul_client import Consul, ConsulError


class ServiceRegistry:
    """把一个本地 HTTP 服务注册到 Consul，并持续上报 TTL 心跳。

    封装了「注册 → 心跳 → 注销」的完整生命周期，避免调用方漏掉注销导致僵尸实例。
    """

    def __init__(self, consul, service_id, name, port, tags=None, ttl='15s'):
        self.consul = consul
        self.service_id = service_id
        self.name = name
        self.port = port
        self.tags = tags or []
        self.ttl = ttl
        self._ttl_seconds = self._parse_ttl(ttl)

    @staticmethod
    def _parse_ttl(ttl):
        """把 '15s' 解析成 15。心跳周期取 TTL 的一半，留足网络抖动余量。"""
        return int(ttl.rstrip('s'))

    def register(self):
        """注册服务，同时挂一个 TTL 健康检查。

        知识点回指（课 4）：TTL 检查是「应用主动上报」的 push 模型——
        应用必须自己在 TTL 到期前调用 pass，否则 agent 会把它标记为 critical。
        这与 HTTP/TCP 检查（agent 主动探测的 pull 模型）方向相反。
        """
        payload = {
            'ID': self.service_id,
            'Name': self.name,
            'Address': '127.0.0.1',
            'Port': self.port,
            'Tags': self.tags,
            'Check': {
                'TTL': self.ttl,
                # 服务消失后多久自动注销注册（避免节点宕机留下僵尸实例）
                'DeregisterCriticalServiceAfter': '1m',
            },
        }
        self.consul.register(payload)
        # TTL 检查刚注册时状态是 critical，先主动 pass 一次让它变成 passing
        self.heartbeat()
        return self

    def heartbeat(self):
        """上报一次心跳，标记本实例存活。"""
        try:
            urllib.request.urlopen(
                urllib.request.Request(
                    f'{self.consul.addr}/v1/agent/check/pass/service:{self.service_id}',
                    method='PUT'),
                timeout=self.consul.timeout).read()
        except Exception:
            # 心跳失败不致命——下一次心跳会补上，只有连续错过 TTL 才会被判 critical
            pass

    def keep_alive(self, stop_event):
        """后台心跳循环：每隔 TTL/2 上报一次，直到 stop_event 被置位。

        TTL 的一半是经验值：既保证网络抖动时有重试机会，又不会让心跳过于频繁。
        """
        interval = max(self._ttl_seconds / 2, 1)
        while not stop_event.is_set():
            self.heartbeat()
            stop_event.wait(interval)

    def deregister(self):
        self.consul.deregister(self.service_id)


def discover(consul, name, dc=None):
    """按服务名查健康实例，返回规格化后的列表。

    知识点回指（课 4）：这里用 /v1/health/service 而不是 /v1/catalog/service——
    后者是目录视角，不反映健康状态，会返回已经挂掉的实例。
    """
    try:
        result = consul.health_service(name, passing=True, dc=dc)
    except ConsulError as e:
        if e.status == 404:
            return []
        raise

    instances = []
    for item in result['body'] or []:
        svc = item['Service']
        instances.append({
            'id': svc['ID'],
            'address': svc['Address'],
            'port': svc['Port'],
            'tags': svc.get('Tags') or [],
        })
    return instances


def call_instance(address, port, path='/', timeout=3.0):
    """真正调用一个实例（普通 HTTP 请求），返回响应体文本。

    知识点回指（课 1 客户端发现）：这一步体现「客户端发现」模式——
    调用方自己从注册中心拿到实例列表，自己选一个直连。Consul 不参与转发。
    """
    url = f'http://{address}:{port}{path}'
    with urllib.request.urlopen(url, timeout=timeout) as resp:
        return resp.read().decode('utf-8')


def discover_and_call(consul, name, path='/', dc=None):
    """组合动作：发现 → 取第一个健康实例 → 调用。

    简化版：取第一个（轮询/随机等负载均衡策略是另一个话题）。
    """
    instances = discover(consul, name, dc=dc)
    if not instances:
        raise RuntimeError(f'服务 {name} 无健康实例')
    inst = instances[0]
    return call_instance(inst['address'], inst['port'], path), inst


def watch_instances(consul, name, interval=2.0, rounds=5):
    """轮询观察实例列表变化（演示用，生产应改用阻塞查询）。

    返回每轮的实例 ID 列表，用于观察「注册/注销后多久被发现」。
    """
    seen = []
    for _ in range(rounds):
        ids = sorted(i['id'] for i in discover(consul, name))
        seen.append((time.strftime('%H:%M:%S'), ids))
        time.sleep(interval)
    return seen
