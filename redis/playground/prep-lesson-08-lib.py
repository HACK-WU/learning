#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 8 备课实验基座：零依赖 Redis 客户端（仅用 Python 标准库 socket 实现 RESP）。

为什么不用 redis-py：本机 WSL 未安装（ModuleNotFoundError: No module named 'redis'），
且与前序课程保持一致（课 7 的 CRC16 也是手写实现）。

用法：
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from prep_lesson_08_lib import Redis, FakeDB
"""
import os
import socket
import time
import threading


class RedisError(Exception):
    pass


class Redis:
    """极简 RESP2 客户端。每个线程请用独立实例（socket 非线程安全）。"""

    def __init__(self, host='127.0.0.1', port=7101, timeout=10):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.buf = b''

    # ---------- 协议编解码 ----------
    def _encode(self, *args):
        out = b'*%d\r\n' % len(args)
        for a in args:
            if isinstance(a, str):
                a = a.encode('utf-8')
            elif isinstance(a, (int, float)):
                a = str(a).encode('utf-8')
            elif a is None:
                a = b''
            out += b'$%d\r\n%s\r\n' % (len(a), a)
        return out

    def _readline(self):
        while b'\r\n' not in self.buf:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise RedisError('connection closed')
            self.buf += chunk
        line, self.buf = self.buf.split(b'\r\n', 1)
        return line

    def _readn(self, n):
        while len(self.buf) < n + 2:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise RedisError('connection closed')
            self.buf += chunk
        data, self.buf = self.buf[:n], self.buf[n + 2:]
        return data

    def _read_reply(self):
        line = self._readline()
        if not line:
            raise RedisError('empty reply')
        tag, body = line[:1], line[1:]
        if tag == b'+':
            return body.decode('utf-8', 'replace')
        if tag == b'-':
            raise RedisError(body.decode('utf-8', 'replace'))
        if tag == b':':
            return int(body)
        if tag == b'$':
            n = int(body)
            if n == -1:
                return None
            return self._readn(n).decode('utf-8', 'replace')
        if tag == b'*':
            n = int(body)
            if n == -1:
                return None
            return [self._read_reply() for _ in range(n)]
        raise RedisError('unknown reply tag %r' % tag)

    def cmd(self, *args):
        self.sock.sendall(self._encode(*args))
        return self._read_reply()

    # ---------- 便捷方法 ----------
    def get(self, k):
        return self.cmd('GET', k)

    def set(self, k, v, ex=None, nx=False):
        args = ['SET', k, v]
        if ex is not None:
            args += ['EX', int(ex)]
        if nx:
            args += ['NX']
        return self.cmd(*args)

    def delete(self, *keys):
        return self.cmd('DEL', *keys)

    def exists(self, *keys):
        return self.cmd('EXISTS', *keys)

    def flushdb(self):
        return self.cmd('FLUSHDB')

    def dbsize(self):
        return self.cmd('DBSIZE')

    def info(self, section='default'):
        return self.cmd('INFO', section)

    def config_set(self, k, v):
        return self.cmd('CONFIG', 'SET', k, v)

    def config_get(self, k):
        return self.cmd('CONFIG', 'GET', k)

    def close(self):
        try:
            self.sock.close()
        except Exception:
            pass

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()


class FakeDB:
    """
    模拟后端数据库：带查询计数与可配置延迟，用于统计"打到数据库的次数"。

    这是本课三个故障场景的核心度量工具——穿透/击穿/雪崩的危害全部体现为
    DB 查询次数与瞬时并发，而不是 Redis 的 QPS。
    """

    def __init__(self, data=None, latency=0.0):
        self.data = data if data is not None else {}
        self.latency = latency      # 单次查询耗时（秒）
        self.queries = 0            # 查询次数
        self.max_concurrent = 0     # 瞬时最大并发
        self._cur = 0
        self._lock = threading.Lock()

    def get(self, key):
        with self._lock:
            self._cur += 1
            self.queries += 1
            if self._cur > self.max_concurrent:
                self.max_concurrent = self._cur
        try:
            if self.latency:
                time.sleep(self.latency)
            return self.data.get(key)
        finally:
            with self._lock:
                self._cur -= 1

    def set(self, key, value):
        with self._lock:
            self._cur += 1
            self.queries += 1
        try:
            if self.latency:
                time.sleep(self.latency)
            self.data[key] = value
            return value
        finally:
            with self._lock:
                self._cur -= 1

    def reset_stats(self):
        with self._lock:
            self.queries = 0
            self.max_concurrent = 0


def ensure_server(port=7101, extra_args=None):
    """确认专用实例在跑，没有就拉起一个（默认无持久化，目录 /tmp/redis-l08）。"""
    try:
        with Redis(port=port, timeout=2) as r:
            r.cmd('PING')
        return True
    except Exception:
        return False


def start_server(port=7101, extra_args=None):
    """拉起专用实例。"""
    d = '/tmp/redis-l08'
    os.makedirs(d, exist_ok=True)
    args = [
        'redis-server',
        '--port', str(port),
        '--save', '',
        '--appendonly', 'no',
        '--dir', d,
        '--dbfilename', 'l08.rdb',
        '--daemonize', 'yes',
        '--logfile', '%s/%d.log' % (d, port),
    ]
    if extra_args:
        args += extra_args
    rc = os.system(' '.join(args))
    # 等待就绪
    for _ in range(50):
        time.sleep(0.1)
        if ensure_server(port):
            return True
    return False


def stop_server(port=7101):
    try:
        with Redis(port=port, timeout=2) as r:
            try:
                r.cmd('SHUTDOWN', 'NOSAVE')
            except Exception:
                pass
    except Exception:
        pass
