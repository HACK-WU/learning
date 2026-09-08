#!/usr/bin/env python3
# 补充采集：C1 段需要"故障进行中"才能演示 recording rule 的值冻结
# 上一轮采样时刚好无故障，ratio1m 恒为 0，看不出冻结效果
import json
import subprocess
import time
import urllib.parse
import urllib.request

BASE = "http://localhost:9094"


def q(expr):
    url = BASE + "/api/v1/query?" + urllib.parse.urlencode({"query": expr})
    with urllib.request.urlopen(url, timeout=20) as r:
        return json.loads(r.read().decode("utf-8"))["data"]["result"]


def qnum(expr):
    r = q(expr)
    return float(r[0]["value"][1]) if r else None


def fault(path):
    code = ("import urllib.request;"
            "print(urllib.request.urlopen('http://localhost:8080/fault/%s').read().decode())" % path)
    p = subprocess.run(["docker", "exec", "l4-app", "python3", "-c", code],
                       capture_output=True, text=True)
    return p.stdout.strip()


print("#" * 70)
print("# 补充采集：recording rule 的值冻结（故障进行中）")
print("#" * 70)

# 用振荡模式，让源数据持续变化，这样才看得出"冻结"
out = fault("wobble?center=0.30&period=200&amp=0.25")
print()
print("注入持续变化的错误率: %s" % out)
print("等待 70 秒让 rate1m 窗口填满")
time.sleep(70)

print()
print("### C1b. 连续 30 次每秒采样 job:app_requests_error:ratio1m")
print("  组 C 的 interval = 10s，所以 30 秒内理论最多变 3~4 次")
print()
samples = []
for i in range(30):
    v = qnum("job:app_requests_error:ratio1m")
    samples.append((time.time(), v))
    time.sleep(1)

vals = [v for _, v in samples if v is not None]
uniq = []
for v in vals:
    if not uniq or abs(v - uniq[-1]) > 1e-9:
        uniq.append(v)

print("  采样次数: %d" % len(samples))
print("  值的不同取值个数: %d" % len(uniq))
print()
print("  逐次采样（查询时刻 / 值）:")
for qt, v in samples:
    print("    %.1f  %.6f" % (qt, v if v is not None else -1))
print()
print("  去重后的取值序列: %s" % ", ".join("%.6f" % v for v in uniq))
print()
print("  -> 30 次采样只得到 %d 个不同值，说明值被冻结在求值时刻" % len(uniq))

# 同时对比：直接查表达式（不走 recording rule）每次都会重算
print()
print("### C2b. 对照组：直接查等价表达式（不走 recording rule）")
expr = ('sum by (job) (rate(app_requests_total{status="500"}[1m])) '
        '/ clamp_min(sum by (job) (rate(app_requests_total[1m])), 1e-9)')
print("  表达式: %s" % expr)
print()
direct = []
for i in range(10):
    v = qnum(expr)
    direct.append(v)
    time.sleep(1)
duniq = []
for v in direct:
    if not duniq or abs(v - duniq[-1]) > 1e-9:
        duniq.append(v)
print("  10 次采样得到 %d 个不同值" % len(duniq))
print("  取值: %s" % ", ".join("%.6f" % v for v in direct if v is not None))
print()
print("  -> 直接查询每次都重算，值持续变化；recording rule 读的是上次求值的快照")

print()
print("#" * 70)
print("# 补充采集结束")
print("#" * 70)
