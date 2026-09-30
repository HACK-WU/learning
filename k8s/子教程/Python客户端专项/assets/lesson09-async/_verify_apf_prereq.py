"""核验：造真 429 的 APF 方案前提条件

⚠️ 本脚本**只读**，只做环境勘察（kubectl get / api 只读调用），
   绝不 apply / patch / delete 任何资源。改集群需用户明确授权。

要验证的前提（决定方案选 A 还是 B）：
  P1. catch-all 是否 Reject 型、nominal 并发多少
  P2. 现有 FlowSchema 的 matchingPrecedence 分布（新 FS 该插在哪）
  P3. 测试用身份（SA / user）能否被 FlowSchema 精确匹配
  P4. distinguishingMethod 支持哪些（ByUser / ByNamespace / ByVerb）
  P5. 当前是否有同名 FS/PL 冲突
"""
import asyncio
import os
import subprocess
import sys

KUBECONFIG = os.path.expanduser("~/.kube/config")


def sh(cmd, timeout=60):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True,
                       timeout=timeout,
                       env={**os.environ, "KUBECONFIG": KUBECONFIG})
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def section(t):
    print()
    print("=" * 62)
    print(t)
    print("=" * 62)


def main():
    section("P0. 集群连通性")
    rc, out = sh("kubectl cluster-info --request-timeout=15s")
    print(out.strip()[:400])
    if rc != 0:
        print("集群不可达，后续跳过")
        return

    section("P1. PriorityLevel 的 limitResponse（谁会 Reject）")
    rc, out = sh(
        "kubectl get --raw /apis/flowcontrol.apiserver.k8s.io/v1 "
        "-o json 2>/dev/null | head -c 200 || true")
    rc, out = sh(
        "kubectl get prioritylevelconfigurations -o custom-columns="
        "NAME:.metadata.name,TYPE:.spec.limitResponse.type,"
        "NOMINAL:.spec.limitResponse.queuing,omitempty "
        "--no-headers 2>&1 | head -20")
    print(out.strip() or "(空)")

    print()
    print("--- catch-all 详情 ---")
    rc, out = sh("kubectl get prioritylevelconfigurations catch-all -o yaml "
                 "2>&1 | grep -A6 'limitResponse'")
    print(out.strip() or "(取不到)")

    section("P2. FlowSchema 优先级分布（新 FS 该插在哪）")
    rc, out = sh(
        "kubectl get flowschemas -o custom-columns="
        "NAME:.metadata.name,PRECEDENCE:.spec.matchingPrecedence,"
        "PL:.spec.priorityLevelConfiguration.name --no-headers "
        "2>&1 | sort -k2 -n | head -25")
    print(out.strip() or "(空)")

    section("P3. 身份匹配可行性")
    print("--- 当前上下文身份 ---")
    rc, out = sh("kubectl auth whoami 2>&1 | head -12")
    print(out.strip()[:500] or "(auth whoami 不可用，尝试其他方式)")
    if "whoami" in out and "error" in out.lower():
        rc, out = sh("kubectl config view --minify -o jsonpath="
                     "'{.contexts[0].context.user}' 2>&1")
        print("当前 user:", out.strip())

    print()
    print("--- 现有 ServiceAccount（可作为测试身份）---")
    rc, out = sh("kubectl get sa -n default --no-headers 2>&1 | head -10")
    print(out.strip() or "(无)")

    section("P4. 已有 FS 的 distinguishingMethod 用法参考")
    rc, out = sh(
        "kubectl get flowschema -o json 2>/dev/null | "
        "python3 -c \"import sys,json;d=json.load(sys.stdin);"
        "[print(i['metadata']['name'],'->',"
        "(i['spec'].get('distinguisherMethod') or {}).get('type','(none)')) "
        "for i in d['items']]\" 2>&1 | head -15")
    print(out.strip() or "(解析失败)")

    section("P5. 目标名是否已被占用")
    for n in ("test-429-reject", "reject-low", "429-demo"):
        rc, out = sh(f"kubectl get flowschema {n} -o name 2>&1")
        exists = rc == 0 and n in out
        print(f"  flowschema/{n:16s}: {'已存在 ⚠️ 需换名' if exists else '可用 ✓'}")
    for n in ("test-reject-pl", "reject-low"):
        rc, out = sh(f"kubectl get prioritylevelconfiguration {n} -o name 2>&1")
        exists = rc == 0 and n in out
        print(f"  prioritylevel/{n:15s}: {'已存在 ⚠️ 需换名' if exists else '可用 ✓'}")

    section("P6. APF 是否真的生效（未被 --enable-priority-and-fairness=false 关掉）")
    rc, out = sh("kubectl get --raw /debug/api_priority_and_fairness/"
                 "dump_priority_levels 2>&1 | head -20")
    print(out.strip()[:600] or "(取不到，可能未开启 debug 端点)")

    print()
    print("=" * 62)
    print("勘察完毕 —— 全程只读，未做任何变更")
    print("=" * 62)


if __name__ == "__main__":
    main()
