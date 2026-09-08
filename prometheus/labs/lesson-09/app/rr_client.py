#!/usr/bin/env python3
"""直接请求 /api/v1/read，构造两种响应模式的 ReadRequest。

SAMPLES            : accepted_response_types 留空 -> ReadResponse（原始样本）
STREAMED_XOR_CHUNKS: accepted_response_types=[1]  -> ChunkedReadResponse 帧流
"""
import sys, time, subprocess, struct
import urllib.request
import cramjam

PROM = "http://l9-prom-1:9090/api/v1/read"


def varint(n):
    out = b""
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out += bytes([b | 0x80])
        else:
            out += bytes([b])
            return out


def tag(field, wt):
    return varint((field << 3) | wt)


def ld(f, payload):
    return tag(f, 2) + varint(len(payload)) + payload


def vi(f, n):
    return tag(f, 0) + varint(n)


def build_read_request(name_val, start_ms, end_ms, accepted):
    """ReadRequest{ queries=1, accepted_response_types=2 }"""
    # LabelMatcher{ type=1, name=2, value=3 }; type 0 = EQ
    matcher = vi(1, 0) + ld(2, b"__name__") + ld(3, name_val.encode())
    # Query{ start_timestamp_ms=1, end_timestamp_ms=2, matchers=3 }
    q = vi(1, start_ms) + vi(2, end_ms) + ld(3, matcher)
    req = ld(1, q)
    for a in accepted:
        req += vi(2, a)
    return req


def snappy_compress(data):
    return bytes(cramjam.snappy.compress_raw(data))


def post(body, timeout=120):
    req = urllib.request.Request(
        PROM, data=body, method="POST",
        headers={
            "Content-Type": "application/x-protobuf",
            "Content-Encoding": "snappy",
            "Accept": "application/x-protobuf,application/x-streamed-protobuf",
        })
    t0 = time.time()
    try:
        r = urllib.request.urlopen(req, timeout=timeout)
        raw = r.read()
        return {
            "ok": True, "code": r.status,
            "ctype": r.headers.get("Content-Type", ""),
            "bytes": len(raw), "ms": (time.time() - t0) * 1000,
            "raw": raw,
        }
    except urllib.error.HTTPError as e:
        return {"ok": False, "code": e.code, "bytes": len(e.read()),
                "ms": (time.time() - t0) * 1000, "err": str(e)}
    except Exception as e:
        return {"ok": False, "code": -1, "bytes": 0,
                "ms": (time.time() - t0) * 1000, "err": str(e)}


def count_stream_frames(raw):
    """ChunkedReadResponse 帧: varint len + uint32 crc + payload"""
    n, i = 0, 0
    while i < len(raw):
        # read varint length
        shift, size = 0, 0
        while True:
            b = raw[i]; i += 1
            size |= (b & 0x7F) << shift
            shift += 7
            if not (b & 0x80):
                break
        if i + 4 > len(raw):
            break
        i += 4          # CRC32C
        i += size       # payload
        n += 1
        if size == 0:
            break
    return n


def parse_samples_count(raw, decompressed):
    """ReadResponse{ results=1 } -> QueryResult{ timeseries=1 } 计数"""
    data = decompressed
    series = 0
    i = 0
    # 简单扫描: 统计 QueryResult 中的 timeseries 字段(1, LEN)
    while i < len(data):
        # varint key
        shift, key = 0, 0
        while True:
            b = data[i]; i += 1
            key |= (b & 0x7F) << shift
            shift += 7
            if not (b & 0x80):
                break
        f, wt = key >> 3, key & 7
        if wt == 2:
            shift, size = 0, 0
            while True:
                b = data[i]; i += 1
                size |= (b & 0x7F) << shift
                shift += 7
                if not (b & 0x80):
                    break
            if f == 1:
                series += 1
            i += size
        elif wt == 0:
            while data[i] & 0x80:
                i += 1
            i += 1
        else:
            break
    return series


def run(mode_name, accepted, metric, duration_s, hp):
    global PROM
    PROM = f"http://{hp}/api/v1/read"
    end_ms = int(time.time() * 1000)
    start_ms = end_ms - duration_s * 1000
    body = build_read_request(metric, start_ms, end_ms, accepted)
    res = post(snappy_compress(body))
    print(f"\n--- {mode_name} ---")
    print(f"  HTTP {res.get('code')}  ctype={res.get('ctype','')}")
    print(f"  bytes={res.get('bytes')}  ms={res.get('ms'):.1f}")
    if not res.get("ok"):
        print(f"  ERR: {res.get('err')}")
        return None
    raw = res["raw"]
    if "streamed" in res.get("ctype", ""):
        frames = count_stream_frames(raw)
        print(f"  frames={frames}")
        return {"mode": mode_name, "bytes": res["bytes"], "ms": res["ms"],
                "frames": frames}
    else:
        dec = bytes(cramjam.snappy.decompress_raw(raw))
        print(f"  decompressed={len(dec)}")
        return {"mode": mode_name, "bytes": res["bytes"], "ms": res["ms"],
                "dec": len(dec)}


if __name__ == "__main__":
    metric = sys.argv[1] if len(sys.argv) > 1 else "app_requests_total"
    dur = int(sys.argv[2]) if len(sys.argv) > 2 else 3600
    port = sys.argv[3] if len(sys.argv) > 3 else "9090"
    r1 = run("SAMPLES", [], metric, dur, port)
    r2 = run("STREAMED_XOR_CHUNKS", [1], metric, dur, port)
    print("\n=== SUMMARY ===")
    for r in (r1, r2):
        if r:
            print(f"  {r['mode']}: bytes={r['bytes']} ms={r['ms']:.1f}")
    if r1 and r2:
        print(f"  size ratio samples/streamed = {r1['bytes']/max(r2['bytes'],1):.2f}x")
