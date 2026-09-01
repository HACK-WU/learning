#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 9《生产实践与选型》备课实验公共库
纯标准库 RESP2 客户端（本机 Python 3.12 无第三方包），用法沿用课 8 惯例。
"""
import socket
import time
import threading
import random
import string


class Redis:
    """最小可用 RESP2 客户端（不支持 sub/pub、stream 阻塞等）。"""

    def __init__(self, host='127.0.0.1', port=7101, timeout=30):
        self.host = host
        self.port = port
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.buf = b''

    # ---------- RESP 编解码 ----------
    def _readline(self):
        while b'\r\n' not in self.buf:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError('connection closed')
            self.buf += chunk
        line, self.buf = self.buf.split(b'\r\n', 1)
        return line

    def _readn(self, n):
        while len(self.buf) < n + 2:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError('connection closed')
            self.buf += chunk
        data, self.buf = self.buf[:n], self.buf[n + 2:]
        return data

    def _encode(self, *args):
        out = [b'*%d\r\n' % len(args)]
        for a in args:
            if isinstance(a, bytes):
                b = a
            elif isinstance(a, (int, float)):
                b = str(a).encode()
            else:
                b = str(a).encode('utf-8')
            out.append(b'$%d\r\n%s\r\n' % (len(b), b))
        return b''.join(out)

    def _decode(self):
        line = self._readline()
        t, rest = line[:1], line[1:]
        if t == b'+':
            return rest.decode('utf-8', 'replace')
        if t == b'-':
            return RedisError(rest.decode('utf-8', 'replace'))
        if t == b':':
            return int(rest)
        if t == b'$':
            n = int(rest)
            if n == -1:
                return None
            return self._readn(n)
        if t == b'*':
            n = int(rest)
            if n == -1:
                return None
            return [self._decode() for _ in range(n)]
        raise ValueError('unknown reply type: %r' % t)

    # ---------- 命令 ----------
    def cmd(self, *args):
        self.sock.sendall(self._encode(*args))
        r = self._decode()
        if isinstance(r, RedisError):
            raise r
        return r

    def pipeline(self, commands):
        """批量发送，返回 [返回值或异常对象]"""
        payload = b''.join(self._encode(*c) for c in commands)
        self.sock.sendall(payload)
        out = []
        for _ in commands:
            r = self._decode()
            out.append(r)  # 保留 RedisError 对象，不抛
        return out

    def __getattr__(self, name):
        def f(*args):
            return self.cmd(name.upper(), *args)
        return f

    def close(self):
        try:
            self.sock.close()
        except Exception:
            pass


class RedisError(Exception):
    pass


def fmt_bytes(n):
    for unit in ('B', 'KB', 'MB', 'GB'):
        if abs(n) < 1024.0:
            return '%.2f %s' % (n, unit)
        n /= 1024.0
    return '%.2f TB' % n


def rand_str(n=10):
    return ''.join(random.choices(string.ascii_lowercase + string.digits, k=n))


def bench(fn, n, desc=''):
    """执行 n 次 fn，返回 (耗时秒, QPS, 错误数)"""
    t0 = time.time()
    err = 0
    for _ in range(n):
        try:
            fn()
        except Exception:
            err += 1
    dt = time.time() - t0
    qps = n / dt if dt > 0 else float('inf')
    return dt, qps, err


def section(title):
    print('\n' + '=' * 66)
    print('  ' + title)
    print('=' * 66)
