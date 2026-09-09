# wf-lab —— 团队 Git 工作流搭建与故障演练沙盘

Git 课程的结课实战项目。把 12 课的知识固化成**能真跑一遍**的演练与检查：
不依赖任何托管平台，远端用本地裸仓库（`file://`）模拟，所有"冲突 / 强推 / 误删 / 瘦身"都在本机真实发生。

## 快速开始

```bash
# 1. 环境体检（确认 git 与依赖）
bash wf-lab doctor

# 2. 搭一个"远端 + 两名成员"的沙盘
bash wf-lab init /tmp/team

# 3. 给 Zhang Wei 的仓库装团队钩子，并验证真的生效
bash wf-lab hooks /tmp/team/zhang

# 4. 跑全套演练
bash wf-lab replay /tmp/team-full

# 5. 跑测试
bash tests/run_tests.sh
```

## 子命令

| 命令 | 作用 | 覆盖课程知识点 |
|---|---|---|
| `init <dir>` | 搭建 remote.git + zhang + li 三仓库沙盘 | 课 1、3、7 |
| `hooks <repo>` | 安装 pre-commit / commit-msg / pre-push 并自检 | 课 9、11、12 |
| `hooks <repo> --check-only` | **只自检，不重新安装** | 课 12 |
| `audit <repo>` | 卫生审计：体积、大文件、工作区状态 | 课 12 |
| `audit <repo> --purge <path>` | 重写历史移除路径并回收空间 | 课 12 |
| `rescue <repo> reset-hard` | 用 reflog 找回被 `reset --hard` 丢掉的提交 | 课 11 |
| `rescue <repo> deleted-branch` | 重建被 `-D` 删除的分支 | 课 11 |
| `rescue <repo> bisect` | 二分定位第一个坏提交 | 课 10 |
| `rescue <dir> force-push` | `--force-with-lease` vs `--force` 对照 | 课 11 |
| `drill <dir> merge-conflict` | 两人改同一行 → 真冲突 → 正确解决 | 课 6 |
| `drill <dir> rebase` | merge 与 rebase 的历史形状对比 | 课 8 |
| `replay <dir>` | 一键跑全套 | 全部 |

## 退出码

| 码 | 含义 | 调用方该怎么做 |
|---|---|---|
| 0 | 全部通过 | 正常 |
| 1 | 有 WARN，或自检发现钩子没生效 | 看一眼；钩子失效要立刻处理 |
| 2 | 有 BLOCK | 必须停下 |
| 64 | 用法错误 | 参数写错了 |
| 66 | 输入不存在 / 不是仓库 | 路径不对 |

`0 / 1 / 2` 三档分开是刻意的：混成一个 `1`，调用方就只能 grep 日志文本判断成败，
那是把结构化信息降级成字符串匹配。

## 三个团队钩子

| 钩子 | 拦什么 | 关键设计 |
|---|---|---|
| `pre-commit` | 调试残留（`console.log` / `debugger` / 私钥）+ 大文件（>512KB） | `--cached` 必须在模式前；排除 `.git` 防止钩子"自咬" |
| `commit-msg` | 不符合 Conventional Commits 的信息、超 72 字符 | 豁免 `Merge` / `Revert` 自动生成的信息 |
| `pre-push` | 直接推送受保护分支、对受保护分支非快进更新 | 课 11 的"可以/不能 force 清单"由人工约定变成机器强制 |

**⚠️ 客户端钩子拦不住 `--no-verify`。** 真正的强制必须靠服务端（pre-receive）。

## 目录结构

```
wf-lab                     主程序（参数解析 + 编排）
lib/core.sh                严格模式、日志、退出码、findings、临时目录 trap
lib/repo.sh                沙盘构建、成员身份、提交辅助
lib/hooks.sh               三个钩子的生成、安装、自检、状态报告
lib/audit.sh               卫生审计、历史大文件定位、瘦身三步走
lib/rescue.sh              reflog/误删分支/bisect/强推 四个救援演练
lib/drill.sh               合并冲突、rebase 两个协作演练
tests/run_tests.sh         手写测试运行器（68 条断言）
tests/verify_complexity.py 复杂度门槛核查
DECISIONS.md               10 条技术决策（含 6 个实测抓出的真 bug）
```

## 环境要求

bash 4.4+，`git`，以及 `awk` / `sort` / `head` / `mktemp` / `du`（均为系统自带）。

**无 git-lfs、无 git-filter-repo、无 shellcheck、无 bats** —— 按课程约定未安装。
历史重写用 `filter-branch` 等价演示，LFS 用 Git 原生 clean/smudge 过滤器等价演示，
差异已在 [DECISIONS.md](DECISIONS.md) D10 说明。

## 复杂度四门槛

| 门槛 | 要求 | 实测 |
|---|---|---|
| 规模 | ≥300 行、≥5 函数、≥2 文件 | 1321 行、52 函数、7 文件 ✓ |
| 跨阶段 | ≥3 阶段、每阶段 ≥2 知识点 | 4 阶段全覆盖（见上表"覆盖课程知识点"）✓ |
| 质量 | 测试全绿、循环内 fork 受控 | 68/68 断言通过、循环内可避免 fork 1 处 ✓ |
| 决策 | ≥2 处权衡并记录取舍 | 10 条，每条写明"放弃了什么" ✓ |

## 本项目实测抓出的真 bug

详见 [DECISIONS.md](DECISIONS.md)，其中 6 个是真实缺陷而非设计选择：

1. **自检误报** —— 探针没进索引时 `commit` 失败被误读成"钩子拦住了"（D2）
2. **`(( x++ ))` 杀死脚本** —— 计数器为 0 时自增表达式结果为 0，`set -e` 终止（D4）
3. **`&& return` 连累调用方** —— AND 列表结果为假时 `set -e` 终止（D5）
4. **`--force-with-lease` 语义误解** —— 它只保证"fetch 后远端没再动"，不检查历史包含关系（D6）
5. **bisect 三连环坑** —— 探针位置、空提交、`run` 的非 0 退出码（D7）
6. **include guard 缺失** —— 5 个库重复 source `core.sh` 导致 `readonly` 冲突（D8）
