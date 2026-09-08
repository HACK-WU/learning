#!/usr/bin/env python3
"""决定性：honor_labels=false 时，两个叶子抓同一个 app 会发生什么？

关键：leaf-a 和 leaf-b 抓的是同一个 l8-app，instance/job 都是 l8-app / l8-app:8080。
- honor_labels=true  -> 保留叶子的 job/instance，靠 cluster 区分（external_labels 附加）
- honor_labels=false -> job/instance 被改写为联邦 target 名，看起来"能区分"
                        但如果联邦 target 的 job 同名呢？那才是真正的冲突
"""
import json
import subprocess


def q(port, expr):
    url = f"http://localhost:{port}/api/v1/query?" + \
        expr.replace('{', '%7B').replace('}', '%7D').replace('"', '%22')
    out = subprocess.run(["curl", "-s", url], capture_output=True, text=True)
    try:
        return json.loads(out.stdout)["data"]["result"]
    except Exception:
        return []


print("=" * 72)
print("场景：两个叶子抓同一个 app（instance 都是 l8-app:8080）")
print("=" * 72)

for label, port in [("honor_labels=true ", 19114), ("honor_labels=false", 19116)]:
    r = q(port, "l8_card_balance")
    print(f"\n  --- {label} ---")
    print(f"  l8_card_balance 总条数 = {len(r)}  （每个叶子 500 条，两叶子应为 1000）")
    # 统计 instance 分布
    inst = {}
    for s in r:
        k = (s["metric"].get("job"), s["metric"].get("instance"))
        inst[k] = inst.get(k, 0) + 1
    for k, v in sorted(inst.items(), key=lambda x: -x[1]):
        print(f"     job={k[0]:16s} instance={k[1]:18s} -> {v} 条")

print()
print("=" * 72)
print("决定性验证：如果两个联邦 job 同名（模拟真实误配）")
print("=" * 72)
print("""
  假如把两个叶子的联邦 job_name 都写成 'federate'：

    - job_name: federate
      static_configs:
        - targets: ["l8-leaf-a:9090"]     # 无区分标签
        - targets: ["l8-leaf-b:9090"]

  honor_labels=true  时：job/instance 来自叶子（l8-app / l8-app:8080），
                        external_labels 的 cluster 保留 -> 仍能区分（1000 条）
  honor_labels=false 时：job=federate, instance=l8-leaf-a:9090 vs l8-leaf-b:9090
                        -> 靠 instance 区分，仍能区分（1000 条）
""")

print()
print("=" * 72)
print("真正的冲突点：external_labels 缺失时（知识点 3 预告）")
print("=" * 72)
r_true = q(19114, "l8_card_balance")
n_true = len(r_true)
print(f"  当前配置（两叶子 external_labels 的 cluster 不同）= {n_true} 条")
print("  若两个叶子的 external_labels 完全相同（比如都写 cluster=prod），")
print("  则联邦后 leaf-a 与 leaf-b 的数据除 source_cluster 外完全一致 -> 重复数据")
print("  而 source_cluster 是我为了对照额外加的，真实配置里通常没有 -> 真冲突")
