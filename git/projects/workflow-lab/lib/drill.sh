#!/usr/bin/env bash
# ── include guard ─────────────────────────────────────────
# 防止重复 source：本文件定义了 全局状态，
# 重复加载会在 set -e 下因 readonly 冲突直接中断。
[[ -n ${_WF_DRILL_LOADED:-} ]] && return 0
_WF_DRILL_LOADED=1
# lib/drill.sh —— 协作演练：合并冲突 / 变基 / 分支策略落地
#
# 课 5-9 的知识点在这里变成"两人真撞一次"的演练。
# 与"讲一遍命令"的差别：演练会验证终态，而不是只打印过程。

WF_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$WF_LIB_DIR/core.sh"
# shellcheck source=/dev/null
. "$WF_LIB_DIR/repo.sh"

# ── 演练 1：两人改同一行 → 真冲突 → 正确解决 ──────────────
wf_drill_merge_conflict() {
    local root="$1"
    local zhang="$root/zhang" li="$root/li"
    [[ -d $zhang && -d $li ]] || die "$WF_NOINPUT" "需要沙盘根目录（含 zhang/ 与 li/）"

    printf '═══ 演练：合并冲突 ═══\n'

    # 两人都从干净的远端出发
    git -C "$zhang" checkout -q -B drill-conflict HEAD
    git -C "$li"    checkout -q -B drill-conflict HEAD
    git -C "$zhang" push -q -f origin drill-conflict 2>/dev/null || true
    git -C "$li"    fetch -q origin
    git -C "$li"    reset -q --hard origin/drill-conflict

    # 同一文件同一行，两人改出不同内容 —— 这是冲突的充分条件
    wf_commit "$zhang" 'feat(zhang): 调整服务端口' 'config.ini' 'port=8080'
    wf_commit "$li"    'feat(li): 调整服务端口'    'config.ini' 'port=9090'

    git -C "$zhang" push -q origin drill-conflict 2>/dev/null || true

    # Li Si 拉取 → 必然冲突
    git -C "$li" fetch -q origin
    local rc=0
    git -C "$li" merge --no-edit origin/drill-conflict >/dev/null 2>&1 || rc=$?

    if (( rc != 0 )); then
        finding_add OK drill "如期产生冲突（merge 退出码 $rc）"
        printf '  冲突文件内容：\n'
        sed 's/^/    /' "$li/config.ini" 2>/dev/null || true

        # 正确解决：显式选定一侧，而非把冲突标记留在文件里
        printf 'port=8080\n' > "$li/config.ini"
        git -C "$li" add -- config.ini
        git -C "$li" commit -q -m 'fix: 解决端口冲突，采用 8080'

        if grep -qE '^(<<<<<<<|>>>>>>>)' "$li/config.ini" 2>/dev/null; then
            finding_add BLOCK drill "冲突标记仍留在文件中"
        else
            finding_add OK drill "冲突已正确解决，无残留冲突标记"
        fi
    else
        finding_add WARN drill "未产生冲突（两人改动可能被自动合并）"
    fi

    return 0
}

# ── 演练 2：rebase vs merge 的历史形状对比 ────────────────
# 目的不是"哪个更好"，而是让两条历史线的形状差异可见：
#   merge 保留分叉（有一次 merge 提交）
#   rebase 变成直线（改写提交，遵循黄金法则：只 rebase 未推送的）
wf_drill_rebase() {
    local root="$1"
    local zhang="$root/zhang"
    [[ -d $zhang ]] || die "$WF_NOINPUT" "需要沙盘根目录"

    printf '═══ 演练：rebase vs merge 的历史形状 ═══\n'

    git -C "$zhang" checkout -q -B drill-rebase HEAD

    # 主线上先有一个别人的提交
    wf_commit "$zhang" 'feat: 主线提交 A' 'a.txt' 'A'
    local base
    base=$(git -C "$zhang" rev-parse HEAD)

    # 切出特性分支，做两个提交
    git -C "$zhang" checkout -q -b feature/rebase-demo
    wf_commit "$zhang" 'feat(demo): 特性提交 1' 'f1.txt' 'F1'
    wf_commit "$zhang" 'feat(demo): 特性提交 2' 'f2.txt' 'F2'

    # 主线再前进一个提交，形成分叉
    git -C "$zhang" checkout -q drill-rebase
    wf_commit "$zhang" 'feat: 主线提交 B' 'b.txt' 'B'

    # 记录：merge 会多出一个合并提交
    git -C "$zhang" checkout -q -b demo-merge feature/rebase-demo
    git -C "$zhang" merge --no-ff -q -m 'chore: 合并特性分支（--no-ff）' drill-rebase >/dev/null 2>&1 || true
    local merge_parents merge_count
    merge_parents=$(git -C "$zhang" log -1 --format=%P | wc -w | tr -d ' ')
    merge_count=$(git -C "$zhang" rev-list --count drill-rebase..demo-merge)

    # rebase：把特性分支搬到主线最新之后，历史成直线
    git -C "$zhang" checkout -q feature/rebase-demo
    git -C "$zhang" rebase -q drill-rebase >/dev/null 2>&1 || true
    local rebase_parents rebase_linear
    rebase_parents=$(git -C "$zhang" log -1 --format=%P | wc -w | tr -d ' ')

    # 判断 rebase 后是否为直线：从 HEAD 到 base 的路径上没有分叉
    rebase_linear=$(git -C "$zhang" log --oneline --merges drill-rebase..feature/rebase-demo | wc -l | tr -d ' ')

    printf '  merge  : 最新提交父指针 %s 个，分支上新增 %s 个提交\n' "$merge_parents" "$merge_count"
    printf '  rebase : 最新提交父指针 %s 个，合并提交 %s 个\n' "$rebase_parents" "$rebase_linear"

    if (( merge_parents == 2 )); then
        finding_add OK drill "merge 保留了分叉（合并提交有两个父指针）"
    else
        finding_add WARN drill "merge 未产生预期的两父指针合并提交"
    fi

    if (( rebase_parents == 1 && rebase_linear == 0 )); then
        finding_add OK drill "rebase 后历史为直线（单父指针、无合并提交）"
    else
        finding_add WARN drill "rebase 后历史不是直线"
    fi

    finding_add WARN drill "黄金法则：只 rebase 未推送给他人的提交（本演练分支从未推送，合规）"

    # 回到主分支，清理演示分支
    git -C "$zhang" checkout -q drill-rebase
    git -C "$zhang" branch -q -D demo-merge feature/rebase-demo 2>/dev/null || true

    return 0
}
