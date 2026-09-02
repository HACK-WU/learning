#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
结课实战项目：电商大促数据层 · 公共库
纯标准库 RESP2 客户端（本机 Python 3.12 无第三方包），沿用课程既有惯例。

对应知识点：
  - 阶段1·课2 key 设计：统一 {业务}:{实体}:{id} 命名
  - 阶段4·课9 安全基线：用最小权限账号连接，绝不裸奔
"""
import socket
import time
import random
import string
import threading


class RedisError(Exception):
    pass


class Redis:
    """最小可用 RESP2 客户端（不支持 sub/pub、stream 阻塞等）"""

    def __init__(self, host='127.0.0.1', port=7201,
                 username=None, password=None, timeout=30):
        self.host = host
        self.port = port
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.buf = b''
        # 安全基线：连接即认证（阶段4·课9）
        if username is not None:
            self.cmd('AUTH', username, password)

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
        """批量发送，返回 [返回值或异常对象]（不抛异常，便于统计失败数）"""
        payload = b''.join(self._encode(*c) for c in commands)
        self.sock.sendall(payload)
        out = []
        for _ in commands:
            out.append(self._decode())
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


# ---------- 项目统一连接入口（安全基线集中在此） ----------
def conn_master():
    """主库连接（读写）—— 用最小权限的 appuser"""
    return Redis(port=7201, username='appuser', password='AppPass123!')


def conn_replica():
    """从库连接（只读）—— 演示读写分离"""
    return Redis(port=7202)


def conn_readonly():
    """主库只读账号连接 —— 演示 ACL 边界"""
    return Redis(port=7201, username='readonly', password='ReadOnly123!')


def conn_insecure():
    """反例实例连接（出厂默认，无认证）—— 仅用于反例对照演示"""
    return Redis(port=7203)


# ---------- 工具函数 ----------
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
    print('\n' + '=' * 70)
    print('  ' + title)
    print('=' * 70)


def subsect(title):
    print('\n--- ' + title + ' ---')
