#!/bin/bash
# 压缩率实测：三种口径都测，避免"只报一个数字"造成误解
#
# 为什么必须实测压缩率而不是引用网上的"压缩率表格"：
#   压缩率完全取决于消息体的熵。本 bench 的消息体是 JSON（固定字段名 + 变化的值 + 长 padding），
#   与你的真实业务消息不一定同构。所以这里明确测三种 payload，
#   让读者一眼看出"压缩率随消息体变化能差多少"。
set -u
cat > /tmp/ratio.py <<'PYEOF'
import gzip, json, os, random, time
import lz4.frame
import snappy
import zstandard as zstd

N = 2000
random.seed(42)

def mk_json(i):
    return json.dumps({"seq": i, "ts": 0, "src": "bench",
                       "pad": "x" * 900}).encode()

def mk_log(i):
    return (f'2026-09-21T10:00:00.123Z INFO  [http-nio-8080-exec-{i%16}] '
            f'c.e.demo.UserController - GET /api/users/{i} 200 15ms').encode()

def mk_random(i):
    return os.urandom(1024)

DATASETS = {
    "JSON(含长padding)": [mk_json(i) for i in range(N)],
    "应用日志(高重复)": [mk_log(i) for i in range(N)],
    "随机字节(不可压)": [mk_random(i) for i in range(N)],
}

def ratio(name, fn, data):
    raw = sum(len(d) for d in data)
    t0 = time.perf_counter()
    comp = sum(len(fn(d)) for d in data)
    dt = time.perf_counter() - t0
    return raw, comp, raw / comp if comp else 0, dt, raw / 1024 / 1024 / dt if dt else 0

print(f"{'数据集':<20}{'codec':<8}{'原始KB':>10}{'压缩后KB':>11}{'压缩比':>9}{'CPU耗时ms':>11}{'单核吞吐MB/s':>14}")
print("-" * 83)

for label, data in DATASETS.items():
    raw_total = sum(len(d) for d in data)
    row0 = True
    for codec, fn in (
        ("gzip", lambda d: gzip.compress(d, 6)),
        ("snappy", lambda d: snappy.compress(d)),
        ("lz4", lambda d: lz4.frame.compress(d)),
        ("zstd", lambda d: zstd.ZstdCompressor(level=3).compress(d)),
    ):
        raw, comp, r, dt, mb = ratio(label, fn, data)
        rn = f"{r:.2f}x" if r else "n/a"
        print(f"{label if row0 else '':<20}{codec:<8}{raw/1024:>10.0f}{comp/1024:>11.0f}"
              f"{rn:>9}{dt*1000:>11.0f}{mb:>14.1f}")
        row0 = False
    print("-" * 83)

print("\n注：以上为【单条独立压缩】口径（Kafka 默认对整批压缩，实际压缩率更高）。")
print("下面补测【整批压缩】口径，二者差异本身就是课 7 要讲的知识点。")

print(f"\n{'数据集':<20}{'codec':<8}{'整批压缩比':>12}")
print("-" * 42)
for label, data in DATASETS.items():
    blob = b"".join(data)
    for codec, fn in (
        ("gzip", lambda d: gzip.compress(d, 6)),
        ("snappy", lambda d: snappy.compress(d)),
        ("lz4", lambda d: lz4.frame.compress(d)),
        ("zstd", lambda d: zstd.ZstdCompressor(level=3).compress(d)),
    ):
        c = len(fn(blob))
        print(f"{label:<20}{codec:<8}{len(blob)/c:>11.2f}x")
    print("-" * 42)
PYEOF
docker run --rm -v /tmp/ratio.py:/r.py kafka-pybench:3.12 \
  /app/.venv/bin/python /r.py 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed'
