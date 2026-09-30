"""复核告警：test-429-reject / test-reject-pl 是否真的被创建了

上一轮核验报"已被创建"，但这与"全程只读"矛盾。
按铁律：数字/结论可疑时先怀疑核验方法本身。

可能的误报来源：
  H1. kubectl 输出的是错误信息（含资源名），我的 in 判断把错误当成功
      例如: Error from server (NotFound): flowschemas... "test-429-reject" not found
      → 字符串里含 test-429-reject，被误判为"已创建"
  H2. 真的被创建了（极不可能，但必须排查）
"""
import os
import subprocess
import sys

KUBECONFIG = os.path.expanduser("~/.kube/config")
ENV = {**os.environ, "KUBECONFIG": KUBECONFIG}


def sh(cmd):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True,
                       env=ENV, timeout=60)
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def probe(kind, name):
    print(f"--- {kind}/{name} ---")
    rc, out = sh(f"kubectl get {kind} {name} -o name 2>&1")
    print(f"  returncode = {rc}")
    print(f"  raw output = {out.strip()!r}")
    # 正确判定：看 returncode + 是否含 NotFound
    really = (rc == 0) and ("NotFound" not in out)
    print(f"  真实存在   = {really}")
    print(f"  上一轮误判 = {name in out}  ← 若此项为 True 而真实存在为 False，"
          f"则确属 H1 误报")
    return really


def main():
    print("=== 逐个复核 ===")
    a = probe("flowschema", "test-429-reject")
    print()
    b = probe("prioritylevelconfiguration", "test-reject-pl")

    print()
    print("=== 权威清单：列出全部 FS / PL ===")
    rc, out = sh("kubectl get flowschema -o name 2>&1")
    fs = [l for l in out.splitlines() if l.startswith("flowschema.")]
    print(f"  实际 FlowSchema 共 {len(fs)} 个")
    hit = [x for x in fs if "test-429" in x or "reject" in x]
    print(f"  含 test-429/reject 的: {hit if hit else '无 ✓'}")

    rc, out = sh("kubectl get prioritylevelconfiguration -o name 2>&1")
    pl = [l for l in out.splitlines() if l.startswith("prioritylevelconfiguration.")]
    print(f"  实际 PriorityLevel 共 {len(pl)} 个")
    hit2 = [x for x in pl if "test-reject" in x or "reject" in x]
    print(f"  含 test-reject/reject 的: {hit2 if hit2 else '无 ✓'}")

    print()
    print("=== 结论 ===")
    if not a and not b and not hit and not hit2:
        print("  ✓ 集群未被改动，上一轮为 H1 误报（kubectl NotFound 错误含资源名）")
    else:
        print("  ✗ 确实被创建了，需立即回退")


if __name__ == "__main__":
    main()
