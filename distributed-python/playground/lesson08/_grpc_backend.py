"""课 8 共用：极小的 gRPC 后端，只回自己的名字。

不依赖 protoc / .proto 文件——用 generic handler 手写方法，避免为了一个探针
引入代码生成链路。真实项目里当然该用 proto，这里只关心"请求落到哪个实例"。
"""
import json
import threading
import time

import grpc

SERVICE = "probe.Svc"


class Registry:
    """统计每个后端被打了多少次（同进程内，方便直接汇总）。"""

    def __init__(self):
        self.hits = {}
        self.lock = threading.Lock()

    def hit(self, sid):
        with self.lock:
            self.hits[sid] = self.hits.get(sid, 0) + 1

    def snapshot(self):
        with self.lock:
            return dict(self.hits)

    def reset(self):
        with self.lock:
            self.hits = {}


def make_server(sid, port, registry, work_ms=0, max_workers=8):
    """起一个只提供 /probe.Svc/Call 的 gRPC server，返回 (server, 实际端口)。"""
    server = grpc.server(
        __import__("concurrent.futures", fromlist=["ThreadPoolExecutor"]).ThreadPoolExecutor(
            max_workers=max_workers
        )
    )

    def call(request, context):
        registry.hit(sid)
        if work_ms:
            time.sleep(work_ms / 1000.0)
        return json.dumps({"sid": sid}).encode()

    handler = grpc.unary_unary_rpc_method_handler(
        call,
        request_deserializer=lambda b: b,
        response_serializer=lambda b: b,
    )
    server.add_generic_rpc_handlers(
        (grpc.method_handlers_generic_handler(SERVICE, {"Call": handler}),)
    )
    bound = server.add_insecure_port(f"127.0.0.1:{port}")
    server.start()
    return server, bound


def make_stub(channel):
    return channel.unary_unary("/probe.Svc/Call")


def target_of(ports):
    """gRPC 的多地址 target 语法：ipv4:host:port,host:port,..."""
    head, *rest = [f"127.0.0.1:{p}" for p in ports]
    return "ipv4:" + ",".join([head] + rest)


ROUND_ROBIN_OPTS = [
    (
        "grpc.service_config",
        json.dumps({"loadBalancingConfig": [{"round_robin": {}}]}),
    )
]
