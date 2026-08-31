"""配置中心模块：基于 KV + 阻塞查询的热更新配置

对应知识点：
- 课 6 KV 存储：KV 是 Consul 自带的键值存储，可当配置源
- 课 6 阻塞查询：长轮询 + X-Consul-Index，配置变更秒级推送到本地
- 课 6 局限：KV 无版本历史、无审计、单值 512KB 上限——重要配置仍需在外部留档
- 非功能约束（可维护性）：本地缓存 + 快照导出，保证 Consul 不可用时应用仍能读到上次的配置
"""

import base64
import json
import os
import time

from consul_client import ConsulError


class ConfigCenter:
    """带本地缓存与热更新的配置客户端。

    设计要点（对应非功能约束）：
    - 启动时全量拉取一次前缀下的配置，失败则回落到本地快照（Consul 挂了应用仍能起）
    - 后台线程用阻塞查询监听变更，变更即更新内存并落盘快照
    - 快照文件是「降级底线」，不是唯一数据源
    """

    def __init__(self, consul, prefix, snapshot_path=None):
        self.consul = consul
        self.prefix = prefix.rstrip('/')
        self.snapshot_path = snapshot_path
        self.config = {}
        # 阻塞查询的游标，必须是响应头 X-Consul-Index 的值（课 6 实测教训）
        self.index = None

    # ---------- 基础读写 ----------
    def _decode(self, item):
        """KV 的 Value 是 base64 编码的，需解码。"""
        raw = item.get('Value')
        if raw is None:
            return None
        return base64.b64decode(raw).decode('utf-8')

    def load_all(self):
        """全量拉取前缀下的所有键。recurse=true 表示前缀查询。"""
        result = self.consul.kv_get(self.prefix, recurse=True)
        self.index = result['index']
        config = {}
        for item in result['body'] or []:
            # 去掉前缀，得到 'greeting' 这样的短键
            key = item['Key'][len(self.prefix) + 1:]
            config[key] = self._decode(item)
        self.config = config
        self._save_snapshot()
        return config

    def get(self, key, default=None):
        return self.config.get(key, default)

    def set(self, key, value):
        self.consul.kv_put(f'{self.prefix}/{key}', value)

    # ---------- 热更新 ----------
    def wait_update(self, wait='60s'):
        """阻塞等待一次配置变更。返回 True 表示确有变更。

        知识点回指（课 6）：阻塞查询是「长轮询」——服务端在配置变化前挂起请求，
        变化后立刻返回，从而实现秒级推送而不需要客户端频繁轮询。

        超时无需调用方传入：下面按 wait 自动计算（wait + 15 秒余量）。
        """
        # 超时必须大于 wait：wait=60s 时给 75 秒，留出网络往返余量
        wait_seconds = int(wait.rstrip('s')) if isinstance(wait, str) else 60
        try:
            result = self.consul.kv_get(self.prefix, index=self.index, wait=wait,
                                        recurse=True, timeout=wait_seconds + 15)
        except ConsulError:
            # 500 常见于集群 quorum 丢失，返回 False 让调用方重试
            return False
        except Exception:
            # 超时 / 网络中断也算「本次没拿到变更」，返回 False 让循环继续
            return False

        new_index = result['index']
        # index 没变 = 本次是超时返回（阻塞查询的正常行为），不是变更
        if new_index == self.index:
            return False

        self.index = new_index
        config = {}
        for item in result['body'] or []:
            key = item['Key'][len(self.prefix) + 1:]
            config[key] = self._decode(item)
        self.config = config
        self._save_snapshot()
        return True

    def watch_loop(self, stop_event, on_change=None, wait='60s'):
        """后台热更新循环，直到 stop_event 被置位。"""
        while not stop_event.is_set():
            changed = self.wait_update(wait=wait)
            if changed and on_change:
                on_change(self.config)

    # ---------- 快照：Consul 不可用时的降级底线 ----------
    def _save_snapshot(self):
        if not self.snapshot_path:
            return
        payload = {'saved_at': time.strftime('%Y-%m-%d %H:%M:%S'), 'config': self.config}
        # 先写临时文件再替换，避免写到一半进程崩溃留下损坏的快照
        tmp = self.snapshot_path + '.tmp'
        with open(tmp, 'w', encoding='utf-8') as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
        os.replace(tmp, self.snapshot_path)

    def load_snapshot(self):
        """从本地快照恢复配置。Consul 不可用时的降级路径。"""
        if not self.snapshot_path or not os.path.exists(self.snapshot_path):
            return None
        with open(self.snapshot_path, encoding='utf-8') as f:
            payload = json.load(f)
        self.config = payload.get('config', {})
        return payload

    def export(self, path):
        """导出当前配置到文件（对应课 6 讲的 KV 无版本历史，需外部留档）。"""
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(self.config, f, ensure_ascii=False, indent=2)
        return path
