#!/usr/bin/env python3
"""全量扫描讲义中的命令写法是否统一、可执行。

刚在第三幕抓到一个真问题：`curl http://localhost:8081/...`
  - 8081 在本机已被其他进程占用（学习档案明确记录）
  - 且与第四幕的 `docker exec l5-prom wget` 写法不一致
  - 读者照抄必失败

本脚本扫描所有命令，找出：
  1. 使用 localhost:808x 的命令（app 端口未映射到宿主，且 8081 被占）
  2. 未用 docker exec 的裸 curl/wget（在 WSL 里可能无对应工具或端口不通）
  3. 端口引用是否在 {19090, 19093} 或容器内部地址范围内
"""
import re

LESSON = ("/mnt/d/projects/learning/prometheus/stages/2-规则与告警/"
          "lessons/lesson-05-Alertmanager深入.md")
with open(LESSON, encoding="utf-8") as f:
    text = f.read()
# 评审结论块（末尾）里的引用文字不是可执行命令，需排除后再判定
tail_idx = text.find("## 🔍 本课评审结论")
body = text if tail_idx < 0 else text[:tail_idx]
lines = body.split("\n")

print("=" * 70)
print("命令写法全量扫描（已排除评审结论块中的引用文字）")
print("=" * 70)

problems = []

# 1. localhost:808x
for i, ln in enumerate(lines, 1):
    for m in re.finditer(r"localhost:(\d{4})", ln):
        port = m.group(1)
        if port.startswith("808"):
            problems.append(("P0", i, "localhost:%s（app 端口未映射宿主，"
                                       "且 8081 本机已被占用）" % port, ln.strip()[:90]))

# 2. 裸 curl —— 需判断执行位置：
#    Windows 宿主侧用 curl.exe 是合法的；WSL 内无 curl（应用 docker exec 代发）。
#    只有"既非 curl.exe、也未说明执行位置"的裸 curl 才是真问题。
for i, ln in enumerate(lines, 1):
    s = ln.strip()
    if re.match(r"^\s*curl ", s) and "docker exec" not in s:
        problems.append(("P2", i,
                         "裸 curl —— 需标明执行位置（宿主用 curl.exe，"
                         "WSL 内请改用 docker exec 代发）", s[:90]))

# 3. 端口白名单检查
allowed_host = {"19090", "19093"}
# 容器内地址（容器里 Prometheus 是 9090、Alertmanager 是 9093），属合法
allowed_container = {"9090", "9093", "8080", "8099"}
for i, ln in enumerate(lines, 1):
    for m in re.finditer(r"localhost:(\d{4,5})", ln):
        port = m.group(1)
        if port in allowed_host or port.startswith("808"):
            continue
        # 区分容器内外：docker exec 里的 localhost 指容器自身
        in_container = "docker exec" in ln
        if in_container and port in allowed_container:
            continue
        problems.append(("P1", i, "宿主端口 %s 不在 {19090,19093}" % port,
                         ln.strip()[:90]))

# 4. wget 直接调用（非 docker exec）
for i, ln in enumerate(lines, 1):
    s = ln.strip()
    if re.match(r"^\s*wget ", s) and "docker exec" not in s:
        problems.append(("P1", i, "裸 wget（应在容器内执行）", s[:90]))

if not problems:
    print("  ✅ 命令写法统一，无问题")
else:
    p0 = [p for p in problems if p[0] == "P0"]
    p1 = [p for p in problems if p[0] == "P1"]
    print("  P0: %d   P1: %d" % (len(p0), len(p1)))
    print()
    for sev, i, desc, snippet in problems:
        print("  [%s] 行%d: %s" % (sev, i, desc))
        print("       %s" % snippet)

print("=" * 70)

# 统计命令写法分布
n_exec = len(re.findall(r"docker exec", text))
print("\n命令写法统计:")
print("  docker exec 出现次数: %d" % n_exec)
print("  localhost:19090: %d" % len(re.findall(r"localhost:19090", text)))
print("  localhost:19093: %d" % len(re.findall(r"localhost:19093", text)))
