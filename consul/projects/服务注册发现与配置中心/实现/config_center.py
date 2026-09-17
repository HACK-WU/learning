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
import urllib.error

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
        """全量拉取前缀下的所有键。recurse=true 表示前缀查询。

        2026-09-17 修复：前缀下无任何键时，Consul 对不存在的 key 返回 **404**
        （课 6 已记录的已知行为）。原实现未处理，导致**首次运行直接崩溃**——
        空前缀是首次启动的常态，不是异常，应视为"空配置"。

        2026-09-17 二次修复（吸收实战篇 C 实测）：404 不等于"没配置"。
        实战篇 C 的 21 项权限矩阵实测发现，**递归查询（?recurse=true）在
        token 无权限时同样返回 404**，而不是 403。于是"没权限"和"没配置"
        在递归读上表现完全一致——原实现会把"没权限"当成"空配置"静默吞掉，
        配置热更新从此不再生效，且没有任何报错。

        归因办法（实战篇 C 补充实测确认）：
          - 无权限时，**单键读恒返回 403**（无论键是否存在）
          - 有权限且键不存在时，单键读才返回 404
        因此 404 之后补一次单键读探针：拿到 403 即可断定是权限问题。
        """
        try:
            result = self.consul.kv_get(self.prefix, recurse=True)
        except ConsulError as e:
            if getattr(e, 'status', None) == 404:
                # 递归读 404：既可能是"前缀真的空"，也可能是"无权限"。
                # 用单键读做归因，避免静默吞掉权限问题（实战篇 C 实测）。
                self._check_permission_on_404()
                # 前缀不存在 = 还没有任何配置，属正常初始状态。
                #
                # ⚠️ 已知限制（2026-09-17 实测确认，未修复，如实记录）：
                # 空前缀时 **拿不到起始 index**——对空前缀的查询本身就是 404，
                # 而 404 响应头里的 X-Consul-Index 在 _request 中被丢弃
                # （ConsulError 只保留 status 与 body）。
                # 于是 wait_update() 会以 index=None 发起阻塞查询，
                # 而缺少 ?index 参数时 Consul **立即返回**（实测 2ms），
                # 导致首次运行后的第一次配置变更被错过。
                #
                # 曾尝试的修复：用 _fetch_current_index() 取前缀当前 index。
                # 实测证明无效——空前缀查询返回 404，该方法同样拿不到值。
                # 已按诚实纪律撤回，不留假装修好的代码。
                #
                # 正确的用法：调用方应对 wait_update 做**循环重试**而非只调一次
                # （见 main.py 第 4 步），这样即使某次立即返回也能重新挂起。
                self.index = None
                self.config = {}
                self._save_snapshot()
                return {}
            if getattr(e, 'status', None) == 403:
                raise PermissionError(
                    f'无权限读取配置前缀 "{self.prefix}"：Consul 返回 403。'
                    f'请检查 token 的 key_prefix 读权限（课 8 / 实战篇 C）'
                ) from None
            raise
        self.index = result['index']
        config = {}
        for item in result['body'] or []:
            # 去掉前缀，得到 'greeting' 这样的短键
            key = item['Key'][len(self.prefix) + 1:]
            config[key] = self._decode(item)
        self.config = config
        self._save_snapshot()
        return config

    def _probe_key_raw(self, key: str) -> int:
        """对单个 key 发一次**不带任何查询参数**的裸 KV 请求，返回 HTTP 状态码。

        为什么不复用 kv_get()：kv_get 默认会拼上 ?recurse=false，
        而 2026-09-17 补充实测确认——**带了查询参数之后，无权限时返回的是
        404 而不是 403**，探针会失效，归因逻辑形同虚设。
        只有裸路径（/v1/kv/<key>，无 query string）才保留 403 语义。
        """
        import urllib.request
        from consul_client import ConsulError
        req = urllib.request.Request(f'{self.consul.addr}/v1/kv/{key}', method='GET')
        token = getattr(self.consul, 'token', None)
        if token:
            req.add_header('X-Consul-Token', token)
        try:
            with urllib.request.urlopen(req, timeout=self.consul.timeout) as resp:
                return resp.status
        except urllib.error.HTTPError as e:
            return e.code
        except Exception:
            return -1

    def _check_permission_on_404(self):
        """递归读拿到 404 时，判断到底是"没配置"还是"没权限"。

        原理（实战篇 C 实测 + 2026-09-17 补充实测，default_policy=deny）：

                                    无权限      有权限+键不存在
            递归读 ?recurse=true     404          404
            单键读（裸路径）          403          404
            单键读 ?recurse=false    404          404   ← 带了参数就分辨不出

        即：**只有不带任何查询参数的单键读，才能把"无权限"从 404 里揪出来。**
        之所以必须实测才知道，是因为凭直觉会写成"复用 kv_get 再传
        recurse=False"——那样写探针永远返回 404，等于没写。
        """
        probe = f'{self.prefix}/__probe__'
        code = self._probe_key_raw(probe)
        if code == 403:
            # 裸路径单键读 403 = 无权限，与键是否存在无关（实战篇 C 实测）
            raise PermissionError(
                f'无权限读取配置前缀 "{self.prefix}"：递归读返回 404，'
                f'但裸路径单键读探针返回 403 —— 这是【权限问题】而非"配置为空"。'
                f'（实战篇 C 实测：递归读越权返回 404 而非 403，'
                f'会把 ACL 问题伪装成空配置，导致配置热更新静默失效）'
                f'请检查 token 的 key_prefix 读权限。'
            )
        # 404 = 探针键不存在且前缀可读，404 确实是空配置；
        # -1（网络异常等）无法归因，按空配置处理——不编造结论
        return

    # 注：曾在此处提供 _fetch_current_index() 用于空前缀时取起始 index，
    # 实测证明无效（空前缀查询返回 404，拿不到 X-Consul-Index），
    # 已按诚实纪律移除，相关限制记录在 load_all 的 404 分支里。

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
