#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
诊断层：把课 9 的性能诊断能力做成项目自带的可观测工具

覆盖知识点：
  阶段4·课9 · 性能诊断四层模型  → 整体指标 → 命令维度 → 单条命令 → 具体 key
  阶段4·课9 · 慢查询日志        → SLOWLOG 只记录命令执行耗时，不含网络传输
  阶段4·课9 · 大 key 诊断       → MEMORY USAGE + 类型感知的扫描
  阶段4·课9 · 热 key 识别       → OBJECT FREQ（需 maxmemory-policy 为 LFU 系列）
  阶段4·课9 · 内存诊断          → INFO memory + 淘汰统计
  阶段4·课1 · 关键补充          → SCAN 代替 KEYS（KEYS 会阻塞，本项目 appuser 已禁用）

为什么不用 KEYS？
  KEYS 一次性遍历全部 key 并构建返回值，百万 key 时会让 Redis 停顿数百毫秒，
  期间所有其他请求排队。SCAN 分批游标遍历，每次只取一小批，不阻塞。
  本项目的 appuser 账号已通过 ACL 禁用 KEYS，从权限层面杜绝误用。
"""

import time
from redislib import RedisError


def _dec(b):
    return b.decode() if isinstance(b, bytes) else b


def _s(v):
    """INFO 等命令返回可能是 bytes，统一转成 str 便于解析"""
    return v.decode() if isinstance(v, bytes) else v


class Diagnostics:
    def __init__(self, r):
        self.r = r

    # ---------- 第一层：整体指标 ----------
    def overview(self):
        """整体健康快照"""
        info = _s(self.r.cmd('INFO', 'stats'))
        mem = _s(self.r.cmd('INFO', 'memory'))
        srv = _s(self.r.cmd('INFO', 'server'))
        out = {}

        def pick(blob, keys):
            d = {}
            for line in blob.splitlines():
                if ':' in line:
                    k, v = line.split(':', 1)
                    if k in keys:
                        d[k] = v
            return d

        out.update(pick(srv, {'redis_version', 'uptime_in_seconds'}))
        out.update(pick(info, {
            'total_commands_processed', 'instantaneous_ops_per_sec',
            'keyspace_hits', 'keyspace_misses',
            'expired_keys', 'evicted_keys',
            'rejected_connections', 'sync_full', 'sync_partial_ok',
        }))
        out.update(pick(mem, {
            'used_memory', 'used_memory_human', 'used_memory_peak_human',
            'maxmemory', 'maxmemory_policy', 'mem_fragmentation_ratio',
        }))

        hits = int(out.get('keyspace_hits', 0))
        miss = int(out.get('keyspace_misses', 0))
        total = hits + miss
        out['hit_rate'] = (hits / total * 100) if total else 0.0
        return out

    def print_overview(self):
        o = self.overview()
        print('  Redis 版本        : %s' % o.get('redis_version'))
        print('  运行时间          : %s 秒' % o.get('uptime_in_seconds'))
        print('  当前 OPS          : %s' % o.get('instantaneous_ops_per_sec'))
        print('  内存用量          : %s (峰值 %s)' % (
            o.get('used_memory_human'), o.get('used_memory_peak_human')))
        print('  淘汰策略          : %s' % o.get('maxmemory_policy'))
        print('  内存碎片率        : %s' % o.get('mem_fragmentation_ratio'))
        print('  >>> 缓存命中率    : %.2f%%  (hits=%s, misses=%s)' % (
            o['hit_rate'], o.get('keyspace_hits'), o.get('keyspace_misses')))
        print('  已淘汰 key 数     : %s' % o.get('evicted_keys'))
        print('  已过期 key 数     : %s' % o.get('expired_keys'))

    # ---------- 第二层：命令维度 ----------
    def command_stats(self):
        """各命令的调用次数与累计耗时（O(1) 采样，无额外开销）"""
        raw = _s(self.r.cmd('INFO', 'commandstats'))
        rows = []
        for line in raw.splitlines():
            if not line.startswith('cmdstat_'):
                continue
            k, v = line.split(':', 1)
            d = {}
            for part in v.split(','):
                if '=' in part:
                    a, b = part.split('=', 1)
                    d[a] = b
            rows.append({
                'cmd': k[len('cmdstat_'):],
                'calls': int(d.get('calls', 0)),
                'usec': float(d.get('usec', 0)),
                'usec_per_call': float(d.get('usec_per_call', 0)),
                'rejected': int(d.get('rejected_calls', 0)),
                'failed': int(d.get('failed_calls', 0)),
            })
        rows.sort(key=lambda x: -x['usec'])
        return rows

    def print_command_stats(self, top=8):
        rows = self.command_stats()
        print('  %-14s %10s %12s %12s' % ('命令', '调用次数', '累计耗时us', '平均us/次'))
        print('  ' + '-' * 52)
        for r in rows[:top]:
            print('  %-14s %10d %12.0f %12.2f' % (
                r['cmd'], r['calls'], r['usec'], r['usec_per_call']))

    # ---------- 第三层：慢查询 ----------
    def slowlog(self, n=10):
        raw = self.r.cmd('SLOWLOG', 'GET', n)
        out = []
        for item in raw:
            # [id, timestamp, duration_us, command_array, client_addr, client_name]
            out.append({
                'id': item[0],
                'ts': item[1],
                'duration_us': item[2],
                'cmd': ' '.join(_dec(x) for x in item[3]),
                'addr': _dec(item[4]) if len(item) > 4 else '',
            })
        return out

    def print_slowlog(self, n=5):
        logs = self.slowlog(n)
        if not logs:
            print('  （无慢查询记录 —— 注意：慢查询为空不代表没问题，见下方说明）')
            return
        for l in logs:
            print('  耗时 %8.2f ms | %s' % (l['duration_us'] / 1000.0, l['cmd'][:70]))

    def slowlog_threshold(self):
        return int(self.r.cmd('CONFIG', 'GET', 'slowlog-log-slower-than')[1])

    # ---------- 第四层：具体 key ----------
    def scan_all(self, pattern='*', count=500, max_rounds=10000):
        """
        用 SCAN 安全遍历全部 key（替代 KEYS）。

        ⚠️ 两个必须注意的点（本项目实测踩坑）：
        1) SCAN 返回的游标是 **bytes**（如 b'0'），不是整数。
           直接写 `if cur == 0` 永远不成立（b'0' != 0），循环不会退出，
           会把 SCAN 打到几百万次 —— 诊断工具反而把实例压垮了。
           必须先解码再比较。
        2) SCAN 不保证一次遍历完，必须循环到游标回 0；
           且过程中 key 可能增删，结果只代表某个时间点的快照。

        max_rounds 是保险丝，防止游标异常时无限循环。
        """
        cur = 0
        keys = []
        rounds = 0
        while rounds < max_rounds:
            raw_cur, batch = self.r.cmd('SCAN', cur, 'MATCH', pattern,
                                        'COUNT', count)
            rounds += 1
            keys.extend(batch)
            # 游标是 bytes，必须解码后与字符串 '0' 比较
            cur_str = raw_cur.decode() if isinstance(raw_cur, bytes) else str(raw_cur)
            if cur_str == '0':      # 游标回 0 才表示遍历结束
                break
            cur = raw_cur
        return keys

    def big_keys(self, top=10, threshold_bytes=10240, sample=2000):
        """
        扫描大 key。生产环境优先用 `redis-cli --bigkeys`（更低开销），
        这里用 SCAN + MEMORY USAGE 是为了能按类型细分并给出结构化结果。

        ⚠️ sample 限制扫描数量：全量 SCAN 在 key 多时会产生海量命令
        （本项目实测：一次全量扫描触发 158 万次 SCAN 调用，反而把实例压慢）。
        诊断工具不能比业务本身更耗资源。
        """
        keys = self.scan_all()[:sample]
        sized = []
        for k in keys:
            k = _dec(k)
            try:
                size = self.r.cmd('MEMORY', 'USAGE', k)
                if size and size >= threshold_bytes:
                    t = self.r.cmd('TYPE', k)
                    sized.append((k, size, _dec(t)))
            except RedisError:
                continue
        sized.sort(key=lambda x: -x[1])
        return sized[:top]

    def print_big_keys(self, top=8):
        bk = self.big_keys(top=top)
        if not bk:
            print('  （未发现超过 10 KB 的 key）')
            return
        print('  %-42s %12s %s' % ('key', '大小', '类型'))
        print('  ' + '-' * 66)
        for k, size, t in bk:
            print('  %-42s %12s %s' % (k[:42], _human(size), t))

    def hot_keys(self, top=10, sample=300):
        """
        热 key 识别。OBJECT FREQ 只在 maxmemory-policy 为 LFU 系列时才有效，
        否则会报错——这不是 bug，是 LFU 计数器未启用。
        sample 限制扫描数量，避免全库 SCAN 拖慢线上实例。
        """
        policy = _dec(self.r.cmd('CONFIG', 'GET', 'maxmemory-policy')[1])
        if 'lfu' not in policy.lower():
            return None, policy   # 返回 None 表示策略不支持
        keys = self.scan_all()[:sample]
        out = []
        for k in keys:
            k = _dec(k)
            try:
                f = self.r.cmd('OBJECT', 'FREQ', k)
                if f:
                    out.append((k, f))
            except RedisError:
                continue
        out.sort(key=lambda x: -x[1])
        return out[:top], _dec(policy)

    # ---------- 延迟与延迟尖刺 ----------
    def latency_events(self):
        """延迟监控需要 latency-monitor-threshold > 0 才有数据"""
        raw = self.r.cmd('LATENCY', 'LATEST')
        return raw

    def latency_monitor_threshold(self):
        return int(self.r.cmd('CONFIG', 'GET', 'latency-monitor-threshold')[1])


def _human(n):
    for unit in ('B', 'KB', 'MB', 'GB'):
        if abs(n) < 1024.0:
            return '%.2f %s' % (n, unit)
        n /= 1024.0
    return '%.2f TB' % n
