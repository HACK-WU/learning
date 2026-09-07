#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把应用日志【直接推给 Loki】，绕开 Promtail 的文件采集。

为什么不用 Promtail（这是本项目踩到的真实坑）：
  WSL 的 fs.inotify.max_user_instances 只有 128（宿主内核参数），
  Promtail 的文件发现要为每个被采集目录建一个 inotify 实例，
  在 WSL 下直接报 `too many open files`，加 --privileged 也无效
  （inotify 限制来自宿主内核命名空间，不是容器能力）。

直推的代价（写进设计决策）：
  - 应用与 Loki 耦合（应用要知道 Loki 地址）
  - 应用挂了日志就丢（没有落盘缓冲，Promtail 方案有 positions 断点续传）
  - 没有背压，Loki 卡住会拖慢业务线程

所以【生产仍应选 Promtail】，本项目在 WSL 上用它只是为了跑通下钻链路。
"""
import json
import os
import queue
import threading
import time
import urllib.request

LOKI_URL = os.getenv("LOKI_URL", "http://grafana-loki:3100/loki/api/v1/push")
BATCH_MAX = int(os.getenv("LOKI_BATCH_MAX", "50"))       # 攒够几条发一次
FLUSH_SEC = float(os.getenv("LOKI_FLUSH_SEC", "2.0"))    # 或攒满几秒发一次

_q = queue.Queue(maxsize=10000)
_stop = threading.Event()

# Loki 标签必须低基数：service / level / route
# trace_id 是高基数（每条都不同），绝不能进标签，只能进日志行内容
_LABELS = {}


def set_labels(service, route=""):
    _LABELS["service"] = service
    _LABELS["job"] = "shop"
    if route:
        _LABELS["route"] = route


def _push(batch):
    """把一个批次的日志推给 Loki。batch: [(ts_ns, line), ...]"""
    if not batch:
        return
    streams = {}
    for ts_ns, line in batch:
        # 标签组合决定 stream key
        key = json.dumps(_LABELS, sort_keys=True)
        streams.setdefault(key, {"stream": dict(_LABELS), "values": []})
        streams[key]["values"].append([str(ts_ns), line])
    payload = json.dumps({"streams": list(streams.values())}).encode()
    req = urllib.request.Request(
        LOKI_URL, data=payload,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            r.read()
    except Exception as e:  # noqa: BLE001
        # 关键点：推送失败不能影响主流程，只丢弃并计数
        print(f"[loki] push failed: {e}", flush=True)


def _worker():
    batch = []
    last = time.time()
    while not _stop.is_set():
        try:
            ts_ns, line = _q.get(timeout=0.5)
            batch.append((ts_ns, line))
        except queue.Empty:
            pass
        if len(batch) >= BATCH_MAX or (batch and time.time() - last >= FLUSH_SEC):
            _push(batch)
            batch = []
            last = time.time()
    if batch:
        _push(batch)


def start():
    set_labels(os.getenv("SERVICE_NAME", "shop-api"))
    threading.Thread(target=_worker, daemon=True).start()


def emit(line: str):
    """把一行日志放进队列（非阻塞，队列满则丢弃）。"""
    ts_ns = time.time_ns()
    try:
        _q.put_nowait((ts_ns, line))
    except queue.Full:
        print("[loki] queue full, drop", flush=True)
