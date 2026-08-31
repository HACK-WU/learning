"""演示用业务服务：一个只依赖标准库的 HTTP 服务

它做的事：启动时把自己注册到 Consul（带 TTL 心跳），
每次被请求时返回当前从 KV 读到的配置值——用来直观展示「改配置不用重启服务」。
"""

import http.server
import json
import socketserver
import threading
import time

from config_center import ConfigCenter
from consul_client import Consul
from service_registry import ServiceRegistry

# ---- 配置区：改这里就能跑在不同端口 ----
SERVICE_NAME = 'demo-svc'
SERVICE_ID = 'demo-svc-1'
SERVICE_PORT = 18081
CONSUL_ADDR = 'http://127.0.0.1:8500'
KV_PREFIX = 'demo'
TTL = '15s'


class Handler(http.server.BaseHTTPRequestHandler):
    """处理业务请求。config_center 与 registry 通过闭包注入。"""

    config_center = None

    def do_GET(self):
        if self.path == '/health':
            body = json.dumps({'status': 'ok'}).encode()
        else:
            # 每次请求都读一次内存中的配置——配置由后台线程热更新
            payload = {
                'service': SERVICE_ID,
                'greeting': self.config_center.get('greeting', '(未配置)'),
                'feature_flag': self.config_center.get('feature_flag', 'off'),
                'served_at': time.strftime('%H:%M:%S'),
            }
            body = json.dumps(payload, ensure_ascii=False).encode()

        self.send_response(200)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        # 默认日志会打到 stderr，演示时静默，避免干扰主流程输出
        pass


def main():
    consul = Consul(CONSUL_ADDR)

    # 1) 配置中心：先拉一次全量，拿不到就退回本地快照
    cc = ConfigCenter(consul, KV_PREFIX, snapshot_path='config-snapshot.json')
    try:
        cc.load_all()
        print(f'[配置] 已从 Consul 加载：{cc.config}', flush=True)
    except Exception as e:
        snap = cc.load_snapshot()
        print(f'[配置] Consul 不可用（{e}），回落本地快照：{snap}', flush=True)

    # 2) 启动配置热更新线程
    stop_config = threading.Event()
    config_thread = threading.Thread(
        target=cc.watch_loop,
        args=(stop_config,),
            kwargs={'on_change': lambda cfg: print(f'[配置] 检测到变更并热更新：{cfg}', flush=True)},
            daemon=True)
    config_thread.start()

    # 3) 注册自己到 Consul，并启动心跳线程
    registry = ServiceRegistry(consul, SERVICE_ID, SERVICE_NAME, SERVICE_PORT,
                               tags=['demo'], ttl=TTL)
    registry.register()
    print(f'[注册] {SERVICE_ID} 已注册到 Consul（端口 {SERVICE_PORT}，TTL {TTL}）')

    stop_heartbeat = threading.Event()
    heartbeat_thread = threading.Thread(target=registry.keep_alive,
                                        args=(stop_heartbeat,), daemon=True)
    heartbeat_thread.start()

    # 4) 启动 HTTP 服务
    Handler.config_center = cc
    socketserver.TCPServer.allow_reuse_address = True
    try:
        with socketserver.TCPServer(('127.0.0.1', SERVICE_PORT), Handler) as httpd:
            print(f'[服务] 监听 http://127.0.0.1:{SERVICE_PORT}/  （Ctrl+C 退出）')
            httpd.serve_forever()
    except KeyboardInterrupt:
        print('\n[退出] 收到中断信号')
    finally:
        # 优雅退出：先停心跳，再从 Consul 注销（顺序很重要，注销后就不该再上报）
        stop_heartbeat.set()
        stop_config.set()
        registry.deregister()
        print('[退出] 已停止心跳并从 Consul 注销')


if __name__ == '__main__':
    main()
