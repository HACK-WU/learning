# 蓝鲸 7.2 部署踩坑记录

> 记录范围：`base-storage` → `seq=first` → `seq=second` 全流程
> 记录原则：**每条坑都要有现场证据 + 可复现的解法**，不写"据说""应该"
> 环境：kind 3 节点（1 control-plane + 2 worker），ingress-nginx 1.13.2，helmfile 部署

---

## 坑 1：镜像拉取极慢，helm 超时失败

**现象**

`helm upgrade` 报 `context deadline exceeded`，Pod 卡在 `ImagePullBackOff`。

**现场证据**

```text
Pulling from OCI Registry (hub.bktencent.com/bitnami/elasticsearch:7.16.2-debian-10-r0)
elapsed: 2292.0s  total: 521.7  (233.1 KiB/s)
```

单连接稳定在 **120~450 KiB/s**，一个 300MB 镜像要 10~40 分钟。

**根因**

不是带宽不够，是 **registry 对单连接限速**。实测：
- 单连接：~120 KiB/s
- 节点内多进程并发：总吞吐线性增长（3 节点并行可达 ~900 KiB/s）

**解法：预拉镜像到节点**

部署前先把该批次镜像全拉到节点，Pod 起来时直接命中缓存，秒起。

```bash
# 1. 渲染出本批次镜像清单
helmfile -f base-blueking.yaml.gotmpl -l seq=third template 2>/dev/null \
  | grep -oE 'image: "?[^ "]+' | sed -E 's/image: "?//' | tr -d '"' | sort -u > /tmp/imgs.txt

# 2. 并行拉到三个节点（节点间并行、节点内串行）
docker exec <node> ctr -n k8s.io images pull <img>
```

脚本：[prefetch-images.sh](/mnt/d/projects/learning/bk-blueking-72/assets/prefetch-images.sh)、[prefetch-pull-v2.sh](/mnt/d/projects/learning/bk-blueking-72/assets/prefetch-pull-v2.sh)

**配套：加大 helmfile timeout**

600s 根本等不完大镜像。改法见坑 2。

---

## 坑 2：helmfile timeout 到底是哪里配的

**我犯的错（重要）**

第一轮我判断"chart 内层 600s 覆盖了外层 `--args` 透传的 timeout"。**这是错的**。

**核验后的事实**

```bash
grep -n 'timeout' /root/bk72/install/blueking/defaults.yaml
# 14:  timeout: 600    <-- 真凶，helmfile 自己的 helmDefaults
```

`--timeout` 是 **helm 的参数**，helmfile 通过 `helmDefaults.timeout` 传给它，单位是秒。

| 位置 | 原值 | 改后 | 作用范围 |
|---|---|---|---|
| `defaults.yaml:14` | 600 | 1800 | 全局 helmDefaults |
| `base-blueking.yaml.gotmpl:142,154` | 900 | 1800 | bkpaas-app-operator、bk-paas |

**正确修法**

```bash
cp defaults.yaml defaults.yaml.bak-$(date +%Y%m%d-%H%M%S)
sed -i 's/^  timeout: 600$/  timeout: 1800/' defaults.yaml
sed -i 's/^    timeout: 900$/    timeout: 1800/' base-blueking.yaml.gotmpl
```

**教训**：区分"是谁的参数"。helmfile 参数、helm 参数、chart values 是三回事，改错地方等于没改。

**反例**：`helmfile -l seq=x sync --timeout=1800s` 是**无效**的，helmfile 没有这个参数，要用 `--args="--timeout=1800s"` 透传（但会被 helmDefaults 覆盖，所以直接改文件最干净）。

---

## 坑 3：判断脚本成功与否，别信日志 grep

**现象**

预拉脚本输出一堆 ❌，但最后校验发现镜像其实在位。

**根因（两层）**

第一层：`ctr` 进度输出会**截断镜像名**，用 `ctr pull | tail -2 | grep <镜像名>` 判断成功，明明成功却判失败。

第二层：子 shell 并发写 stdout 导致**报告错位**，A 节点的结果被标到 B 节点头上。

**解法：用退出码 + 复验，不看日志**

```bash
# 错：靠日志
if docker exec $n ctr ... pull "$img" 2>&1 | tail -2 | grep -q "$img"; then

# 对：靠退出码 + 事后复验
if docker exec "$n" ctr -n k8s.io images pull "$img" >/dev/null 2>&1; then
    # 再用 images list 复验一次
    docker exec "$n" ctr -n k8s.io images list | awk '{print $1}' | grep -qx "$img"
fi
```

**这是第三次栽在"没核验就下结论"上**（前两次是 selector 失效、参数名判断）。已固化：任何"成功/失败"判定，优先用退出码或事后复验，不用日志 grep。

---

## 坑 4：重试次数不够，误判为"镜像不存在"

**现象**

脚本报 `❌ bkssm:v1.0.12`，4 次重试全失败。

**核验**

手动拉一次，看真实耗时：

```text
Pulling from OCI Registry (hub.bktencent.com/blueking/bkssm:v1.0.12)
elapsed: 746.5s  total: 226.6  (310.9 KiB/s)
saved
```

**拉成功了，只是要 12 分钟** —— 而脚本每次重试等待时间不够，被提前放弃。

**解法**

重试次数从 4 次提到 **8 次**，并在失败后 sleep 3 秒再试。改后 `bkssm` 第 2 次就成功。

**教训**：慢 ≠ 失败。在限速 registry 上，"超时"和"不存在"要分开判断，先用手动单次拉取确认镜像可达性。

---

## 坑 5：registry 401，token 拿到了也没用

**现象**

想用 API 探测镜像是否存在：

```bash
TOKEN=$(curl -s -u 'blueking:blueking' \
  'https://hub.bktencent.com/service/token?scope=repository:blueking/bkssm:pull&service=harbor-registry' \
  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
curl -H "Authorization: Bearer $TOKEN" .../manifests/v1.0.12
# HTTP 401
```

token 长度 749，拿到了，但**连已知存在的 bkiam 也 401**。

**结论**

该 registry 的鉴权方式不是标准 Harbor bearer token 流程（可能是反向代理层做了额外鉴权）。**这条路走不通，别浪费时间**。

**替代方案：直接试拉**

```bash
docker exec <node> ctr -n k8s.io images pull <img> 2>&1 | tail -5
```

看真实输出，比探测 API 可靠。

---

## 坑 6：ingress-nginx 两道关卡拦 snippet（本次最隐蔽）

**现象**

`bk-iam` 部署失败：

```text
admission webhook "validate.nginx.ingress.kubernetes.io" denied the request:
nginx.ingress.kubernetes.io/server-snippet annotation cannot be used.
Snippet directives are disabled by the Ingress administrator
```

**根因**

集群里的 ingress-nginx 是**裸装社区版**（`k8smirror/ingress-nginx-controller:v1.13.2`），ConfigMap `data: null`。ingress-nginx 1.9+ 默认**禁用** snippet 注解（安全加固）。

蓝鲸原厂设计是走 [00-ingress-nginx.yaml.gotmpl](/root/bk72/install/blueking/00-ingress-nginx.yaml.gotmpl) + 蓝鲸定制版 `bk-ingress-nginx`，那个版本默认放开。**我跳过了这一步**。

**两道关卡（关键，不是一道）**

只改第一道的话，报错会变成另一种，容易误以为"改了没用"：

```bash
# 第一道：全局开关
kubectl -n ingress-nginx patch cm ingress-nginx-controller --type merge \
  -p '{"data":{"allow-snippet-annotations":"true"}}'

# 第二道：风险分级（server-snippet 属 High 风险，需放宽到 Critical）
kubectl -n ingress-nginx patch cm ingress-nginx-controller --type merge \
  -p '{"data":{"annotations-risk-level":"Critical"}}'
```

**验证（必须真建一个 ingress 试）**

```bash
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: snippet-probe
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/server-snippet: |
      location ~* "^/metrics" { deny all; return 403; }
spec:
  ingressClassName: nginx
  rules:
  - host: probe.example.com
    http:
      paths:
      - path: / { pathType: Prefix, backend: {service:{name: snippet-probe, port:{number: 80}}} }
EOF
```

第一道后报错从 `Snippet directives are disabled` 变成 `contains risky annotation` —— **错误变了说明第一道生效了**，这是判断"改动有没有起作用"的有效信号。

**影响面**：实测 `seq=third`、`seq=fourth` 渲染出来 **0 处 snippet**，只有 `second` 批的 `bk-iam` 用。

**部署前预检**（吸取教训，别等部署时才发现）：

```bash
helmfile -f base-blueking.yaml.gotmpl -l seq=third template 2>/dev/null \
  | grep -oE 'nginx.ingress.kubernetes.io/[a-z-]*snippet[a-z-]*' | sort | uniq -c
```

脚本：[precheck-third.sh](/mnt/d/projects/learning/bk-blueking-72/assets/precheck-third.sh)

---

## 坑 7：Redis Cluster 组建死锁（探针杀死 creator）

**现象**

`bk-redis-cluster` 三个 Pod 全部 `0/1`，各自为王（`myself,master`），互不认识。

**根因**

经典的**集群组建死锁**：
1. `bk-redis-cluster-0`（creator）等待 `-2` 节点就绪
2. 但 `-2` 因 `livenessProbe` 反复被杀（重启 8 次）
3. creator 自己也被探针杀过一次（退出码 **137** = SIGKILL）
4. 组建流程中断，三个节点各自为王

**解法**

在 `-0` 上手动组建：

```bash
kubectl exec -n blueking bk-redis-cluster-0 -- \
  redis-cli --cluster create <ip0>:6379 <ip1>:6379 <ip2>:6379 \
  --cluster-replicas 0 --cluster-yes
```

**治本**：调大 `initialDelaySeconds`，否则下次重启还会复现。

**验证**：`redis-cli cluster info` 看 `cluster_state:ok` + 16384 槽全分配。

---

## 坑 8：helm 显示 failed，但 Pod 全绿

**现象**

```text
NAME          STATUS
bk-auth       failed
bk-repo       failed
bk-apigateway failed
```

但 `kubectl get pods` 全是 `Running`/`Completed`，零异常。

**根因**

`--wait` + `--timeout` 超时 → helm 把 release 标记 failed，**但 K8s 侧资源已全部创建成功**。是**超时假象，不是真失败**。

**判断标准**

不要看 `helm list` 的 STATUS，看 Pod：

```bash
kubectl get pods -n blueking --no-headers | awk '{print $3}' | sort | uniq -c
# 期望：Running + Completed，无 Pending/CrashLoopBackOff/ImagePullBackOff
```

**典型证据**：`bkiam-migrate-2` 等 Job 显示 `Completed` → 说明数据库迁移成功、依赖是通的。

---

## 速查表

| 症状 | 先查 | 解法 |
|---|---|---|
| Pod ImagePullBackOff | 镜像是否预拉到节点 | 坑 1 预拉脚本 |
| helm context deadline | `defaults.yaml` 的 timeout | 坑 2 改 1800 |
| 脚本报失败但好像成功了 | 退出码 vs 日志 | 坑 3 用退出码 |
| 某镜像"拉不到" | 手动单次拉取看真实耗时 | 坑 4 加重试次数 |
| registry API 401 | 别折腾 token | 坑 5 直接试拉 |
| ingress 创建被拒 | 两道 snippet 关卡 | 坑 6 两个 patch |
| Redis 集群不组建 | creator 是否被探针杀 | 坑 7 手动 create |
| helm failed 但 Pod 正常 | Pod 状态 | 坑 8 忽略状态标记 |

---

## 贯穿性教训

1. **慢 ≠ 失败**：限速环境下，"超时"和"不可用"必须分开判断。
2. **别信日志 grep**：判断成功与否用退出码 + 事后复验。
3. **改动有没有生效，看错误是否变化**：snippet 那两道关卡就是靠"错误信息变了"确认第一道生效的。
4. **部署前预检 > 部署时救火**：`precheck-third.sh` 一次扫完 snippet / quota / SC / 磁盘，比撞墙再查快得多。
5. **分清参数归属**：helmfile 参数、helm 参数、chart values 是三层，改错层等于白改。
