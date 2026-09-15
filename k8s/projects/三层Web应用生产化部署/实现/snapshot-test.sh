#!/usr/bin/env bash
# ============================================================
# 卷快照与恢复验证 —— 完整生命周期实测
#
# 前置：需先安装 hostpath CSI 驱动 + snapshot-controller
#       （见 install-csi-snapshot.sh）
#
# 验证链路：写数据 → 打快照 → 删除数据 → 从快照恢复 → 验证数据回来
# 这是「快照能用」的唯一硬证据 —— 必须真删数据再恢复
#
# 用法： bash snapshot-test.sh
# 清理：脚本结束自动删除测试命名空间
# ============================================================
set -u
NS=snapshot-test

echo "=== 0. 准备测试命名空间 ==="
kubectl create ns $NS 2>&1 | tail -1

echo ""
echo "=== 1. 建 PVC（hostpath CSI）==="
cat <<'EOF' | kubectl apply -f - 2>&1
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: hp-pvc
  namespace: snapshot-test
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: csi-hostpath-sc
  resources:
    requests:
      storage: 128Mi
EOF

echo ""
echo "=== 2. 建写数据的 Pod ==="
cat <<'EOF' | kubectl apply -f - 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: data-writer
  namespace: snapshot-test
spec:
  containers:
  - name: c
    image: python:3.12-slim
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: hp-pvc
EOF

kubectl -n $NS wait --for=condition=Ready pod/data-writer --timeout=180s 2>&1

echo ""
echo "=== 3. 写入关键数据 ==="
kubectl -n $NS exec data-writer -- sh -c \
  'echo "BEFORE-SNAPSHOT-2026" > /data/proof.txt; sync; cat /data/proof.txt' 2>&1

echo ""
echo "=== 4. 打快照 ==="
cat <<'EOF' | kubectl apply -f - 2>&1
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: hp-snapshot
  namespace: snapshot-test
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: hp-pvc
EOF

for i in $(seq 1 30); do
  READY=$(kubectl -n $NS get volumesnapshot hp-snapshot -o jsonpath='{.status.readyToUse}' 2>/dev/null)
  echo "  [$i] readyToUse=$READY"
  [ "$READY" = "true" ] && break
  sleep 3
done

kubectl -n $NS get volumesnapshot hp-snapshot 2>&1
echo ""
echo "--- 对应的 VolumeSnapshotContent ---"
kubectl get volumesnapshotcontent 2>&1

echo ""
echo "=== 5. 毁灭性破坏：删除数据 ==="
kubectl -n $NS exec data-writer -- sh -c 'rm -f /data/proof.txt' 2>&1
kubectl -n $NS exec data-writer -- sh -c 'cat /data/proof.txt 2>&1 || echo "PROOF_FILE_GONE"' 2>&1

echo ""
echo "=== 6. 从快照恢复为新 PVC ==="
cat <<'EOF' | kubectl apply -f - 2>&1
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: hp-pvc-restored
  namespace: snapshot-test
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: csi-hostpath-sc
  resources:
    requests:
      storage: 128Mi
  dataSource:
    name: hp-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF

echo ""
echo "=== 7. 挂载恢复卷，验证数据 ==="
cat <<'EOF' | kubectl apply -f - 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: data-verifier
  namespace: snapshot-test
spec:
  containers:
  - name: c
    image: python:3.12-slim
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: hp-pvc-restored
EOF

kubectl -n $NS wait --for=condition=Ready pod/data-verifier --timeout=180s 2>&1
echo ""
echo "--- 恢复卷内容（决定性证据）---"
kubectl -n $NS exec data-verifier -- sh -c 'cat /data/proof.txt' 2>&1

echo ""
echo "=== 8. 清理 ==="
kubectl -n $NS delete pod data-writer data-verifier --wait=false 2>&1
kubectl -n $NS delete pvc hp-pvc hp-pvc-restored --wait=false 2>&1
kubectl -n $NS delete volumesnapshot hp-snapshot --wait=false 2>&1
kubectl delete ns $NS --wait=false 2>&1
echo "已清理（异步）"
