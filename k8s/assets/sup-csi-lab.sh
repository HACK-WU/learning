#!/usr/bin/env bash
NS=csilab
cleanup() { kubectl delete ns $NS --ignore-not-found >/dev/null 2>&1; }
trap cleanup EXIT

echo "===== 0. 确认 CSI 驱动就绪 ====="
kubectl rollout status statefulset/csi-hostpathplugin -n default --timeout=180s 2>&1 | tail -1
kubectl get csidriver hostpath.csi.k8s.io -o jsonpath='  driverInfo: attachRequired={.spec.attachRequired} podInfoOnMount={.spec.podInfoOnMount} volumeLifecycleModes={.spec.volumeLifecycleModes}{"\n"}'
echo -n "  CSINode 注册的驱动: "
kubectl get csinode k8s-c1-control-plane -o jsonpath='{range .spec.drivers[*]}{.name}{" "}{end}{"\n"}'

kubectl create ns $NS >/dev/null 2>&1

echo
echo "===== 1. 创建 StorageClass（hostpath CSI）====="
cat <<'EOF' | kubectl apply -f - 2>&1
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: csi-hostpath-sc
provisioner: hostpath.csi.k8s.io
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF
kubectl get sc csi-hostpath-sc --no-headers

echo
echo "===== 2. 创建 PVC（动态供给）====="
cat <<'EOF' | kubectl apply -n $NS -f - 2>&1
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: csi-pvc
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: csi-hostpath-sc
  resources:
    requests:
      storage: 1Gi
EOF
echo "  --- 建 PVC 后立刻看 PV（WaitForFirstConsumer 应该还没有 PV）---"
sleep 3
echo -n "    PV 数量: "; kubectl get pv --no-headers 2>/dev/null | wc -l
echo -n "    PVC 状态: "; kubectl get pvc csi-pvc -n $NS --no-headers -o custom-columns='STATUS:.status.phase' 2>/dev/null

echo
echo "===== 3. 起 Pod 消费 PVC（触发真正供给）====="
cat <<'EOF' | kubectl apply -n $NS -f - 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: csi-app
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh","-c","echo hello-csi > /data/greeting.txt; sync; sleep 3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: csi-pvc
EOF
kubectl wait --for=condition=Ready pod/csi-app -n $NS --timeout=180s 2>&1 | tail -1

echo
echo "===== 4. 验收：PV 已由 CSI 动态创建 ====="
kubectl get pvc csi-pvc -n $NS --no-headers -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,CAP:.status.capacity.storage,SC:.spec.storageClassName' 2>/dev/null
PV=$(kubectl get pvc csi-pvc -n $NS -o jsonpath='{.spec.volumeName}' 2>/dev/null)
echo "  PV 名: $PV"
kubectl get pv $PV --no-headers -o custom-columns='CAP:.spec.capacity.storage,RECLAIM:.spec.persistentVolumeReclaimPolicy,CSI-DRIVER:.spec.csi.driver,VOLHANDLE:.spec.csi.volumeHandle' 2>/dev/null
echo -n "  PV 的 volumeAttributes: "; kubectl get pv $PV -o jsonpath='{.spec.csi.volumeAttributes}{"\n"}' 2>/dev/null

echo
echo "===== 5. 验收：数据真的写进卷了 ====="
kubectl exec csi-app -n $NS -- cat /data/greeting.txt 2>&1
echo -n "  挂载点文件系统: "; kubectl exec csi-app -n $NS -- df -h /data 2>/dev/null | tail -1

echo
echo "===== 6. 卷快照（课20 唯一缺实测的知识点）====="
cat <<'EOF' | kubectl apply -n $NS -f - 2>&1
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: csi-snap
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: csi-pvc
EOF
kubectl wait --for=jsonpath='{.status.readyToUse}'=true volumesnapshot/csi-snap -n $NS --timeout=120s 2>&1 | tail -1
kubectl get volumesnapshot csi-snap -n $NS --no-headers -o custom-columns='NAME:.metadata.name,READY:.status.readyToUse,RESTORE-SIZE:.status.restoreSize,SNAPCONTENT:.status.boundVolumeSnapshotContentName' 2>/dev/null

echo
echo "===== 7. 从快照恢复出新 PVC ====="
cat <<'EOF' | kubectl apply -n $NS -f - 2>&1
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: csi-pvc-restore
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: csi-hostpath-sc
  resources:
    requests:
      storage: 1Gi
  dataSource:
    kind: VolumeSnapshot
    name: csi-snap
    apiGroup: snapshot.storage.k8s.io
EOF
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/csi-pvc-restore -n $NS --timeout=120s 2>&1 | tail -1
cat <<'EOF' | kubectl apply -n $NS -f - 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: csi-restore-check
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh","-c","sleep 600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: csi-pvc-restore
EOF
kubectl wait --for=condition=Ready pod/csi-restore-check -n $NS --timeout=120s 2>&1 | tail -1
echo -n "  从快照恢复出的卷里的内容: "; kubectl exec csi-restore-check -n $NS -- cat /data/greeting.txt 2>&1

echo
echo "===== 8. 卷扩容（1Gi -> 2Gi）====="
kubectl patch pvc csi-pvc -n $NS --type merge -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}' 2>&1
sleep 12
kubectl get pvc csi-pvc -n $NS --no-headers -o custom-columns='REQ:.spec.resources.requests.storage,CAP:.status.capacity.storage,COND:.status.conditions[0].type' 2>/dev/null
echo -n "  Pod 内看到的容量: "; kubectl exec csi-app -n $NS -- df -h /data 2>/dev/null | tail -1
