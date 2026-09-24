"""课 1 三库生态核验 v2：修正上一版的纯 Python 判定 bug。

v1 的 bug：用 "any 出现在任何平台标签里" 判断纯 Python，
导致 confluent-kafka（manylinux/win_amd64，明明是 C 扩展）被误判为纯 Python。
正确判据：wheel 文件名形如 {name}-{ver}-{python_tag}-{abi_tag}-{platform_tag}.whl
  - 纯 Python：platform_tag == "any"（且 abi_tag == "none"）
  - C 扩展   ：platform_tag 是 manylinux/win_amd64/macosx 等具体平台
"""
import json
import urllib.request
from datetime import datetime

LIBS = ["kafka-python", "kafka-python-ng", "confluent-kafka", "aiokafka"]
TODAY = datetime(2026, 9, 21)

for lib in LIBS:
    url = f"https://pypi.org/pypi/{lib}/json"
    with urllib.request.urlopen(url, timeout=30) as r:
        data = json.load(r)

    info = data["info"]
    latest = info["version"]
    releases = data["releases"]
    rel_files = releases.get(latest, [])
    upload = rel_files[0]["upload_time"][:10] if rel_files else None

    # 距今天数
    days = (TODAY - datetime.strptime(upload, "%Y-%m-%d")).days if upload else None

    # 修正后的平台判定
    platforms, abis = set(), set()
    for w in rel_files:
        fn = w["filename"]
        if not fn.endswith(".whl"):
            continue
        parts = fn[:-4].split("-")   # 去掉 .whl 再切
        if len(parts) >= 5:
            platforms.add(parts[-1])
            abis.add(parts[-2])

    is_pure = platforms == {"any"}

    print(f"=== {lib} ===")
    print(f"  最新版        : {latest}  ({upload}，距今 {days} 天)")
    print(f"  platform_tag  : {sorted(platforms)}")
    print(f"  abi_tag       : {sorted(abis)}")
    print(f"  判定          : {'纯 Python（无 C 扩展）' if is_pure else '含 C 扩展（平台特定 wheel）'}")

    # 最近 3 个正式版的时间（排除 rc/b/dev）
    dated = []
    for ver, files in releases.items():
        if not files:
            continue
        if any(x in ver.lower() for x in ("rc", "b1", "b2", "dev", "a1")):
            continue
        dated.append((files[0]["upload_time"][:10], ver))
    dated.sort(reverse=True)
    print(f"  最近 3 个正式版: {', '.join(f'{v}({d})' for d, v in dated[:3])}")
    print()
