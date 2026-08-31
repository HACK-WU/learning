"""
动态配置 + 本地缓存兜底（正确版）
对应知识点：阶段2 课5（watch 一次性 / 断连期收不到通知 / 重连要全量重同步）
          阶段4 课12 决策3（配置是「基础设施元数据」还是「业务治理对象」）

★ 三条铁律：
  1) watch 是一次性的 —— 回调里必须重新注册（kazoo 的 DataWatch 会自动重注册，手写必须自己来）
  2) 断连期间收不到任何 watch —— 重连后要「全量重新读一次」，不能只信增量
  3) 本地缓存兜底 —— 配置中心挂了，服务要能靠上次的配置启动（课12 场景B 的硬要求）
"""
import json
import os
import threading
from kazoo.client import KazooClient
from kazoo.protocol.states import KazooState

ZK_HOSTS = "127.0.0.1:2181"
CONFIG_PATH = "/scheduler/config/task_switch"
LOCAL_CACHE = ".config_cache.json"      # 本地缓存文件（演示用；生产放 /var/lib/ 或配置目录）

# 默认配置：连不上 ZK 且无缓存时使用（保证极端情况也能起来）
DEFAULT_CONFIG = {
    "enable_reconcile": True,
    "enable_stock_deduct": True,
    "max_retry": 3,
    "threshold": 100,
}


class ConfigClient:
    """
    配置客户端：ZK watch + 本地缓存兜底。
    """

    def __init__(self, zk: KazooClient):
        self.zk = zk
        self.config = dict(DEFAULT_CONFIG)
        self._lock = threading.Lock()
        self._load_local_cache()          # 启动时先加载本地缓存（ZK 挂了也能起）
        self._state = None

    # --------------------------------------------------------------
    # 本地缓存：兜底用
    # --------------------------------------------------------------
    def _load_local_cache(self):
        if os.path.exists(LOCAL_CACHE):
            try:
                with open(LOCAL_CACHE, "r", encoding="utf-8") as f:
                    self.config.update(json.load(f))
                print(f"   从本地缓存加载配置：{self.config}")
            except Exception as e:
                print(f"   ⚠️ 本地缓存损坏，用默认值：{e}")
        else:
            print(f"   无本地缓存，用默认配置：{self.config}")

    def _save_local_cache(self):
        try:
            with open(LOCAL_CACHE, "w", encoding="utf-8") as f:
                json.dump(self.config, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"   ⚠️ 写本地缓存失败（不影响运行）：{e}")

    # --------------------------------------------------------------
    # 全量重读：断连重连后必须调用（★ 铁律 2）
    # --------------------------------------------------------------
    def _full_resync(self):
        """从 ZK 全量重新读一次配置 —— 断连期间的变更靠这次补齐"""
        try:
            data, stat = self.zk.get(CONFIG_PATH)
            new_cfg = json.loads(data.decode())
            with self._lock:
                if new_cfg != self.config:
                    print(f"   🔄 全量重同步，配置已更新：{new_cfg}")
                    self.config.update(new_cfg)
                    self._save_local_cache()
                else:
                    print("   ✓ 全量重同步，配置无变化")
        except Exception as e:
            print(f"   ⚠️ 全量重同步失败（沿用本地缓存）：{e}")

    # --------------------------------------------------------------
    # 状态监听：断连/重连的处理（★ 铁律 2 的触发点）
    # --------------------------------------------------------------
    def _state_listener(self, state):
        print(f"   [连接状态] {state}")
        if state == KazooState.CONNECTED:
            # 重连后：全量重读（断连期间的 watch 全丢了）
            self._full_resync()
        elif state == KazooState.SUSPENDED:
            # 与 ZK 断开但会话未过期 —— 此时不能确定配置是否变了
            print("   ⚠️ SUSPENDED：期间收不到任何 watch，恢复后必须全量重读")
        elif state == KazooState.LOST:
            # 会话已过期 —— 临时节点没了（Worker 注册失效），锁也需重新获取
            print("   🔴 LOST：会话已过期！临时节点被清除，持有的锁需重新获取")

    # --------------------------------------------------------------
    # 启动：注册 watch + 状态监听
    # --------------------------------------------------------------
    def start(self):
        self.zk.add_listener(self._state_listener)     # 状态回调（★ 铁律 2）
        self.zk.ensure_path("/scheduler/config")

        # 初始化：若配置节点不存在，写入默认值
        if not self.zk.exists(CONFIG_PATH):
            self.zk.create(CONFIG_PATH, json.dumps(DEFAULT_CONFIG).encode(), makepath=True)

        # DataWatch：kazoo 会自动重注册（★ 铁律 1 由框架保证）
        # ⚠️ 如果你手写 zk.get(path, watch=...)，回调里必须自己再调用一次 get(watch=...)
        @self.zk.DataWatch(CONFIG_PATH)
        def _on_change(data, stat, event=None):
            if data is None:
                return          # 节点被删除，忽略
            try:
                new_cfg = json.loads(data.decode())
                with self._lock:
                    if new_cfg != self.config:
                        print(f"   📥 配置变更（watch 触发）：{new_cfg}")
                        self.config.update(new_cfg)
                        self._save_local_cache()
            except Exception as e:
                print(f"   ⚠️ 解析配置失败（沿用旧值）：{e}")

        # 首次全量读一次（DataWatch 也会立即回调一次，这里确保顺序）
        self._full_resync()

    def get(self, key, default=None):
        with self._lock:
            return self.config.get(key, default)


# ---------------------------------------------------------------------------
# 演示
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    zk = KazooClient(hosts=ZK_HOSTS, timeout=10.0)
    zk.start()

    cfg = ConfigClient(zk)
    cfg.start()
    print(f"\n当前配置：enable_stock_deduct={cfg.get('enable_stock_deduct')}, threshold={cfg.get('threshold')}")

    print("\n-- 在另一个终端执行：")
    print(f'   zkCli.sh set {CONFIG_PATH} \'{{"enable_reconcile":false,"enable_stock_deduct":true,"max_retry":5,"threshold":999}}\'')
    print("   观察这里会打印「配置变更（watch 触发）」，且第二次改也能收到（证明 watch 被重注册）--\n")

    try:
        for i in range(60):
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        zk.stop()
        zk.close()
