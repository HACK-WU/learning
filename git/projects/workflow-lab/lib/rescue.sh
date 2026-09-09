#!/usr/bin/env bash
# ── include guard ─────────────────────────────────────────
# 防止重复 source：本文件定义了 全局状态，
# 重复加载会在 set -e 下因 readonly 冲突直接中断。
[[ -n ${_WF_RESCUE_LOADED:-} ]] && return 0
_WF_RESCUE_LOADED=1
# lib/rescue.sh —— 误操作救援：reflog 找回、误删分支、强推覆盖、丢失的 stash
#
# 课 11 的救援矩阵在这里变成"能真跑一遍"的演练：
#   每个 rescue 子命令都先制造事故，再用正确手法救回，并验证救回结果。
# 课 10 的 bisect 也纳入：定位坏提交不是靠肉眼扫日志。

WF_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$WF_LIB_DIR/core.sh"

# ── reflog 救援：找回被 reset --hard 丢掉的提交 ────────────
# 流程：造事故 → 用 reflog 找 sha → reset 回去 → 验证文件回来了
wf_rescue_reset_hard() {
    local dir="$1"
    local sha

    printf 'v1\n' > "$dir/lost.txt"
    git -C "$dir" add -A
    git -C "$dir" commit -q -m 'feat: add lost.txt (will be destroyed)'
    sha=$(git -C "$dir" rev-parse --short HEAD)

    # 制造事故：回退到上一个提交，工作区一并丢弃
    git -C "$dir" reset -q --hard HEAD~1
    printf '  事故已制造：reset --hard HEAD~1，lost.txt 消失\n'
    [[ -f $dir/lost.txt ]] && printf '  ⚠️ 文件仍在（异常）\n' || printf '  确认：lost.txt 已不存在\n'

    # 救援：reflog 里找那条提交
    local found
    found=$(git -C "$dir" reflog --format='%h %gd %gs' \
            | grep -F "commit: feat: add lost.txt" | head -1 | awk '{print $1}')
    [[ -n $found ]] || { finding_add BLOCK rescue "reflog 里找不到目标提交"; return 1; }
    printf '  reflog 找到：%s（原 sha %s）\n' "$found" "$sha"

    git -C "$dir" reset -q --hard "$found"

    if [[ -f $dir/lost.txt ]]; then
        finding_add OK rescue "reflog 成功救回被 reset --hard 删除的提交（内容：$(cat "$dir/lost.txt")）"
        return 0
    fi
    finding_add BLOCK rescue "reflog 救援失败"
    return 1
}

# ── 误删分支救援 ───────────────────────────────────────────
# 分支只是指针，删掉的是指针不是提交 —— 提交还在，靠 reflog 找。
wf_rescue_deleted_branch() {
    local dir="$1"
    local branch='feature/deleted-demo'

    git -C "$dir" checkout -q -b "$branch"
    printf 'branch-only content\n' > "$dir/branch-only.txt"
    git -C "$dir" add -A
    git -C "$dir" commit -q -m 'feat: work that lives only on this branch'
    local sha
    sha=$(git -C "$dir" rev-parse --short HEAD)

    git -C "$dir" checkout -q -
    git -C "$dir" branch -q -D "$branch"
    printf '  事故已制造：分支 %s 已被 -D 删除（原 HEAD %s）\n' "$branch" "$sha"

    # 救援：reflog 是"所有操作的飞行记录仪"，删分支也留痕
    local found
    found=$(git -C "$dir" reflog --format='%h %gs' \
            | grep -F "commit: feat: work that lives only on this branch" \
            | head -1 | awk '{print $1}')
    [[ -n $found ]] || { finding_add BLOCK rescue "reflog 中找不到被删分支的提交"; return 1; }

    git -C "$dir" branch "$branch" "$found"
    if git -C "$dir" rev-parse --verify --quiet "$branch" >/dev/null; then
        finding_add OK rescue "误删分支已重建：$branch → $found"
        return 0
    fi
    finding_add BLOCK rescue "分支重建失败"
    return 1
}

# ── 强推覆盖救援：用 force-with-lease 而非 --force ─────────
# 这是课 11 的核心边界：--force 不知道自己覆盖了什么，
# --force-with-lease 会在"远端已被别人更新"时拒绝推送。
wf_rescue_force_push_demo() {
    local root="$1"
    local zhang="$root/zhang" li="$root/li"

    # ── What --force-with-lease actually guarantees ──────────────────
    # It refuses when the REMOTE HAS MOVED since the moment we last fetched.
    # It does NOT check "does my history contain the remote's commits".
    # (Verified on git 2.43.0: with origin/master == remote tip, a divergent
    #  local branch is still pushed happily. That is by design.)
    #
    # So the drill must create the right ordering:
    #   1. zhang resets to an old base and commits  -> divergent from remote
    #   2. zhang fetches                            -> origin/master = tip (li)
    #   3. li pushes ANOTHER commit (after the fetch) -> remote moves on
    #   4. zhang push --force-with-lease            -> MUST be rejected
    local base
    base=$(git -C "$zhang" rev-parse HEAD)

    # 1) Li Si 先推一个提交，让远端领先
    git -C "$li" fetch -q origin 2>/dev/null || true
    git -C "$li" reset -q --hard origin/master 2>/dev/null \
        || git -C "$li" reset -q --hard origin/HEAD
    wf_commit "$li" 'feat(li): li 的第一个改动' 'li.txt' 'li v1'
    local li_rc=0
    git -C "$li" push -q origin HEAD:master 2>/dev/null || li_rc=$?
    if (( li_rc != 0 )); then
        finding_add BLOCK rescue "场景构造失败：Li Si 未能推送"
        return 1
    fi

    # 2) Zhang Wei 回到旧基点另起提交，然后 fetch
    git -C "$zhang" reset -q --hard "$base"
    wf_commit "$zhang" 'feat(zhang): 基于旧基点的改动' 'zhang.txt' 'zhang v1'
    git -C "$zhang" fetch -q origin

    # 3) 关键时序：Li Si 在 Zhang Wei fetch 之后又推了一个提交
    wf_commit "$li" 'feat(li): li 的第二个改动' 'li2.txt' 'li v2'
    git -C "$li" push -q origin HEAD:master 2>/dev/null || true

    printf '  场景已就绪：Zhang Wei fetch 后，Li Si 又推送了一个提交\n'

    # 4) lease 必须拒绝
    # lease 被拒时 push 返回非 0，在 set -e 下必须用 if 捕获，
    # 否则脚本在此中断，后面的对照与结论永远走不到。
    local out rc
    if out=$(git -C "$zhang" push --force-with-lease origin master:master 2>&1); then
        rc=0
    else
        rc=$?
    fi
    if (( rc != 0 )); then
        finding_add OK rescue "force-with-lease 正确拒绝了覆盖（远端在 fetch 之后又被更新）"
        printf '  git 的反馈：%s\n' \
            "$(printf '%s' "$out" | grep -iE 'stale|rejected|lease|fetch' | head -1)"
    else
        finding_add BLOCK rescue "force-with-lease 未拒绝，Li Si 的提交已被静默覆盖！"
    fi

    # 对照组：--force 会成功
    if out=$(git -C "$zhang" push --force origin master:master 2>&1); then
        rc=0
    else
        rc=$?
    fi
    if (( rc == 0 )); then
        git -C "$li" fetch -q origin 2>/dev/null || true
        if git -C "$li" cat-file -e "origin/master:li.txt" 2>/dev/null; then
            finding_add WARN rescue "对照：--force 推送成功但 li.txt 仍在"
        else
            finding_add OK rescue "对照确认：--force 后 li.txt 从远端消失，Li Si 的提交被覆盖"
        fi
    else
        finding_add WARN rescue "对照：--force 推送失败（rc=$rc）"
    fi

    # 补充：显式指定期望值，展示 lease 的精确语义
    finding_add WARN rescue "语义补充：lease 只保证'远端没在我 fetch 之后又动过'，不检查历史是否包含远端提交"
}

# ── bisect 定位坏提交（课 10）─────────────────────────────
# 造一串提交，其中一个引入"故障"，用 bisect run 自动二分。
wf_rescue_bisect_demo() {
    local dir="$1"
    # ⚠️ 探针必须放在仓库外：放在仓库里会变成未跟踪文件，
    #    而 bisect 要求工作区干净，bisect start 会直接拒绝并只打印 status。
    #    （本项目实测踩到：表现为"bisect 无输出、演练静默失败"）
    local probe
    probe="$(mktemp "${TMPDIR:-/tmp}/wf-bisect-probe.XXXXXX.sh")"
    local n=10 bad=7 i

    cat > "$probe" <<EOF
#!/usr/bin/env bash
# 判定"当前版本是否有故障"：version.txt 里写着 bad 即失败
# 探针在仓库外，改用绝对路径（bisect run 的 cwd 是仓库根）
grep -q 'bad' "$dir/version.txt" && exit 1
exit 0
EOF
    chmod +x -- "$probe"

    # Each commit must change the file: writing the same content again makes
    # git report "nothing to commit", so fewer than n commits are created and
    # HEAD~N then goes out of range (observed: "Bad rev input: HEAD~9").
    # Appending the step number guarantees every iteration produces a commit.
    for ((i = 1; i <= n; i++)); do
        if (( i >= bad )); then
            printf 'bad step=%d\n' "$i" > "$dir/version.txt"
        else
            printf 'good step=%d\n' "$i" > "$dir/version.txt"
        fi
        git -C "$dir" add -- version.txt
        git -C "$dir" commit -q -m "chore: version step $i"
    done

    # sanity: confirm n commits really exist before bisecting
    local have
    have=$(git -C "$dir" rev-list --count HEAD 2>/dev/null || echo 0)
    if (( have < n + 1 )); then
        finding_add WARN rescue "提交数不足（期望 >$n，实际 $have），bisect 范围可能受限"
    fi

    printf '  已构造 %d 个提交，第 %d 个引入故障\n' "$n" "$bad"

    # Each step must run separately: chaining them inside one $( ) with || true
    # swallowed the real failure (bisect start refuses when the tree is dirty).
    git -C "$dir" bisect reset >/dev/null 2>&1 || true
    git -C "$dir" bisect start >/dev/null 2>&1
    local start_rc=$?
    (( start_rc == 0 )) || {
        finding_add BLOCK rescue "bisect start 失败（工作区不干净？）"
        rm -f -- "$probe"
        return 1
    }

    git -C "$dir" bisect bad HEAD >/dev/null 2>&1
    git -C "$dir" bisect good "HEAD~$((n - 1))" >/dev/null 2>&1

    # bisect run exits non-zero when it FINDS a bad commit -- that is how it
    # reports success. Under set -e this kills the script, so wrap in if.
    local run_out
    if ! run_out=$(git -C "$dir" bisect run "$probe" 2>&1); then
        :
    fi
    printf '%s\n' "$run_out" | grep -E 'is the first bad commit' | head -2 | sed 's/^/  /'

    # extract sha before reset: BISECT_* state is cleared by bisect reset
    local found
    found=$(printf '%s\n' "$run_out" \
        | grep -oE '[0-9a-f]{7,40} is the first bad commit' \
        | awk '{print $1}' | head -1)
    if [[ -z $found ]]; then
        found=$(git -C "$dir" bisect log 2>/dev/null \
            | grep -A1 'first bad commit' | tail -1 | awk '{print $2}')
    fi
    git -C "$dir" bisect reset >/dev/null 2>&1 || true

    if [[ -n $found ]]; then
        local subject
        subject=$(git -C "$dir" log -1 --format=%s "$found" 2>/dev/null)
        finding_add OK rescue "bisect 定位到第一个坏提交：${subject:-$found}（预期 step $bad）"
        if [[ $subject == *"step $bad"* ]]; then
            finding_add OK rescue "bisect 结果与预期完全一致"
        else
            finding_add WARN rescue "bisect 结果与预期不符：实际 $subject"
        fi
    else
        finding_add BLOCK rescue "bisect 未能定位坏提交"
    fi
    rm -f -- "$probe"
}
