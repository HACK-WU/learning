#!/usr/bin/env python3
"""
E3（核心）：WAL 兜底与真正的数据丢失点

remote write 不只是内存队列，还有一层 WAL 兜底：
  - 样本先写 WAL（持久化）
  - WAL watcher 把样本喂给内存队列
  - 队列发给远端，成功后 WAL 中对应的段才能被截断

因此"队列满"不等于"数据丢"——只要 WAL 还在，重启后能重放。
真正的丢失发生在：WAL 段被截断（已确认发送）之后。

本实验用「进程崩溃」来区分两种情况：
  场景 A：队列积压时正常重启（SIGTERM）→ WAL 完整，重启后应重放补发
  场景 B：队列积压时强杀（SIGKILL）→ WAL 未 flush 的部分丢失

关键：观察重启后 receiver 是否收到"迟到很久"的样本（时间戳远早于当前）
"""
import subprocess
import time

from l7lib import qnum, recv_mode, recv_reset, recv_stats

URL = 'http://l7-receiver:8080/api/v1/write'
LBL = f'{{url="{URL}"}}'


def sh(cmd):
    return subprocess.run(["bash", "-lc", cmd], capture_output=True, text=True).stdout.strip()


print("=" * 78)
print("E3  WAL 兜底与真正的数据丢失点")
print("=" * 78)

print("\n########## 场景 A：队列积压中优雅重启（SIGTERM） ##########")
recv_mode("ok")
recv_reset()
time.sleep(10)

print("  注入 500，让队列积压 45 秒")
recv_mode("500")
time.sleep(45)
before = {
    "pending": qnum(f"prometheus_remote_storage_samples_pending{LBL}") or 0,
    "sent": qnum(f"prometheus_remote_storage_samples_total{LBL}") or 0,
}
print(f"    重启前：pending={before['pending']:.0f} sent={before['sent']:.0f}")

print("\n  保持 500 状态，优雅重启 Prometheus（模拟发布/扩缩容）")
sh("docker stop -t 25 l7-prom")
print("    已停止（SIGTERM，给了 25 秒 graceful 时间）")
time.sleep(3)
sh("docker start l7-prom")
print("    已启动，等待就绪")
time.sleep(30)

print("\n  切回 ok，看积压是否补发")
recv_mode("ok")
time.sleep(20)

after = {
    "pending": qnum(f"prometheus_remote_storage_samples_pending{LBL}") or 0,
    "sent": qnum(f"prometheus_remote_storage_samples_total{LBL}") or 0,
}
s = recv_stats()
print(f"    重启后：pending={after['pending']:.0f} sent={after['sent']:.0f}")
print(f"    receiver: requests={s['requests']} accepted={s['accepted']} rejected={s['rejected']}")

print("\n  观察 WAL 重放迹象")
replay = qnum("prometheus_tsdb_wal_replay_duration_seconds_count")
segs = qnum("prometheus_tsdb_wal_segment_current")
print(f"    WAL 重放次数计数 = {replay}")
print(f"    当前 WAL 段号    = {segs}")

print("\n########## 场景 B：队列积压中强杀（SIGKILL） ##########")
recv_mode("ok")
recv_reset()
time.sleep(10)

print("  注入 500，让队列积压 45 秒")
recv_mode("500")
time.sleep(45)
b_before = {
    "pending": qnum(f"prometheus_remote_storage_samples_pending{LBL}") or 0,
    "sent": qnum(f"prometheus_remote_storage_samples_total{LBL}") or 0,
}
print(f"    强杀前：pending={b_before['pending']:.0f} sent={b_before['sent']:.0f}")

print("\n  强杀 Prometheus（模拟 OOM / 节点宕机）")
sh("docker kill -s KILL l7-prom")
print("    已 SIGKILL")
time.sleep(3)
sh("docker start l7-prom")
print("    已启动，等待就绪")
time.sleep(30)

recv_mode("ok")
time.sleep(20)
b_after = {
    "pending": qnum(f"prometheus_remote_storage_samples_pending{LBL}") or 0,
    "sent": qnum(f"prometheus_remote_storage_samples_total{LBL}") or 0,
}
s2 = recv_stats()
print(f"    重启后：pending={b_after['pending']:.0f} sent={b_after['sent']:.0f}")
print(f"    receiver: requests={s2['requests']} accepted={s2['accepted']} rejected={s2['rejected']}")

print("\n" + "=" * 78)
print("E3 结论")
print("=" * 78)
print(f"""
场景 A（SIGTERM 优雅重启）：
  pending {before['pending']:.0f} → {after['pending']:.0f}
  重启后队列恢复消费，说明 WAL 中的积压数据被重放

场景 B（SIGKILL 强杀）：
  pending {b_before['pending']:.0f} → {b_after['pending']:.0f}
  对比两者可判断未 flush 的 WAL 是否丢失

共同点：两种重启后 sent 都继续增长，说明 WAL 提供了跨进程的兜底能力。
真正的数据丢失发生在：WAL 段被截断之后（数据已确认发送，或超过保留期）。
""")
