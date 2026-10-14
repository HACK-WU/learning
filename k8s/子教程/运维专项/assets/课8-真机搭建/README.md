# 课 8 真机搭建取证脚本

## 这是什么

2026-10-09 运维专项课 8《真机搭建：从裸虚机到跨节点互通》的实操脚本。
在 WSL2 内用 KVM 从零搭了一套**真机双节点集群**（非 kind），按 kubeadm 官方步骤逐步取证。

这些脚本不是"教学示例"——它们当时真实跑过，讲义里的数字与结论都来自它们的输出。

## 环境

| 项目 | 值 |
|---|---|
| 宿主 | Windows 11 + WSL2 Ubuntu（内核 6.6.87.2） |
| 虚拟化 | WSL2 内 KVM，`systemd-detect-virt` = kvm |
| 虚机 | k8s-cp1(192.168.122.19) + k8s-w1(192.168.122.54)，2C/2G each |
| 节点 OS | Ubuntu 22.04.5 LTS，内核 5.15.0-198-generic |
| k8s | v1.29.15 |
| 运行时 | containerd 2.2.1 |
| CNI | Calico v3.27.3 |

## 执行顺序

| 脚本 | 做什么 |
|---|---|
| `01-KVM环境与嵌套虚拟化核验.sh` | 装 KVM/libvirt 工具链，验证 `/dev/kvm` 与 `kvm-ok` |
| `02-libvirt配置.sh` | 配 libvirt 网络与存储池 |
| `03-创建虚机与cloud-init.sh` | 用云镜像建 qcow2 增量盘，写 cloud-init 建两台虚机 |
| `04-取虚机IP.sh` | 从 DHCP 租约取出两台虚机 IP |
| `05-虚机连通性验收.sh` | 虚机间 SSH 与网络连通性初验 |
| `06-k8s前置条件.sh` | 内核模块、sysctl、swap 关闭等前置 |
| `07-安装kubeadm与kubelet.sh` | 装 kubeadm / kubelet / kubectl |
| `08-控制面初始化.sh` | cp1 上 `kubeadm init` |
| `09-装CNI并join工作节点.sh` | 装 Calico，w1 执行 join |
| `10-集群终验.sh` | 节点 Ready、系统 Pod、DNS、Service 验收 |
| `11-跨节点互通验收.sh` | 跨节点 Pod 互通验收（此处暴露了故障） |

## 怎么跑

脚本面向 WSL2 内的 KVM 环境，入口在 WSL 里：

```bash
wsl -- bash -lc "bash /mnt/d/projects/learning/k8s/子教程/运维专项/assets/课8-真机搭建/01-KVM环境与嵌套虚拟化核验.sh"
```

## 两条注意事项

**会改环境**：`01` / `02` / `06` / `07` 会 apt 装包、改 sysctl、装 libvirt。按协作约定，这类操作需你确认后再跑，别在无准备的环境里顺着执行。

**有记忆化参数**：`03` 里写死了内存核算（WSL 约 8G，先起 1 台 2G），`08` 里带 `--ignore-preflight-errors=NumCPU,Mem`（虚机 1963MB < kubeadm 要求 2048MB）。**生产环境不该这样**，这是为了在受限的 WSL 里跑通做的妥协，讲义正文已标注。

## 相关

- 讲义：[08-真机搭建：从裸虚机到跨节点互通.md](../../lessons/08-真机搭建：从裸虚机到跨节点互通.md)
- 排障脚本：[../课8-Calico排障/](../课8-Calico排障/)（本组 11 步跑完后跨节点不通，排障在那里）
