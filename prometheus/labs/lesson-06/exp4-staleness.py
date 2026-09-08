"""E4/E5/E6：staleness marker 与 lookback delta。

三组实验：
  E4 目标消失（/kill，抓取仍成功 200）→ 序列何时变为"无数据"
  E5 抓取失败（/break，返回 500）    → 与 E4 的关键对照
  E6 rate() 在目标消失后的行为         → 承接课4/课5 的伏笔

关键变量：query.lookback-delta（实测 v3.14.0 默认 5m）
"""
import time

from l6lib import app_get, query, now

EXPR = "l6_concurrency"


def probe(expr):
    """返回 (命中条数, 值或None)。"""
    r = query(expr)
    if not r or len(r) == 0:
        return 0, None
    return len(r), float(r[0]["value"][1])


def watch(label, seconds, every=5, expr=EXPR):
    print(f"   {label}")
    t0 = now()
    for _ in range(seconds // every):
        n, v = probe(expr)
        el = now() - t0
        mark = "有数据" if n else "★无数据"
        vs = f"{v:.1f}" if v is not None else "-"
        print(f"     t+{el:>5.1f}s  序列数={n}  值={vs:<8} {mark}")
        time.sleep(every)


print("== 准备：确保目标存活 ==")
print("revive:", app_get("/revive"))
print("unbreak:", app_get("/unbreak"))
time.sleep(8)
n, v = probe(EXPR)
print(f"基线：序列数={n} 值={v}")

print()
print("=" * 60)
print("E4：目标消失（/kill —— 抓取仍返回 200，只是没有这条序列）")
print("=" * 60)
print("kill:", app_get("/kill"))
watch("kill 之后每 5 秒采样一次：", 40, 5)

print()
print("恢复：")
print("revive:", app_get("/revive"))
time.sleep(10)
n, v = probe(EXPR)
print(f"   恢复后：序列数={n} 值={v}")

print()
print("=" * 60)
print("E5：抓取失败（/break —— /metrics 返回 HTTP 500）")
print("=" * 60)
time.sleep(10)
print("break:", app_get("/break"))
watch("break 之后每 5 秒采样一次：", 40, 5)
print()
print("unbreak:", app_get("/unbreak"))
time.sleep(10)
n, v = probe(EXPR)
print(f"   恢复后：序列数={n} 值={v}")
