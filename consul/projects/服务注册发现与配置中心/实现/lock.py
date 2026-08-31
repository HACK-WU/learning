"""分布式锁与领导者选举（基于 session + KV acquire）

对应知识点：
- 课 6 会话（session）：带 TTL 的租约凭证，会话失效则它持有的锁自动释放
- 课 6 分布式锁：用 KV 键的 acquire 语义实现互斥
- 课 6 局限：Consul 的锁是「 Advisory（建议性）」锁——
  它只能约束「遵守规则的参与者」，不遵守的应用仍可直接改 KV 键，绕过锁。
"""

import threading
import time

from consul_client import ConsulError


class LeaderElection:
    """用 Consul KV 锁实现的领导者选举。

    用法：
        e = LeaderElection(consul, 'locks/leader', 'worker-1')
        if e.try_acquire():
            # 我是 leader，干活
            e.keep_alive_until(stop_event)
    """

    def __init__(self, consul, lock_key, name, ttl='15s'):
        self.consul = consul
        self.lock_key = lock_key
        self.name = name
        self.ttl = ttl
        self._ttl_seconds = int(ttl.rstrip('s'))
        self.session_id = None
        self._acquired = False

    def _ensure_session(self):
        """会话只需创建一次，之后靠续约维持。"""
        if self.session_id is None:
            self.session_id = self.consul.session_create(
                name=f'lock-{self.name}', ttl=self.ttl)['body']['ID']
        return self.session_id

    def try_acquire(self):
        """尝试抢占锁。返回 True 表示抢到。

        知识点回指（课 6）：acquire 用 KV 的 CAS 语义实现——
        只有锁键未被持有（或持有会话已失效）时才能成功。
        """
        self._ensure_session()
        try:
            result = self.consul.kv_acquire(self.lock_key, self.session_id, value=self.name)
        except ConsulError as e:
            if e.status == 500:
                return False
            raise
        # body 为 true 表示抢到，false 表示已被别人持有
        self._acquired = result['body'] is True
        return self._acquired

    def is_leader(self):
        """确认自己当前是否仍持有锁（可能因 TTL 过期而失去）。"""
        if not self._acquired:
            return False
        try:
            result = self.consul.kv_get(self.lock_key)
        except ConsulError as e:
            if e.status == 404:
                self._acquired = False
                return False
            raise
        items = result['body'] or []
        if not items:
            self._acquired = False
            return False
        # Session 字段为空表示无人持有；等于自己的会话 ID 表示自己持有
        holder = items[0].get('Session')
        self._acquired = (holder == self.session_id)
        return self._acquired

    def keep_alive_until(self, stop_event, on_lost=None):
        """持续续约会话维持领导权，直到 stop_event 被置位。

        知识点回指（课 6）：续约周期取 TTL 的 1/3——
        即使某次续约失败，还有两次重试机会才到期。
        """
        interval = max(self._ttl_seconds / 3, 1)
        while not stop_event.is_set():
            try:
                self.consul.session_renew(self.session_id)
            except ConsulError:
                # 续约失败：可能网络抖动或会话已过期
                if not self.is_leader():
                    if on_lost:
                        on_lost()
                    return False
            # 顺便确认领导权是否还在（TTL 过期会被别人抢走）
            if not self.is_leader():
                if on_lost:
                    on_lost()
                return False
            stop_event.wait(interval)
        return True

    def release(self):
        """主动释放锁并销毁会话。"""
        if self.session_id and self._acquired:
            try:
                self.consul.kv_release(self.lock_key, self.session_id)
            except ConsulError:
                pass
        if self.session_id:
            try:
                self.consul.session_destroy(self.session_id)
            except ConsulError:
                pass
        self.session_id = None
        self._acquired = False

    def __enter__(self):
        self.try_acquire()
        return self

    def __exit__(self, *exc):
        self.release()
        return False
