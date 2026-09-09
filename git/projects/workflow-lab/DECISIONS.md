# wf-lab 技术决策记录

> 每条记录回答三件事：**为什么这么写**、**放弃了什么**、**证据是什么**。
> 标注 🔴 的是本项目实测抓出的真 bug 或真实认知偏差，不是设计权衡。

---

## D1. 钩子必须"自检"，不能只"安装"

**决定**：`wf_hooks_install` 之后必须有 `wf_hooks_selftest`，且自检造一个必然违规的提交去看退出码。

**放弃了什么**：自检会真实产生并提交再回滚文件，比"检查文件存在且可执行"慢，也会短暂改动暂存区。

**证据**：课 12 实测的钩子三大失效场景都不是"文件不存在"，而是"文件在但不起作用"——
① 没有执行位，Git 只打印一行 hint，提交照样 exit 0；
② `git grep --cached` 写错位置，exit 128 被 `if` 当成"没找到"，静默放行；
③ 钩子文件里含被检查的关键词，不排除钩子目录会命中自己。

**推论**：检查"装了没"是没意义的，只有"能不能拦住"才算数。

---

## D2. 🔴 自检的前置条件必须先验证（误报陷阱）

**现象**：自检永远报"成功拦住"，即使钩子是坏的。

**根因**：探针文件若没真正进入暂存区（被 `.gitignore` 排除、或 `add` 失败），
`git commit` 会以"nothing to commit"失败（rc≠0）。朴素的判断把**这个失败**
误读成"钩子拦住了"。

**修法**：先用 `git diff --cached --quiet -- <probe>` 确认探针已入索引，再判断提交结果。
探针一律用 `git add -f` 强制加入。

**教训**：任何"用失败退出码反推防护生效"的检查，都必须先证明**有东西可拦**。
否则失败原因和保护生效无法区分。

---

## D3. 🔴 `--cached` 的触发条件比讲义写的更精确

**课 12 原表述**：`--cached` 必须放在模式之前，否则 exit 128。

**本项目实测补充**（Git 2.43.0）：触发条件是 **`--cached` 出现在位置参数（模式）之后且没有 `--` 分隔**。

```
git grep --cached -n -E 'x'         # ✓ rc=0
git grep -n -E 'x' --cached         # ✗ rc=128  fatal: option '--cached' must come before non-option arguments
git grep -n -E -e 'x' --cached      # ✓ rc=0   ← -e 让模式成为"选项"，不是位置参数
git grep -n -E -e 'x' --cached -- . # ✓ rc=0   ← 有 -- 分隔，解析正常
```

**影响**：只有第 2 种写法会让钩子静默失效。用 `-e` 或带 `--` 都是安全的。
写自检用例时如果拿 `-e` 版本去"人为写坏钩子"，钩子其实没坏，自检自然通过——
本项目第一版测试就是这样误判的。

---

## D4. 🔴 `(( x++ ))` 在 `set -e` 下会杀死脚本

**现象**：`finding_add` 被调用后脚本静默退出，无任何报错。

**根因**：`(( WF_N_WARN++ ))` 求值是**自增前**的值。计数器为 0 时表达式结果为 0，
bash 把"算术表达式结果为 0"当作返回码 1，`set -e` 立即终止。

**修法**：改用前置自增 `(( ++WF_N_WARN ))`。

**注**：这与课程讲义里讲过的是同一个陷阱（课 4 / Shell 课程均强调），
但换到"计数器"场景仍然会踩到——因为直觉上"自增"和"判断"是两件事。

---

## D5. 🔴 `cond && return N` 在 `set -e` 下会连累调用方

**现象**：`findings_exit_code` 之后的代码不执行，但退出码其实是对的。

**根因**：`(cond) && return N` 是一个 AND 列表。当 `cond` 为假时，
整个列表的返回值是 1，`set -e` 终止脚本——即使语义上"条件不满足"是正常的。

**修法**：改用 `if ... then return ... fi`。if 条件中的命令受 `set -e` 豁免。

**同类**：`bisect run`、`git push` 这些"用非 0 退出码表达成功语义"的命令，
都必须用 `if cmd; then ... else ... fi` 捕获，不能用 `cmd || true` 掩盖。

---

## D6. 🔴 `--force-with-lease` 的语义常被误解

**常见误解**："`--force-with-lease` 会检查我的历史是否包含远端的提交，不包含就拒绝。"

**实测语义**：它只保证"**我上次 fetch 之后，远端没有再被别人动过**"。

证据（Git 2.43.0）：

| 场景 | 结果 |
|---|---|
| `origin/master` == 远端 tip，但本地历史与远端分叉 | **lease 通过**（照样覆盖） |
| fetch 之后别人又推了一个提交 | lease 拒绝：`! [rejected] (stale info)` |
| 用 `HEAD:master` 而非 `master:master` 推送 | lease **退化为无条件 force**（本地侧没有对应跟踪分支可比对） |

**影响**：lease 不是"安全版 force"，它是"**我只覆盖我看到的那个版本**"。
如果不先 fetch 就推，或者用 `HEAD:` 形式推，保护等于没有。

**演练设计**：因此本项目的强推演练必须构造成"fetch 之后别人又推"的时序，
才能真实展示拒绝行为。最初按"历史分叉"构造，lease 一律放行，演练给出假阴性。

---

## D7. 🔴 bisect 演练的三个连环坑

1. **探针不能放在仓库里**：`.bisect-probe.sh` 是未跟踪文件，bisect 要求工作区干净，
   `bisect start` 直接被拒，只打印 `git status`，看起来像"bisect 没输出"。
   修法：探针放 `mktemp` 到仓库外，用绝对路径读被测文件。

2. **每次提交必须真的改变内容**：循环写 `good`/`bad` 两个固定值时，
   连续相同内容会让 `git commit` 报 "nothing to commit"，实际提交数少于预期，
   `HEAD~9` 随即越界报 `Bad rev input`。修法：内容里带上步号。

3. **`bisect run` 找到坏提交时返回非 0**：它用退出码表达"找到了"。
   `set -e` 下脚本立刻中断，结论永远走不到。修法：`if ! out=$(...); then :; fi`。
   另外 `bisect log` 必须在 `bisect reset` **之前**取，reset 会清空状态。

---

## D8. 库文件必须加 include guard（本项目踩到两次）

**现象**：`readonly variable` 报错，或 `unbound variable`。

**根因**：5 个库都 `source core.sh`，主程序又逐个 source 它们 → `core.sh` 被加载 6 次。
`readonly WF_OK=0` 第二次执行即报错，在 `set -e` 下直接中断。

**修法**：每个库头部加 guard：

```bash
[[ -n ${_WF_CORE_LOADED:-} ]] && return 0
_WF_CORE_LOADED=1
```

**注**：这与 Shell 课程 `declare -r` 的坑同源——**`readonly` 在重复 source 场景下是雷**。
本项目的 5 个库都定义了全局状态（临时目录数组、findings 数组、trap），
重复加载除了报错还会导致已登记的资源被重置。

---

## D9. 复杂度门槛的检测口径必须明确

**第一版口径（错）**：按行匹配 `while|for` 与 `$(` → 把函数内的普通赋值
（`before=$(wf_repo_size_kb ...)`）全部误判为"循环内 fork"，报 9 次。

**修正口径**：按**循环体深度**判定，且排除 `$(( ))`（算术展开不产生子进程），
并只统计"可避免"的 fork（循环内调 `cat-file` / `wc -l` / `mktemp`）。

**当前实测**：1 处（在阈值内）。

**放弃**：没有把阈值设为 0。`while read` 里一次命令替换是可读性与性能的合理折中；
真正的红线是"循环体内每次迭代都 fork 外部命令"。

---

## D10. 为什么用 filter-branch 而不是 git-filter-repo

**约束**：本机未安装 `git-lfs` 与 `git-filter-repo`（课程约定不擅自安装软件）。

**决定**：用 `filter-branch --index-filter` 演示历史重写，用 Git 原生 clean/smudge
过滤器演示 LFS 指针机制，并在输出里显式声明这是一次替代实现。

**放弃了什么**：`git-filter-repo` 更快也更安全（它默认不保留 `refs/original`）。
`filter-branch` 是官方自 Git 2.24 起不推荐的。

**但机制与后果完全相同**，尤其是这条最容易踩的：
**`filter-branch` 跑完体积不降反升**——因为 `refs/original/` 保留了完整备份。
必须接三步清理（删 `refs/original` → `reflog expire` → `gc --prune=now`）才真正释放。

**课程价值**：这个"不降反升"的现象用 filter-repo 反而看不到，
用 filter-branch 反而更能说明"为什么瘦身需要做完整套动作"。

---

## 决策汇总

| 编号 | 主题 | 类型 |
|---|---|---|
| D1 | 钩子自检而非仅安装 | 设计 |
| D2 | 自检前置条件（误报陷阱） | 🔴 真 bug |
| D3 | `--cached` 精确触发条件 | 🔴 认知偏差 |
| D4 | `(( x++ ))` 与 set -e | 🔴 真 bug |
| D5 | `&&` 短路与 set -e | 🔴 真 bug |
| D6 | `--force-with-lease` 真实语义 | 🔴 认知偏差 |
| D7 | bisect 三连环坑 | 🔴 真 bug |
| D8 | include guard | 🔴 真 bug |
| D9 | 复杂度门槛口径 | 设计 |
| D10 | filter-branch 替代方案 | 约束下的取舍 |
