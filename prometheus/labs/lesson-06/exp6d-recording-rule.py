"""E6-D：recording rule 预聚合的真实收益 —— 用两条规则做前后对照。

做法：
  1. 先测「直接查」的成本
  2. 建一条 recording rule 把结果预计算好
  3. 等规则求值产出数据
  4. 再测「查预聚合结果」的成本

这是课4 recording rule 知识点的**成本视角**补充：
固化不只是"台阶更新频率"的变化，更是查询成本的量级下降。
"""
import statistics
import subprocess
import time

from l6lib import app_get, query, query_range, now

RULES_LOCAL = "rules.yml"


def bench(expr, start, end, step, n=9):
    els, pts = [], []
    for _ in range(n):
        t0 = time.perf_counter()
        r = query_range(expr, start, end, step)
        els.append((time.perf_counter() - t0) * 1000)
        pts.append(sum(len(x["values"]) for x in r) if r else 0)
    return (statistics.median(els), min(els), max(els),
            int(statistics.median(pts or [0])))


def docker_exec(cmd):
    return subprocess.run(["docker", "exec", "l6-prom"] + cmd,
                          capture_output=True, text=True)


print("== 准备：20000 条序列，攒 60 秒 ==")
print(app_get("/cardinality?n=20000"))
print(app_get("/revive"))
time.sleep(60)

end = now()

print()
print("== 1. 改写前：直接查原始表达式 ==")
before_cases = [
    ("sum(rate(l6_card_metric[5m]))", "全聚合"),
    ("sum by (idx) (rate(l6_card_metric[5m]))", "按 idx 聚合"),
]
before = {}
for expr, label in before_cases:
    m, lo, hi, pts = bench(expr, end - 300, end, "15s")
    before[label] = (m, pts)
    print(f"   {label:<14} 中位={m:>7.1f}ms  点数={pts:>7}  ({lo:.1f}~{hi:.1f})")

print()
print("== 2. 复制规则文件并 reload ==")
# 规则文件已随 prometheus.yml 一起声明为 rule_files，用 docker cp 覆盖
subprocess.run(["docker", "cp", RULES_LOCAL, "l6-prom:/etc/prometheus/rules.yml"],
               capture_output=True)
r = docker_exec(["sh", "-c", "cat /etc/prometheus/rules.yml"])
print("   容器内规则文件行数:", len(r.stdout.strip().splitlines()))

docker_exec(["sh", "-c", "kill -HUP 1"])
print("   已 reload，等待规则求值（interval=10s，等 45 秒）")
time.sleep(45)

print()
print("== 3. 确认预聚合产物已生成（关键校验） ==")
ok = True
for m in ["l6:card_rate:sum", "l6:card_rate:by_idx", "l6:card_rate:top10"]:
    r = query(m)
    n = len(r) if r else 0
    print(f"   {m:<22} 序列数 = {n}")
    if n == 0:
        ok = False
if not ok:
    print("   !! 产物为 0，后续降幅数据无效，终止")
    raise SystemExit(1)

print()
print("== 4. 改写后：查预聚合结果 ==")
after_cases = [
    ("l6:card_rate:sum", "全聚合"),
    ("l6:card_rate:by_idx", "按 idx 聚合"),
]
print(f'{"场景":<14} | {"改写前(ms)":>10} | {"改写前点数":>10} | {"改写后(ms)":>10} | {"改写后点数":>10} | {"降幅":>8}')
print("-" * 80)
for expr, label in after_cases:
    m, lo, hi, pts = bench(expr, end - 300, end, "15s")
    bm, bpts = before.get(label, (0, 0))
    cut = (1 - m / bm) * 100 if bm else 0
    print(f"{label:<14} | {bm:>10.1f} | {bpts:>10} | {m:>10.1f} | {pts:>10} | {cut:>7.1f}%")
