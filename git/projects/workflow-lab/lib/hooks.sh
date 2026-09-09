#!/usr/bin/env bash
# ── include guard ─────────────────────────────────────────
# 防止重复 source：本文件定义了 readonly 常量 WF_PROTECTED_BRANCHES 等，
# 重复加载会在 set -e 下因 readonly 冲突直接中断。
[[ -n ${_WF_HOOKS_LOADED:-} ]] && return 0
_WF_HOOKS_LOADED=1
# lib/hooks.sh —— 团队钩子的安装、校验与自检
#
# 本库承载课 12 的三个核心实测结论，全部是踩过坑才写进来的：
#   ① 钩子没有执行权限 → Git 只打印一行 hint，提交照样成功（exit 0）
#   ② git grep 的 --cached 必须放在模式之前，写反了 exit 128，
#      而 if 会把它当成"没找到"，钩子静默放行
#   ③ 钩子文件里若含有被检查的关键词，不排除钩子目录会"自咬"，
#      导致干净提交也被拦
# 因此 install 之后必须有 wf_hooks_selftest：装了不等于生效。

WF_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$WF_LIB_DIR/core.sh"

# 受保护分支（课 11：可以/不能 force 的清单，由 pre-push 强制执行）
readonly WF_PROTECTED_BRANCHES='^(master|main|release/.*)$'
# 提交主题行规范（课 9：Conventional Commits）
readonly WF_COMMIT_RE='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .+'
# 禁止入库的调试残留（课 12 实测：钩子"自咬"的元凶）
readonly WF_DEBUG_PATTERN='console\.log|debugger|TODO-FIXME|BEGIN RSA PRIVATE KEY'

# ── 生成 pre-commit 钩子 ───────────────────────────────────
# ⚠️ 注意 grep 的参数顺序与自咬排除，见本文件头部注释 ② ③。
wf_hook_precommit_body() {
    cat <<'HOOK'
#!/usr/bin/env bash
set -uo pipefail

# ── 1. 调试残留检查 ────────────────────────────────────────
# ⚠️ 关键 1：--cached 必须放在模式之前。
#    git grep PATTERN --cached 会报 exit 128（unable to resolve revision），
#    而下面的 if 会把 128 当成"没找到" → 钩子静默放行，等于没装。
# ⚠️ 关键 2：pathspec 排除 .git，否则钩子文件里的 console.log 字样会命中自己。
if git grep --cached -n -E -I \
        -e 'console\.log' -e 'debugger' -e 'TODO-FIXME' \
        -e 'BEGIN RSA PRIVATE KEY' \
        -- . ':(exclude).git' >/dev/null 2>&1; then
    echo "pre-commit: 检出调试残留或私钥，已阻止提交"
    git grep --cached -n -E -I \
        -e 'console\.log' -e 'debugger' -e 'TODO-FIXME' \
        -e 'BEGIN RSA PRIVATE KEY' \
        -- . ':(exclude).git' >&2
    exit 1
fi

# ── 2. 大文件检查（阈值 512KB）─────────────────────────────
# 查暂存区（--cached）里的 blob 实际字节数。
# 数据来源 git ls-files -s：<mode> <sha> <stage> <path>
# ⚠️ 必须用 -z + read -d $'\0'：文件名可能含空格，默认按空格切分会读错路径。
# ⚠️ 这里不能写成 read -d '' —— 本文件是 heredoc，空字符串的两个引号会
#    被 bash 当成配对引号，导致 heredoc 提前结束（本项目实测踩到）。
while IFS= read -r -d $'\0' rec; do
    [[ -n $rec ]] || continue
    sha=$(printf '%s' "$rec" | cut -d' ' -f2)
    path=$(printf '%s' "$rec" | cut -d' ' -f4-)
    [[ -n $sha ]] || continue
    size=$(git cat-file -s "$sha" 2>/dev/null || printf '0')
    if (( size > 512 * 1024 )); then
        echo "pre-commit: 文件超过 512KB（${size} 字节）：$path" >&2
        echo "            大文件请走 LFS，或加入 .gitignore" >&2
        exit 1
    fi
done < <(git ls-files -s -z --cached)

exit 0
HOOK
}

# ── 生成 commit-msg 钩子 ───────────────────────────────────
wf_hook_commitmsg_body() {
    cat <<'HOOK'
#!/usr/bin/env bash
set -uo pipefail

msg_file="${1:-}"
[[ -n $msg_file && -f $msg_file ]] || exit 0

# 跳过 merge / revert 等自动生成的提交信息：
# 它们不是人写的，按规范校验会产生大量假阳性。
first_line=$(head -1 -- "$msg_file")
case "$first_line" in
    Merge*|Revert*|"Merge pull request"*) exit 0 ;;
esac

# Conventional Commits：type(optional-scope)!?: subject
if ! printf '%s' "$first_line" | grep -qE '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .+'; then
    echo "commit-msg: 提交信息不符合 Conventional Commits" >&2
    echo "            实际：$first_line" >&2
    echo "            应为：feat(scope): 简短描述" >&2
    exit 1
fi

# 主题行长度（含 scope，留一点余量给中文）
if (( ${#first_line} > 72 )); then
    echo "commit-msg: 主题行 ${#first_line} 字符，超过 72" >&2
    exit 1
fi

exit 0
HOOK
}

# ── 生成 pre-push 钩子 ─────────────────────────────────────
# 课 11 的"可以/不能 force 清单"在这里从人工约定变成机器强制。
# ⚠️ 客户端钩子拦不住 --no-verify，真正的强制必须靠服务端。
wf_hook_prepush_body() {
    cat <<'HOOK'
#!/usr/bin/env bash
set -uo pipefail

# pre-push 的 stdin 格式：<local ref> <local sha> <remote ref> <remote sha>
# 每行一个待推送的 ref，必须逐行读，不能只看第一行。
while read -r local_ref local_sha remote_ref remote_sha; do
    [[ -n $local_ref ]] || continue

    branch="${remote_ref#refs/heads/}"

    # 1. 保护分支：禁止直接推送（应走 PR）
    if printf '%s' "$branch" | grep -qE '^(master|main|release/.*)$'; then
        echo "pre-push: $branch 是受保护分支，禁止直接推送，请走 PR" >&2
        exit 1
    fi

    # 2. 禁止对保护分支做非快进更新（force push）
    #    remote_sha 全零 = 新建分支，不算 force
    if [[ $remote_sha =~ ^0+$ ]]; then
        continue
    fi
    if printf '%s' "$branch" | grep -qE '^(master|main|release/.*)$'; then
        if ! git merge-base --is-ancestor "$remote_sha" "$local_sha" 2>/dev/null; then
            echo "pre-push: 对 $branch 的更新不是快进，疑似 force push，已阻止" >&2
            exit 1
        fi
    fi
done

exit 0
HOOK
}

# ── 安装钩子 ───────────────────────────────────────────────
# 返回 0=安装成功。⚠️ 安装成功 ≠ 生效，必须再跑 wf_hooks_selftest。
wf_hooks_install() {
    local dir="$1" mode="${2:-hooksPath}"
    local hooks_dir

    case "$mode" in
        hooksPath)  hooks_dir="$dir/.githooks" ;;
        dotgit)     hooks_dir="$dir/.git/hooks" ;;
        *)          die "$WF_USAGE" "未知安装模式: $mode（可选 hooksPath / dotgit）" ;;
    esac

    mkdir -p -- "$hooks_dir"

    wf_hook_precommit_body  > "$hooks_dir/pre-commit"
    wf_hook_commitmsg_body  > "$hooks_dir/commit-msg"
    wf_hook_prepush_body    > "$hooks_dir/pre-push"

    # ⚠️ 课 12 实测结论 ①：没有执行位，Git 只打印 hint，提交照样成功。
    chmod +x -- "$hooks_dir/pre-commit" "$hooks_dir/commit-msg" "$hooks_dir/pre-push"

    if [[ $mode == hooksPath ]]; then
        git -C "$dir" config core.hooksPath .githooks
    fi
    hp_now=$(git -C "$dir" config --get core.hooksPath 2>/dev/null || printf 'unset')
    log_info "钩子已安装到 $hooks_dir core.hooksPath=$hp_now"
}
# ── 钩子自检：装了真的生效吗？──────────────────────────────
# 这是本项目最重要的一个函数。它把"以为在保护"和"真的在保护"分开。
# 做法：造一个必然违规的提交，看退出码是不是非 0。
wf_hooks_selftest() {
    local dir="$1"
    local rc=0

    # --- 自检 1：pre-commit 能否拦住调试残留 ---
    # Pitfall: if the probe never reaches the index (e.g. ignored by
    # .gitignore), `git commit` fails with "nothing to commit" and a naive
    # check would misread that failure as "the hook blocked it".
    # So: verify the probe is staged BEFORE judging the hook.
    printf 'console.log("probe")\n' > "$dir/.wf-selftest-probe.js"
    git -C "$dir" add -f -- .wf-selftest-probe.js
    if ! git -C "$dir" diff --cached --quiet -- .wf-selftest-probe.js; then
        if git -C "$dir" commit -q -m 'test: probe pre-commit' >/dev/null 2>&1; then
            finding_add BLOCK hooks "pre-commit 未拦住调试残留（钩子可能没有执行位或未被加载）"
            rc=1
        else
            finding_add OK hooks "pre-commit 成功拦住调试残留"
        fi
    else
        finding_add BLOCK hooks "自检前置失败：探针未进入暂存区（被 .gitignore 排除？）"
        rc=1
    fi
    git -C "$dir" reset -q --hard HEAD 2>/dev/null || true
    rm -f -- "$dir/.wf-selftest-probe.js"

    # --- 自检 2：commit-msg 能否拦住不规范信息 ---
    #    用一个合规的改动内容，只让"提交信息"违规，以隔离变量
    printf 'probe\n' > "$dir/.wf-selftest-msg.txt"
    git -C "$dir" add -f -- .wf-selftest-msg.txt
    if ! git -C "$dir" diff --cached --quiet -- .wf-selftest-msg.txt; then
        if git -C "$dir" commit -q -m '改了点东西' >/dev/null 2>&1; then
            finding_add BLOCK hooks "commit-msg 未拦住不规范提交信息"
            rc=1
        else
            finding_add OK hooks "commit-msg 成功拦住不规范提交信息"
        fi
    else
        finding_add BLOCK hooks "自检前置失败：msg 探针未进入暂存区"
        rc=1
    fi
    git -C "$dir" reset -q --hard HEAD 2>/dev/null || true
    rm -f -- "$dir/.wf-selftest-msg.txt"

    return "$rc"
}

# ── 取证：列出钩子及其状态 ─────────────────────────────────
wf_hooks_report() {
    local dir="$1"
    local hp
    hp=$(git -C "$dir" config --get core.hooksPath 2>/dev/null || true)
    printf '  core.hooksPath : %s\n' "${hp:-<未设置，使用 .git/hooks>}"
    local base="$dir/${hp:-.git/hooks}"
    local h
    for h in pre-commit commit-msg pre-push; do
        if [[ -f $base/$h ]]; then
            if [[ -x $base/$h ]]; then
                printf '  %-12s : 存在且可执行 ✅\n' "$h"
            else
                printf '  %-12s : 存在但无执行位 ❌（Git 只给 hint，提交仍会成功）\n' "$h"
            fi
        else
            printf '  %-12s : 缺失 ❌\n' "$h"
        fi
    done
}
