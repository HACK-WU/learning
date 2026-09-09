# Git 课程手册

> 全课索引与收束。12 课 / 4 阶段 / 36 知识点已全部讲完，结课项目与三份收尾手册已交付。
> 这份文档不重复讲知识，只做三件事：**处境索引**、**硬数字速查**、**决策清单**。

**环境**：WSL Ubuntu 24.04 · bash 5.2.21 · Git **2.43.0** · git-lfs / git-filter-repo 未安装

---

## 📍 处境索引：你在哪，就看哪份

| 你现在…… | 去看 |
|---|---|
| 刚开始学，想按课走 | [01-学习路径总览.md](01-学习路径总览.md) → [02-课程目录.md](02-课程目录.md) |
| 出事了，要立刻定位 | [09-排障速查手册.md](09-排障速查手册.md) |
| 想理解"为什么会这样" | [08-实战经验.md](08-实战经验.md) |
| 想直接复制命令 | [10-场景解法库.md](10-场景解法库.md) |
| 想跑一遍演练 | [wf-lab](projects/workflow-lab/README.md) |
| 想知道项目为什么这么写 | [DECISIONS.md](projects/workflow-lab/DECISIONS.md) |
| 断点续学 | [00-学习档案.md](00-学习档案.md) |

---

## 🎯 全课结构

| 阶段 | 主题 | 课 | 核心问题 |
|---|---|---|---|
| 1 | 地基与对象模型 | 1–3 | 一次 `git commit` 到底往磁盘里写了什么 |
| 2 | 个人工作流 | 4–6 | 改 → 暂存 → 提交 → 分支 → 合并 → 撤销 |
| 3 | 协作与共享 | 7–9 | 多人协作时怎么让历史可读、可追溯、可回滚 |
| 4 | 排查、救援与工程实践 | 10–12 | 东西丢了、历史被覆盖了——怎么找回来、怎么预防 |

**故事主线**：一次提交的一生。冲突是"历史既不能随便改，又必须能被改写才能交付"；
收束是"既能设计分支模型，也能用 reflog 把任何误操作救回来"。

---

## 🔢 硬数字速查（本机实测）

### 仓库体积

| 场景 | 数字 |
|---|---|
| 空仓库 `.git` 基线 | 208 KB |
| 加 1MB **随机**文件 | +1048 KB |
| 加 1MB **零字节** | +28 KB（压缩差 37 倍） |
| 删除大文件并提交后 | **+8 KB（不降反升）** |
| `gc --prune=now` 后 | −44 KB（大文件仍在历史） |
| `filter-branch` 刚跑完 | **+16 KB（refs/original 备份）** |
| 三步清理后 | 1252 → **188 KB** |

### 命令行为

| 行为 | 结果 |
|---|---|
| 钩子无执行位 | 提交 **exit 0**（只有一行 hint） |
| `git grep -n -E 'x' --cached`（位置参数后） | **exit 128** |
| `git grep -n -E -e 'x' --cached`（`-e` 模式） | exit 0（安全） |
| bisect 定位（100 个提交） | **6 步**（log₂100 ≈ 6.64） |
| `--force-with-lease`，远端未再动但历史分叉 | **放行** |
| `--force-with-lease`，fetch 后别人又推 | **拒绝**（`stale info`） |
| `--force-with-lease` 用 `HEAD:master` | **退化为无条件 force** |

---

## 🧭 三张决策清单

### 1. 撤销四连：该用哪个

| 命令 | 动 HEAD | 动索引 | 动工作区 | 用在哪 |
|---|---|---|---|---|
| `restore <file>` | ✗ | ✗ | ✓ | 丢弃工作区改动 |
| `restore --staged <file>` | ✗ | ✓ | ✗ | 取消暂存 |
| `reset --soft <sha>` | ✓ | ✗ | ✗ | 改完重提 |
| `reset --mixed <sha>` | ✓ | ✓ | ✗ | 默认，重新选择要暂存什么 |
| `reset --hard <sha>` | ✓ | ✓ | ✓ | **危险**，工作区一并丢弃 |
| `revert <sha>` | 新增提交 | — | — | **已推送**历史的正确撤销方式 |

**判据**：**已推送 → `revert`；未推送 → `reset`。**

### 2. merge 还是 rebase

| 判断点 | 选 |
|---|---|
| 这些提交**已推送**给别人 | `merge` |
| 这些提交只在本地 | `rebase`（要直线历史）或 `merge`（要保留分叉） |
| 想要可追溯的"这个功能是一整块" | `merge --no-ff` |

**黄金法则**：**只 rebase 尚未推送给他人的提交。**

### 3. 可以 / 不能 force

| 场景 | 结论 |
|---|---|
| 自己独占的功能分支，未推送 | ✅ 可以 force |
| 自己独占，已推送但无人基于它工作 | ⚠️ 可以，但先通知 |
| 共享分支（`master` / `main` / `release/*`） | ❌ **禁止** |
| 任何人可能已拉取的分支 | ❌ 禁止 |

**强制手段**：客户端 `pre-push` 钩子能拦住误操作，但**拦不住 `--no-verify`**——
真正的强制必须靠服务端 `pre-receive`。

---

## ⚡ 五组"唯一正确写法"

**1. 找不到东西查 reflog，不查 log**

```bash
git reflog          # 你做过什么（飞行记录仪）
git log             # 当前历史（被移开的提交看不到）
```

**2. 强推必用 lease，且用分支名**

```bash
git fetch origin
git push --force-with-lease origin master:master    # 不是 HEAD:master
```

**3. 钩子装完必须自检**

```bash
git add -f -- probe.js
git diff --cached --quiet -- probe.js || echo "可判断"   # 先证明有东西可拦
git commit -m 'test: probe' && echo "❌ 没生效" || echo "✅ 拦住了"
```

**4. 瘦身必须三步走，且全员重克隆**

```bash
git filter-branch -f --prune-empty --index-filter "..." -- --all
git for-each-ref --format='%(refname)' refs/original/ | xargs -n1 git update-ref -d
git reflog expire --expire=now --all
git gc --prune=now --aggressive
```

**5. 造测试数据用随机源**

```bash
head -c 1048576 /dev/urandom > big.bin     # ✅
dd if=/dev/zero of=big.bin bs=1M count=1   # ❌ 会被压缩
```

---

## 🏗️ 结课项目：wf-lab

**团队 Git 工作流搭建与故障演练沙盘** —— 不依赖任何托管平台，远端用本地裸仓库模拟，
所有"冲突 / 强推 / 误删 / 瘦身"都在本机真实发生。

| 门槛 | 要求 | 实测 |
|---|---|---|
| 规模 | ≥300 行、≥5 函数、≥2 文件 | 1321 行、52 函数、7 文件 ✓ |
| 跨阶段 | ≥3 阶段 | 4 阶段全覆盖 ✓ |
| 质量 | 测试全绿 | **68/68 断言通过** ✓ |
| 决策 | ≥2 处权衡 | 10 条，含 **6 个实测真 bug** ✓ |

**实测抓出的 6 个真 bug**（详见 [DECISIONS.md](projects/workflow-lab/DECISIONS.md)）：

1. 自检误报——探针没进索引时 `commit` 失败被误读成"钩子拦住了"
2. `(( x++ ))` 在 `set -e` 下杀死脚本（计数器为 0 时自增表达式结果为 0）
3. `cond && return N` 在 `set -e` 下连累调用方
4. `--force-with-lease` 语义被误解（只保证"fetch 后远端没再动"）
5. bisect 三连环坑（探针位置 / 空提交 / `run` 的非 0 退出码）
6. 库缺 include guard，重复 source 导致 `readonly` 冲突

---

## 🔗 三条贯穿全课的伏笔

**1. 分支是指针不是副本**（课 5）→ 撑起了课 6 的冲突、课 8 的 rebase、课 11 的误删分支救援。
删分支能救回来，正是因为删的只是指针。

**2. 提交过就几乎丢不了**（课 3 对象模型）→ 课 11 的 reflog 救援全部建立在这条上。
真正危险的是**从没提交过**的工作。

**3. 历史可被改写，但改写有代价**（课 8 rebase）→ 课 12 的历史瘦身是同一件事的极端形式；
代价是**全员必须重新克隆**。

---

## 📚 全部产物

| 类型 | 文件 |
|---|---|
| 档案与索引 | [00-学习档案.md](00-学习档案.md) · [00-评审清单.md](00-评审清单.md) · [01-学习路径总览.md](01-学习路径总览.md) · [02-课程目录.md](02-课程目录.md) |
| 讲义 | 4 个阶段 `stages/*/lessons/`，共 12 课 |
| 阶段概览 | `stages/1..4/overview.md` |
| 结课项目 | [projects/workflow-lab/](projects/workflow-lab/README.md) · [DECISIONS.md](projects/workflow-lab/DECISIONS.md) |
| 收尾手册 | [08-实战经验.md](08-实战经验.md) · [09-排障速查手册.md](09-排障速查手册.md) · [10-场景解法库.md](10-场景解法库.md) · 本文件 |

---

## ✅ 交付状态

| 项 | 状态 |
|---|---|
| 12 课 / 36 知识点 | ✅ 全部讲完（2026-09-08 ~ 09-09） |
| 复杂度四门槛 | ✅ 全部达标 |
| 68 条断言 | ✅ 全通过 |
| 链接 | ✅ 零死链 |
