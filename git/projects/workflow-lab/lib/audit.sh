#!/usr/bin/env bash
# ── include guard ─────────────────────────────────────────
# 防止重复 source：本文件定义了 readonly 阈值常量，
# 重复加载会在 set -e 下因 readonly 冲突直接中断。
[[ -n ${_WF_AUDIT_LOADED:-} ]] && return 0
_WF_AUDIT_LOADED=1
# lib/audit.sh —— 仓库卫生审计：体积 / 大文件 / 未跟踪垃圾 / 历史里的"胖子"
#
# 课 12 最反直觉的一条结论在本库被固化：
#   "删掉大文件并提交"之后，.git 体积不降反升；
#   只有 gc --prune=now 之后才下降，但大文件仍在历史里 —— 真正的释放要靠历史重写。

WF_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$WF_LIB_DIR/core.sh"

# 审计阈值
readonly WF_AUDIT_BIG_BLOB_KB=512      # 单文件超过此值算"大文件"
readonly WF_AUDIT_REPO_SIZE_MB=50      # .git 超过此值提示该瘦身
readonly WF_AUDIT_TOP_N=10

# ── 列出历史里最大的 N 个 blob ─────────────────────────────
# ⚠️ 用 --all --reflog 才能覆盖"已从分支上删除、但仍被 reflog 挂着"的对象。
#    只查 HEAD 会漏掉刚删掉的那个大文件 —— 而那恰恰是最该清理的。
wf_audit_big_blobs() {
    local dir="$1" n="${2:-$WF_AUDIT_TOP_N}"
    git -C "$dir" rev-list --objects --all --reflog 2>/dev/null \
        | git -C "$dir" cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' \
        | awk -v n="$n" '
            $1 == "blob" {
                size = $3; name = ""
                for (i = 4; i <= NF; i++) name = (name == "" ? $i : name " " $i)
                if (!(name in seen) || size > seen[name]) {
                    seen[name] = size
                }
            }
            END {
                for (k in seen) printf "%d\t%s\n", seen[k], k
            }' \
        | sort -rn | head -n "$n"
}

# ── 大文件是否仍在历史里（即使工作区已删）────────────────
wf_audit_blob_in_history() {
    local dir="$1" path="$2"
    git -C "$dir" log --all --oneline -- "$path" 2>/dev/null | head -n 3
}

# ── 工作区卫生：未跟踪文件与未提交改动 ────────────────────
wf_audit_worktree() {
    local dir="$1"
    local untracked dirty
    untracked=$(git -C "$dir" ls-files --others --exclude-standard | wc -l | tr -d ' ')
    dirty=$(git -C "$dir" status --porcelain | grep -cv '^??' || true)
    printf 'untracked=%s modified=%s\n' "$untracked" "$dirty"
}

# ── 完整卫生审计 ───────────────────────────────────────────
wf_audit_run() {
    local dir="$1"
    [[ -d $dir/.git ]] || die "$WF_NOINPUT" "不是 Git 仓库: $dir"

    local size_kb size_mb untracked modified
    size_kb=$(wf_repo_size_kb "$dir")
    size_mb=$(( size_kb / 1024 ))

    printf '── 仓库卫生审计：%s ──\n' "$dir"
    printf '  .git 体积    : %d KB (%d MB)\n' "$size_kb" "$size_mb"

    if (( size_mb > WF_AUDIT_REPO_SIZE_MB )); then
        finding_add WARN audit ".git 体积 ${size_mb}MB 超过 ${WF_AUDIT_REPO_SIZE_MB}MB，建议做历史瘦身"
    fi

    # 工作区状态
    local wt
    wt=$(wf_audit_worktree "$dir")
    untracked="${wt#untracked=}"; untracked="${untracked%% *}"
    modified="${wt##*modified=}"
    printf '  未跟踪文件  : %s\n' "$untracked"
    printf '  已改动文件  : %s\n' "$modified"
    (( modified == 0 )) || finding_add WARN audit "工作区有 ${modified} 个未提交改动"

    # 历史大文件
    printf '\n  历史中体积最大的 blob（Top %d）：\n' "$WF_AUDIT_TOP_N"
    local line size path found=0
    while IFS=$'\t' read -r size path; do
        [[ -n ${size:-} ]] || continue
        found=1
        local kb=$(( size / 1024 ))
        printf '    %8d KB  %s\n' "$kb" "$path"
        if (( kb > WF_AUDIT_BIG_BLOB_KB )); then
            finding_add WARN audit "历史中存在 ${kb}KB 的大文件：${path}（删除文件不能释放空间，需重写历史）"
        fi
    done < <(wf_audit_big_blobs "$dir")
    (( found )) || printf '    （无 blob）\n'

    printf '\n'
}

# ── 瘦身：删除历史中的指定路径并回收空间 ──────────────────
# 本机未装 git-filter-repo，用 filter-branch 演示 —— 机制与后果完全相同，
# 官方自 Git 2.24 起推荐 filter-repo（更快、更安全），区别不在原理。
#
# ⚠️ filter-branch 跑完体积不降反升，因为 refs/original/ 留了完整备份。
#    必须接三步清理，否则等于白做（这是课 12 实测的关键发现）。
wf_audit_purge_path() {
    local dir="$1" path="$2"
    [[ -d $dir/.git ]] || die "$WF_NOINPUT" "不是 Git 仓库: $dir"

    log_info "开始重写历史，移除路径：$path"
    local before after
    before=$(wf_repo_size_kb "$dir")

    # 第一步：重写历史（--index-filter 比 --tree-filter 快得多，不碰工作区）
    FILTER_BRANCH_SQUELCH_WARNING=1 git -C "$dir" filter-branch -f --prune-empty \
        --index-filter "git rm -r --cached --ignore-unmatch -- '$path'" \
        --tag-name-filter cat -- --all >/dev/null 2>&1 \
        || die "$WF_INTERNAL" "filter-branch 执行失败"

    after=$(wf_repo_size_kb "$dir")
    printf '  重写后      : %d KB（%s）\n' "$after" \
        "$( (( after >= before )) && echo '⚠️ 不降反升：refs/original 仍在' || echo '已下降' )"

    # 第二步：三步清理（缺一不可）
    git -C "$dir" for-each-ref --format='%(refname)' refs/original/ \
        | while read -r r; do [[ -n $r ]] && git -C "$dir" update-ref -d "$r"; done
    git -C "$dir" reflog expire --expire=now --all
    git -C "$dir" gc -q --prune=now --aggressive 2>/dev/null || true

    local final
    final=$(wf_repo_size_kb "$dir")
    printf '  三步清理后  : %d KB\n' "$final"
    printf '\n  %d KB → 重写后 %d KB → 清理后 %d KB\n' "$before" "$after" "$final"

    finding_add WARN audit "历史已重写（移除 $path）：所有协作者必须重新克隆，不能 merge"
}
