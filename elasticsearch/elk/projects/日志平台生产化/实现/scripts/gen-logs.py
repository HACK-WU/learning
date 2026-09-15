#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
结课实战：模拟 shop-api 的应用日志生成器

设计意图（对应课程知识点）：
  1. **两种格式混杂** —— JSON（新版本服务）与半结构化文本（老版本服务）同时存在，
     真实系统里就是这样的。Logstash 管道必须能同时处理，这是课 7 分支条件的用武之地。
  2. **三台"主机"** —— web-01 / web-02 / web-03，其中 web-03 故障率明显偏高，
     用来在 Dashboard 上体现"按主机下钻"的价值（课 11）。
  3. **@timestamp 是事件时间** —— 生成时写的是日志里的真实时间，
     由 Logstash 的 date 插件校准进 @timestamp（课 3 的"采集时间 vs 事件时间"）。

  4. **另有一路 nginx 访问日志** —— 格式与业务日志完全不同（combined log format），
     走 Filebeat 的第二个 input、Logstash 的第一条分支。用来证明"多输入隔离"不是空话：
     两条分支的 grok 规则互不干扰，写出来的字段也各归各位。

用法：
    python3 gen-logs.py                      # 默认：最近 3 小时 600 条应用日志
    python3 gen-logs.py 200 60               # 200 条，铺在最近 60 分钟
    python3 gen-logs.py 10 1 --burst         # 立即灌 10 条 ERROR（触发告警用，@timestamp=now）
    python3 gen-logs.py 600 180 --nginx 400  # 同时生成 400 行 nginx 访问日志
"""
import json
import random
import sys
import time
import os
from datetime import datetime, timedelta, timezone

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "logs")
HOSTS = ["web-01", "web-02", "web-03"]          # web-03 故障率更高
HOST_WEIGHT = [0.35, 0.35, 0.30]
PATHS = ["/api/pay/submit", "/api/order/create", "/api/user/profile", "/api/cart/list", "/health"]
LEVELS = ["DEBUG", "INFO", "INFO", "INFO", "WARN", "ERROR"]   # ERROR ≈ 1/6
MSG = {
    "DEBUG": ["cache hit key=user:{}", "sql prepared in {}ms", "loaded config version {}"],
    "INFO":  ["request completed", "order created id={}", "user login uid={}"],
    "WARN":  ["slow query {}ms", "retrying upstream attempt {}", "connection pool near limit"],
    "ERROR": ["payment timeout after {}ms", "upstream connect error",
              "NullPointerException at PayService", "db connection refused"],
}


def _pick_host():
    r = random.random()
    acc = 0.0
    for h, w in zip(HOSTS, HOST_WEIGHT):
        acc += w
        if r <= acc:
            return h
    return HOSTS[-1]


def make_event(ts: datetime, host: str, level: str, as_json: bool):
    path = random.choice(PATHS)
    status = 200 if level in ("DEBUG", "INFO") else (404 if level == "WARN" else 500)
    duration = random.randint(5, 300) if status == 200 else random.randint(300, 3000)
    msg = random.choice(MSG[level]).format(random.randint(10, 999))

    if as_json:
        return json.dumps({
            "ts": ts.strftime("%Y-%m-%dT%H:%M:%S+08:00"),
            "level": level,
            "host": host,
            "path": path,
            "status": status,
            "duration_ms": duration,
            "msg": msg,
            "trace_id": f"{random.randint(0x100000, 0xffffff):x}",
        }, ensure_ascii=False)
    # 半结构化文本（老版本服务）
    # ⚠️ /health 只有一段，取 [1] 会 IndexError —— 用最后一段兜底
    seg = [s for s in path.split("/") if s]
    cls = (seg[1] if len(seg) > 1 else (seg[0] if seg else "App")).capitalize()
    return (f"{ts.strftime('%Y-%m-%d %H:%M:%S')} [{level}] [http-nio-8080-exec-{random.randint(1, 8)}] "
            f"com.shop.{cls}Service - {msg} "
            f"path={path} status={status} duration={duration}ms host={host}")


# ── Nginx 访问日志（combined log format）──────────────────────────────
METHODS = ["GET", "GET", "GET", "POST", "POST", "DELETE"]
UAS = [
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/126.0 Safari/537.36",
    "curl/8.4.0",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) Mobile/15E148 Safari/604.1",
    "kube-probe/1.29",
]


def make_access(ts: datetime, host: str) -> str:
    """生成一行 nginx combined 格式的访问日志。

    ⚠️ 月份必须是【英文缩写】（Sep），因为 Logstash 的 HTTPDATE 模式只认英文月份；
       写成 09 或者中文"9月"都会让 grok 的 date 部分解析失败。
    """
    ip = f"10.20.{random.randint(1, 8)}.{random.randint(2, 250)}"
    path = random.choice(PATHS)
    method = random.choice(METHODS)
    # 少数请求打 4xx/5xx，方便 Dashboard 上做"错误率"
    status = random.choices([200, 200, 200, 200, 301, 404, 500, 502],
                            weights=[55, 12, 10, 8, 5, 6, 3, 1])[0]
    body = random.randint(120, 9000) if status < 400 else random.randint(0, 400)
    ua = random.choice(UAS)
    return (f'{ip} - - [{ts.strftime("%d/%b/%Y:%H:%M:%S +0800")}] '
            f'"{method} {path} HTTP/1.1" {status} {body} "-" "{ua}"')


def main():
    argv = [a for a in sys.argv[1:] if not a.startswith("--")]
    n = int(argv[0]) if len(argv) > 0 else 600
    span_min = int(argv[1]) if len(argv) > 1 else 180
    burst = "--burst" in sys.argv          # burst 模式：全部 ERROR 且 @timestamp = now
    # --nginx N：额外生成 N 行 nginx 访问日志（不传则只生成应用日志）
    nginx_n = 0
    if "--nginx" in sys.argv:
        idx = sys.argv.index("--nginx")
        if idx + 1 < len(sys.argv) and sys.argv[idx + 1].isdigit():
            nginx_n = int(sys.argv[idx + 1])

    random.seed()
    os.makedirs(OUT_DIR, exist_ok=True)
    now = datetime.now(timezone(timedelta(hours=8)))

    # 三台主机各一个文件（模拟三台机器的日志）
    files = {h: open(os.path.join(OUT_DIR, f"app-{h}.log"), "a", encoding="utf-8") for h in HOSTS}

    written = 0
    for i in range(n):
        if burst:
            ts = now
            host, level = random.choice(HOSTS), "ERROR"
        else:
            ts = now - timedelta(minutes=random.uniform(0, span_min))
            host = _pick_host()
            # web-03 故障率翻倍：给它的 level 池多塞一个 ERROR
            pool = LEVELS + (["ERROR"] if host == "web-03" else [])
            level = random.choice(pool)

        as_json = random.random() < 0.7          # 70% JSON / 30% 文本
        line = make_event(ts, host, level, as_json)
        # 事件时间统一按 +08:00 输出（date 插件用 Asia/Shanghai 解析）
        files[host].write(line + "\n")
        written += 1

    for f in files.values():
        f.close()

    # ── 另起一路：nginx 访问日志（每台机器一个文件）───────────────────
    if nginx_n > 0:
        nf = {h: open(os.path.join(OUT_DIR, f"nginx-{h}.log"), "a", encoding="utf-8")
              for h in HOSTS}
        for _ in range(nginx_n):
            ts = now if burst else now - timedelta(minutes=random.uniform(0, span_min))
            h = _pick_host()
            nf[h].write(make_access(ts, h) + "\n")
        for f in nf.values():
            f.close()

    mode = "BURST(ERROR@now)" if burst else f"铺在最近 {span_min} 分钟"
    print(f"已写入 {written} 条应用日志到 {os.path.abspath(OUT_DIR)}/app-*.log  [{mode}]")
    if nginx_n:
        print(f"已写入 {nginx_n} 条访问日志到 {os.path.abspath(OUT_DIR)}/nginx-*.log")
    print(f"当前时间(北京时间) = {now.strftime('%Y-%m-%d %H:%M:%S')}")
    print("提示：生成后需清空 Filebeat registry（重建容器）才会重新采集全部历史行")


if __name__ == "__main__":
    main()
