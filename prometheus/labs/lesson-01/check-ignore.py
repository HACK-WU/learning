import subprocess

targets = [
    "prometheus/stages/1-单机内核/lessons/lesson-01-架构总览与第一条数据.md",
    "prometheus/labs/lesson-01/app/demo_app.py",
    "prometheus/00-学习档案.md",
    "prometheus/02-课程目录.md",
]

for t in targets:
    p = subprocess.run(
        ["git", "-C", "/mnt/d/projects/learning", "check-ignore", "-v", t],
        capture_output=True, text=True,
    )
    status = "被忽略(!)" if p.returncode == 0 else "未被忽略(ok)"
    print("  %-64s %s" % (t, status))
    if p.returncode == 0:
        print("      规则: %s" % p.stdout.strip())
