#!/usr/bin/env python3
# 用 Python 生成 Corefile，彻底避免 shell heredoc 转义问题
# 上一版 bug：heredoc 未加引号，\\\\. 变成 \\.，Go 正则里 \\. = 字面反斜杠+任意字符
import subprocess, sys

CIP = subprocess.run(
    ["kubectl","get","svc","ingress-nginx-controller","-n","ingress-nginx",
     "-o","jsonpath={.spec.clusterIP}"],
    capture_output=True, text=True).stdout.strip()
print(f"ingress ClusterIP = {CIP}")

# Go 正则：\. 匹配字面点。这里直接写单反斜杠
corefile = f""".:53 {{
    errors
    log
    health {{
       lameduck 5s
    }}
    ready

    # 蓝鲸统一域名 -> ingress-nginx
    # 兼容 ndots:5 拼 search 域后的查询名
    template IN A {{
        match "^[^.]+\\.paas\\.example\\.com(\\.[a-z0-9-]+)*\\.?$"
        answer "{{{{ .Name }}}} 60 IN A {CIP}"
        fallthrough
    }}
    template IN A {{
        match "^[^.]+\\.example\\.com(\\.[a-z0-9-]+)*\\.?$"
        answer "{{{{ .Name }}}} 60 IN A {CIP}"
        fallthrough
    }}
    template IN A {{
        match "^(paas\\.example\\.com|example\\.com)(\\.[a-z0-9-]+)*\\.?$"
        answer "{{{{ .Name }}}} 60 IN A {CIP}"
        fallthrough
    }}

    kubernetes cluster.local in-addr.arpa ip6.arpa {{
       pods insecure
       fallthrough in-addr.arpa ip6.arpa
       ttl 30
    }}
    prometheus :9153
    forward . /etc/resolv.conf {{
       max_concurrent 1000
    }}
    cache 30 {{
       disable success cluster.local
       disable denial cluster.local
    }}
    loop
    reload
    loadbalance
}}
"""

with open("/tmp/Corefile-v4", "w") as f:
    f.write(corefile)

print("\n===== 生成的 match 规则（应为单反斜杠）=====")
for line in corefile.splitlines():
    if "match" in line:
        print("   ", line.strip())

print("\n===== 应用 =====")
r = subprocess.run(
    "kubectl create cm coredns -n kube-system --from-file=Corefile=/tmp/Corefile-v4 "
    "--dry-run=client -o yaml | kubectl apply -f -",
    shell=True, capture_output=True, text=True)
print("  ", (r.stdout + r.stderr).strip().splitlines()[-1] if (r.stdout+r.stderr).strip() else "ok")

r = subprocess.run(["kubectl","rollout","restart","deployment/coredns","-n","kube-system"],
                   capture_output=True, text=True)
print("  ", (r.stdout+r.stderr).strip())
r = subprocess.run(["kubectl","rollout","status","deployment/coredns","-n","kube-system","--timeout=90s"],
                   capture_output=True, text=True)
print("  ", (r.stdout+r.stderr).strip().splitlines()[-1] if (r.stdout+r.stderr).strip() else "")

import time
time.sleep(10)

print("\n===== 验证解析 =====")
for d in ["bkiam.paas.example.com","bkapi.paas.example.com","paas.example.com","bkrepo.example.com"]:
    r = subprocess.run(["kubectl","exec","paas3-dbg","-n","blueking","--",
                        "getent","hosts",d], capture_output=True, text=True)
    out = r.stdout.strip()
    if out:
        print(f"  OK   {d} -> {out}")
    else:
        print(f"  FAIL {d}  解析失败")

print("\n===== coredns 日志中的 example 查询 =====")
pod = subprocess.run("kubectl get pods -n kube-system --no-headers 2>/dev/null | grep dns | awk '{print $1}' | head -1",
                     shell=True, capture_output=True, text=True).stdout.strip()
subprocess.run(["kubectl","exec","paas3-dbg","-n","blueking","--",
                "getent","hosts","bkiam.paas.example.com"], capture_output=True)
time.sleep(2)
r = subprocess.run(["kubectl","logs",pod,"-n","kube-system","--tail=30"],
                   capture_output=True, text=True)
hits = [l for l in r.stdout.splitlines() if "example" in l.lower()]
for l in hits[-6:]:
    print("   ", l.strip())
if not hits:
    print("    (无 example 查询记录 —— 查询未到达 coredns)")
