#!/usr/bin/env bash
# 课 5 取证脚本：对象总表（上）——工作负载 · 配置 · 存储
# 用途：验证课 5 讲义里每一份 YAML 都能真实 apply 成功（硬承诺的落地证据）。
# 写操作隔离在一次性命名空间 obj5-lab，结束即删除并断言零残留。
set -u
NS=obj5-lab
PASS=0; FAIL=0
kubectl create namespace "$NS" 2>&1 | tail -1

check() { # $1=描述 $2=期望关键字 $3=实际输出
  if echo "$3" | grep -qi "$2"; then echo "  ✅ $1"; PASS=$((PASS+1));
  else echo "  ❌ $1 —— 实际：$3"; FAIL=$((FAIL+1)); fi
}

apply() { # $1=标识 $2=yaml
  OUT=$(echo "$2" | kubectl apply -f - 2>&1 | tail -1)
  check "$1" "created\|configured\|unchanged" "$OUT"
}

echo "===== A. Pod 与直接管理者 ====="
apply "Pod" "apiVersion: v1
kind: Pod
metadata: {name: t-pod, namespace: $NS}
spec:
  containers: [{name: c, image: nginx:alpine, imagePullPolicy: IfNotPresent}]"

apply "ReplicaSet" "apiVersion: apps/v1
kind: ReplicaSet
metadata: {name: t-rs, namespace: $NS}
spec:
  replicas: 2
  selector: {matchLabels: {app: t-rs}}
  template:
    metadata: {labels: {app: t-rs}}
    spec: {containers: [{name: c, image: nginx:alpine, imagePullPolicy: IfNotPresent}]}"

apply "Deployment" "apiVersion: apps/v1
kind: Deployment
metadata: {name: t-deploy, namespace: $NS}
spec:
  replicas: 2
  selector: {matchLabels: {app: t-deploy}}
  template:
    metadata: {labels: {app: t-deploy}}
    spec: {containers: [{name: c, image: nginx:alpine, imagePullPolicy: IfNotPresent}]}"

echo "===== B. 其余工作负载 ====="
apply "StatefulSet" "apiVersion: apps/v1
kind: StatefulSet
metadata: {name: t-sts, namespace: $NS}
spec:
  serviceName: t-sts-svc
  replicas: 2
  selector: {matchLabels: {app: t-sts}}
  template:
    metadata: {labels: {app: t-sts}}
    spec: {containers: [{name: c, image: nginx:alpine, imagePullPolicy: IfNotPresent}]}"

apply "DaemonSet" "apiVersion: apps/v1
kind: DaemonSet
metadata: {name: t-ds, namespace: $NS}
spec:
  selector: {matchLabels: {app: t-ds}}
  template:
    metadata: {labels: {app: t-ds}}
    spec: {containers: [{name: c, image: nginx:alpine, imagePullPolicy: IfNotPresent}]}"

apply "Job" "apiVersion: batch/v1
kind: Job
metadata: {name: t-job, namespace: $NS}
spec:
  template:
    spec:
      restartPolicy: Never
      containers: [{name: c, image: busybox:1.36, command: [sh, -c, 'echo done'], imagePullPolicy: IfNotPresent}]"

apply "CronJob" "apiVersion: batch/v1
kind: CronJob
metadata: {name: t-cronjob, namespace: $NS}
spec:
  schedule: '*/5 * * * *'
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          containers: [{name: c, image: busybox:1.36, command: [sh, -c, 'echo hi'], imagePullPolicy: IfNotPresent}]"

echo "===== C. 配置与存储 ====="
apply "ConfigMap" "apiVersion: v1
kind: ConfigMap
metadata: {name: t-cm, namespace: $NS}
data: {key: value}"

apply "Secret" "apiVersion: v1
kind: Secret
metadata: {name: t-secret, namespace: $NS}
type: Opaque
stringData: {username: exampleuser}"

apply "PVC" "apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: t-pvc, namespace: $NS}
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 64Mi}}"

apply "StorageClass(集群级)" "apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: {name: t-sc}
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer"

apply "PV(集群级)" "apiVersion: v1
kind: PersistentVolume
metadata: {name: t-pv}
spec:
  capacity: {storage: 64Mi}
  accessModes: [ReadWriteOnce]
  hostPath: {path: /tmp/t-pv-data}
  storageClassName: t-sc"

echo "===== D. 关键取证：谁管谁（ownerReference）====="
sleep 10
for K in deploy rs sts ds job cronjob; do
  echo "--- $K 列表 ---"
  kubectl get $K -n "$NS" --no-headers 2>&1 | head -2
done

echo "--- Deployment 生成的 Pod 认谁做爹 ---"
P=$(kubectl get pod -n "$NS" -l app=t-deploy --no-headers 2>/dev/null | head -1 | awk '{print $1}')
[ -n "$P" ] && kubectl get pod "$P" -n "$NS" -o jsonpath='owner={.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}'; echo

echo "--- StatefulSet 生成的 Pod 认谁做爹（应直接是 StatefulSet）---"
P2=$(kubectl get pod -n "$NS" -l app=t-sts --no-headers 2>/dev/null | head -1 | awk '{print $1}')
[ -n "$P2" ] && kubectl get pod "$P2" -n "$NS" -o jsonpath='owner={.metadata.ownerReferences[0].kind}'; echo

echo "--- CronJob → Job 的两跳链 ---"
kubectl get job -n "$NS" --no-headers 2>&1 | head -2

echo "--- PVC 状态（Pending 说明在等 PV 或 StorageClass）---"
kubectl get pvc t-pvc -n "$NS" --no-headers 2>&1 | head -1

echo
echo "===== 统计 ====="
echo "PASS=$PASS  FAIL=$FAIL"

echo
echo "===== 清理 ====="
kubectl delete namespace "$NS" 2>&1 | tail -1
kubectl delete pv t-pv 2>&1 | tail -1
kubectl delete sc t-sc 2>&1 | tail -1
kubectl get ns "$NS" 2>&1 | tail -1
