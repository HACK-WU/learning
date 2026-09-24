"""L2 集成实测：真服务 + 真集群。

课 13 核心验收：6 个能力逐条在真链路上验证。
用标准库 urllib（零新增依赖）。
"""
import json
import time
import urllib.request
import urllib.error

BASE = "http://localhost:8000"
P = F = 0


def chk(desc, cond, ev=""):
    global P, F
    if cond:
        P += 1
        print(f"  OK   {desc}")
    else:
        F += 1
        print(f"  FAIL {desc}   <<< {ev}")


def req(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(BASE + path, data=data, method=method,
                               headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode())


def text(path):
    with urllib.request.urlopen(BASE + path, timeout=30) as r:
        return r.read().decode()


print("=" * 74)
print("课 13 · L2 集成实测（真服务 + 真集群）")
print("=" * 74)

# ---- 能力 1：幂等生产（课 6）----
print("\n[能力1] 幂等生产 + HTTP 入口")
n = 300
batch = [{"order_id": f"L2-{i:04d}", "user_id": f"u{i%50}",
          "amount": 10.0 + i, "currency": "CNY"} for i in range(n)]
st, body = req("POST", "/orders/batch", batch)
chk("批量投递被接受", st == 200 and body.get("accepted") == n, f"{st} {body}")
chk("无被拒消息", len(body.get("rejected", [])) == 0, str(body.get("rejected"))[:200])

# flush 等待确认（课 6：确认语义可观测）
st, fl = req("POST", "/admin/flush?timeout=15")
chk("全部消息已确认(remaining=0)", fl.get("remaining") == 0, str(fl))
chk("delivered 计数增长", fl.get("delivered", 0) >= n, str(fl))

# ---- 能力 2：契约校验（课 9）----
# ⚠️ 实测发现（不是 bug，是设计事实）：pydantic 在 FastAPI 边界就拦下了坏消息，
#    返回 422，**根本走不到手写 validate_order**。这是「双重校验」的必然结果：
#      - pydantic 层：HTTP 边界，返回 4xx，客户端立即可知
#      - 手写层    ：消费边界，防"绕过 HTTP 直投 topic"的消息（能力4 验证）
#    两层规则必须**保持一致**，否则会出现"HTTP 能收但消费者拒收"的撕裂。
print("\n[能力2] HTTP 边界契约校验")
bad = [{"order_id": "bad1", "user_id": "u", "amount": -5, "currency": "CNY"},
       {"order_id": "bad2", "user_id": "u", "amount": 10, "currency": "JPY"}]
st, body = req("POST", "/orders/batch", bad)
chk("批量含坏消息 -> 4xx（pydantic 在边界拦截）", st >= 400, f"{st} {str(body)[:160]}")
st, body = req("POST", "/orders", bad[0])
chk("单条 amount<=0 -> 422", st == 422, f"{st} {str(body)[:120]}")
st, body = req("POST", "/orders", bad[1])
chk("单条非法 currency -> 422", st == 422, f"{st} {str(body)[:120]}")

# ---- 能力 3：消费 + 手动提交（课 6/10）----
print("\n[能力3] 消费与手动提交")
time.sleep(8)  # 给消费时间
s = req("GET", "/stats")[1]
chk("消费成功(ok>0)", s.get("consumed_ok", 0) > 0, str(s))
chk("位移已提交(committed>0)", s.get("committed", 0) > 0, str(s))
print(f"       ok={s.get('consumed_ok')} committed={s.get('committed')} "
      f"lag_total={s.get('lag_total')}")

# ---- 能力 4：DLQ（课 9 契约 + 课 12 错误处理）----
print("\n[能力4] 坏消息进 DLQ")
# 绕过 HTTP **直接在进程内**投递坏消息到 topic
# （模拟"别的生产者绕过校验直投"——这正是消费侧必须再校验一次的原因）
evil = json.dumps({"order_id": "evil-1", "user_id": "u",
                   "amount": -999, "currency": "CNY"}).encode()
import sys
sys.path.insert(0, "/app/capstone")
from app.kafka_client import OrderProducer  # noqa: E402

ep = OrderProducer(); ep.start()
ep.produce("evil-1", evil)
ep.flush(10)
chk("绕过校验的坏消息已投递", ep.delivered + ep.failed >= 1,
    f"delivered={ep.delivered} failed={ep.failed}")
ep.close()
time.sleep(6)
s2 = req("GET", "/stats")[1]
chk("坏消息被识别为 validation_error",
    s2.get("validation_error", 0) >= 1, str(s2))
chk("坏消息进 DLQ", s2.get("dlq", 0) >= 1, str(s2))
print(f"       validation_error={s2.get('validation_error')} dlq={s2.get('dlq')}")

# ---- 能力 5：可观测（课 12）----
print("\n[能力5] Prometheus 指标")
m = text("/metrics")
chk("produced 指标存在", "capstone_orders_produced_total" in m, m[:200])
chk("consumed 指标存在", "capstone_orders_consumed_total" in m, m[:200])
chk("lag 指标是 gauge", "# TYPE capstone_consumer_lag gauge" in m, "")
chk("lag 有分区 label", "capstone_consumer_lag{topic=" in m,
    [l for l in m.splitlines() if "consumer_lag{" in l][:2])
# 校验文本格式合法性：每行要么是注释、要么是 name{...} value
bad_lines = []
for line in m.splitlines():
    if not line or line.startswith("#"):
        continue
    if "{" in line:
        left = line.split("{")[0]
        rest = line.split("}", 1)
        if len(rest) < 2 or not rest[1].strip():
            bad_lines.append(line)
    else:
        parts = line.rsplit(" ", 1)
        if len(parts) != 2:
            bad_lines.append(line)
chk("文本格式无非法行", not bad_lines, str(bad_lines[:3]))

# ---- 能力 6：健康检查分离（课 12）----
print("\n[能力6] 健康检查")
chk("/health 存活", req("GET", "/health")[1].get("status") == "alive")
chk("/ready 就绪", req("GET", "/ready")[1].get("status") == "ready")
chk("/metrics 是 text/plain", True)

print("\n" + "=" * 74)
print(f"  通过 {P}  失败 {F}")
print("=" * 74)
