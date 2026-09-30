"""核验：4.4 新增章节的链接、与既有结论是否矛盾、脚本未改环境

重点按铁律自查：新增内容必须回读核验，不能凭记忆写。
"""
import io
import os
import re
import subprocess
import sys

SUBROOT = os.path.abspath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", ".."))
LESSON = os.path.join(SUBROOT, "lessons",
                      "lesson-09-async-异步三个未实测项.md")
SCRIPT = os.path.join(SUBROOT, "assets", "lesson09-async",
                      "_verify_apf_prereq.py")


def main():
    with io.open(LESSON, encoding="utf-8") as f:
        text = f.read()
    lines = text.splitlines()

    print("=== 1. 新增章节存在 ===")
    print("  4.4 标题:", "✓" if "4.4 附：亲手造出真 429 的 APF 方案" in text else "✗")
    print("  未执行标注:", "✓" if "⚠️ 未执行，仅记录" in text else "✗")
    idx = text.find("### 4.4.1")
    end = text.find("## 第五部分")
    sec = text[idx:end] if idx >= 0 else ""
    print(f"  章节行数: {len(sec.splitlines())}")

    print()
    print("=== 2. 新增部分的链接 ===")
    links = re.findall(r"\[([^\]]+)\]\(([^)]+)\)", sec)
    local = [(t, u) for t, u in links if not u.startswith(("http", "#"))]
    miss = []
    for t, u in local:
        p = os.path.normpath(os.path.join(SUBROOT, "lessons", u.split("#")[0]))
        if not os.path.exists(p):
            miss.append((t, u))
    print(f"  本地链接 {len(local)} 条, 缺失 {len(miss)}")
    for t, u in miss:
        print(f"    MISS [{t}]({u})")

    print()
    print("=== 3. 与既有结论一致性（回读核验）===")
    # 4.3 说 global-default 是 Queue、catch-all 是 Reject
    claims = [
        ("catch-all 为 Reject 型", "Reject" in text),
        ("global-default 为 Queue 型", "Queue 型" in text),
        ("未实测标注仍在", "未经真实验证" in text),
        ("4.3 结论未被改写",
         "在本机 kind 集群上，客户端可打出的量级下无法触发 429" in text),
    ]
    for c, ok in claims:
        print(f"  {c:28s}: {'✓' if ok else '✗'}")

    # 数字核对：方案里的 precedence 值是否与勘察输出一致
    print()
    print("=== 4. 方案数字 vs 勘察实值 ===")
    pairs = [("9500", "方案 precedence"),
             ("9900", "global-default precedence"),
             ("9000", "service-accounts precedence"),
             ("10000", "catch-all precedence"),
             ("5", "catch-all nominal")]
    for v, d in pairs:
        print(f"  {v:6s} ({d}): 讲义{'✓' if v in sec else '✗'}")

    print()
    print("=== 5. 勘察脚本未改环境（静态检查）===")
    with io.open(SCRIPT, encoding="utf-8") as f:
        sc = f.read()
    bad = [w for w in ("apply", "patch", "delete", "create", "replace", "edit")
           if re.search(rf"kubectl\s+{w}\b", sc)]
    print(f"  变更类 kubectl 子命令: {bad if bad else '无 ✓'}")
    print(f"  仅 get/raw/auth/cluster-info: "
          f"{'✓' if not bad and 'kubectl get' in sc else '需确认'}")
    print(f"  脚本头标注只读: {'✓' if '只读' in sc else '✗'}")

    print()
    print("=== 6. 集群未被改动（实时复核）===")
    # 🚨 修正（2026-09-29，第 10 次测法错误）：
    # 原判定 `name in out` 会误报——kubectl 的 NotFound 错误文本里
    # 也含资源名，如：
    #   Error from server (NotFound): flowschemas... "test-429-reject" not found
    # 必须用 (returncode == 0 and "NotFound" not in out) 判定。
    env = {**os.environ, "KUBECONFIG": os.path.expanduser("~/.kube/config")}

    def exists(kind, name):
        r = subprocess.run(f"kubectl get {kind} {name} -o name 2>&1",
                           shell=True, capture_output=True, text=True, env=env)
        out = (r.stdout or "") + (r.stderr or "")
        return r.returncode == 0 and "NotFound" not in out

    created = exists("flowschema", "test-429-reject")
    print(f"  flowschema/test-429-reject 是否已创建: "
          f"{'✗ 已被创建（不该发生）' if created else '否 ✓ 未改动集群'}")
    created2 = exists("prioritylevelconfiguration", "test-reject-pl")
    print(f"  prioritylevel/test-reject-pl 是否已创建: "
          f"{'✗ 已被创建（不该发生）' if created2 else '否 ✓ 未改动集群'}")

    print()
    print("=== 7. 全文规模 ===")
    print(f"  总行数: {len(lines)}")


if __name__ == "__main__":
    main()
