import subprocess

print("=== A) 用 --post-file（wget 从 stdin 读 body） ===")
payload = "# TYPE t1 gauge\nt1 1\n"
p = subprocess.run(
    ["docker", "exec", "-i", "prometheus", "wget", "-qO-", "--post-file=-",
     "http://pushgateway:9091/metrics/job/test-a"],
    input=payload, capture_output=True, text=True,
)
print("  exit=%s stdout=%r stderr=%r" % (p.returncode, p.stdout[:80], p.stderr[:160]))

print()
print("=== B) 用 --post-data 直接给字符串（不经过管道） ===")
p = subprocess.run(
    ["docker", "exec", "prometheus", "wget", "-qO-",
     "--post-data", "# TYPE t2 gauge\nt2 2\n",
     "http://pushgateway:9091/metrics/job/test-b"],
    capture_output=True, text=True,
)
print("  exit=%s stdout=%r stderr=%r" % (p.returncode, p.stdout[:80], p.stderr[:160]))

print()
print("=== C) 用 PUT 方法（Pushgateway 推荐方式） ===")
p = subprocess.run(
    ["docker", "exec", "prometheus", "wget", "-qO-",
     "--method=PUT", "--body-data", "# TYPE t3 gauge\nt3 3\n",
     "http://pushgateway:9091/metrics/job/test-c"],
    capture_output=True, text=True,
)
print("  exit=%s stdout=%r stderr=%r" % (p.returncode, p.stdout[:80], p.stderr[:160]))

print()
print("=== 检查推送结果 ===")
p = subprocess.run(
    ["curl", "-s", "http://localhost:9091/metrics"],
    capture_output=True, text=True,
)
for line in p.stdout.splitlines():
    if line.startswith("t1") or line.startswith("t2") or line.startswith("t3"):
        print("  " + line)
