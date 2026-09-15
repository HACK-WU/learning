#!/usr/bin/env bash
# ============================================================
# 安装 hostpath CSI 驱动 + snapshot 组件（启用卷快照能力）
#
# ⚠️ 两个实测踩坑（不按此做会静默失败）：
#
# 坑 1：清单文件名带连字符
#        是 csi-hostpath-plugin.yaml，不是 csi-hostpathplugin.yaml
#        新版把 RBAC 和全部 sidecar 合并进了这一个文件
#
# 坑 2：csi-hostpath-plugin.yaml 只建 ClusterRoleBinding，
#        不建 ClusterRole！sidecar 会一直报
#        "external-provisioner-runner not found" 而静默不工作，
#        表现为 PVC 永远 Pending 且无 FailedScheduling 事件
#        → 必须另行创建 5 个 ClusterRole（本脚本已处理）
#
# 用法： bash install-csi-snapshot.sh
# ============================================================
set -u
SNAP=https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master
HP=https://raw.githubusercontent.com/kubernetes-csi/csi-driver-host-path/master/deploy/kubernetes-1.34/hostpath

echo "=== 1. 安装 VolumeSnapshot CRD ==="
for f in snapshot.storage.k8s.io_volumesnapshotclasses.yaml \
         snapshot.storage.k8s.io_volumesnapshotcontents.yaml \
         snapshot.storage.k8s.io_volumesnapshots.yaml; do
  kubectl apply -f "$SNAP/client/config/crd/$f" 2>&1
done

echo ""
echo "=== 2. 安装 snapshot-controller ==="
kubectl apply -f "$SNAP/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml" 2>&1
kubectl apply -f "$SNAP/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml" 2>&1
kubectl -n kube-system rollout status deploy/snapshot-controller --timeout=180s 2>&1

echo ""
echo "=== 3. 安装 hostpath CSI 驱动 ==="
kubectl apply -f "$HP/csi-hostpath-driverinfo.yaml" 2>&1
kubectl apply -f "$HP/csi-hostpath-plugin.yaml" 2>&1 | tail -3

echo ""
echo "=== 4. 补齐缺失的 ClusterRole（官方清单没给！）==="
# csi-snapshotter 的 role 由 external-snapshotter 仓库提供
kubectl apply -f "$SNAP/deploy/kubernetes/csi-snapshotter/rbac-csi-snapshotter.yaml" 2>&1

# 其余 4 个 role 需自建
cat <<'EOF' | kubectl apply -f - 2>&1
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-provisioner-runner
rules:
- apiGroups: [""]
  resources: ["persistentvolumes"]
  verbs: ["get", "list", "watch", "create", "delete", "patch", "update"]
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["get", "list", "watch", "update", "patch"]
- apiGroups: ["storage.k8s.io"]
  resources: ["storageclasses"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["list", "watch", "create", "update", "patch"]
- apiGroups: ["snapshot.storage.k8s.io"]
  resources: ["volumesnapshots", "volumesnapshotcontents"]
  verbs: ["get", "list"]
- apiGroups: ["storage.k8s.io"]
  resources: ["csinodes", "volumeattachments", "volumeattributesclasses"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["storage.k8s.io"]
  resources: ["volumeattachments"]
  verbs: ["patch"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-attacher-runner
rules:
- apiGroups: [""]
  resources: ["events", "persistentvolumes"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
- apiGroups: ["storage.k8s.io"]
  resources: ["volumeattachments", "csinodes"]
  verbs: ["get", "list", "watch", "patch", "update"]
- apiGroups: ["storage.k8s.io"]
  resources: ["volumeattachments/status"]
  verbs: ["patch"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-resizer-runner
rules:
- apiGroups: [""]
  resources: ["persistentvolumes"]
  verbs: ["get", "list", "watch", "patch", "update"]
- apiGroups: [""]
  resources: ["persistentvolumeclaims", "pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["persistentvolumeclaims/status"]
  verbs: ["patch"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["list", "watch", "create", "update", "patch"]
- apiGroups: ["storage.k8s.io"]
  resources: ["storageclasses"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-snapshot-metadata-runner
rules:
- apiGroups: ["snapshot.storage.k8s.io"]
  resources: ["volumesnapshots", "volumesnapshotcontents"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["groupsnapshot.storage.k8s.io"]
  resources: ["volumegroupsnapshots"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["list", "watch", "create", "update", "patch"]
EOF

echo ""
echo "=== 5. 重启驱动让 sidecar 重建 watch ==="
kubectl -n default rollout restart sts/csi-hostpathplugin 2>&1
kubectl -n default rollout status sts/csi-hostpathplugin --timeout=240s 2>&1

echo ""
echo "=== 6. 建 StorageClass 与 VolumeSnapshotClass ==="
cat <<'EOF' | kubectl apply -f - 2>&1
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: csi-hostpath-sc
provisioner: hostpath.csi.k8s.io
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: csi-hostpath-snapclass
driver: hostpath.csi.k8s.io
deletionPolicy: Delete
EOF

echo ""
echo "=== 7. 验证 ==="
echo "--- CSIDriver ---"
kubectl get csidriver 2>&1
echo "--- CSI 节点注册 ---"
kubectl get csinode -o jsonpath='{range .items[*]}{.metadata.name}{" drivers="}{range .spec.drivers[*]}{.name}{" "}{end}{"\n"}{end}' 2>&1
echo "--- 5 个 ClusterRole ---"
for r in external-provisioner-runner external-attacher-runner external-resizer-runner external-snapshotter-runner external-snapshot-metadata-runner; do
  kubectl get clusterrole "$r" -o jsonpath='{.metadata.name}{"\n"}' 2>&1 || echo "MISSING: $r"
done
echo "--- CRD ---"
kubectl get crd 2>&1 | grep -i volumesnapshot
