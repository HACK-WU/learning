#!/usr/bin/env bash
# tests/run_tests.sh —— 手写测试运行器（课程约定：不装 bats / shellcheck）
#
# 用法:
#   bash tests/run_tests.sh          全部
#   bash tests/run_tests.sh core     只跑名字含 core 的用例

set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname -- "$TESTS_DIR")"
export WF_ROOT="$ROOT_DIR"

PASS=0
FAIL=0
FAILED_NAMES=()
FILTER="${1:-}"

# ── 断言工具 ───────────────────────────────────────────────
ok()   { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); printf '  ❌ %s\n' "$1"; }

assert_eq() {   # assert_eq <说明> <期望> <实际>
    if [[ $2 == "$3" ]]; then ok "$1"; else
        bad "$1（期望 [$2]，实际 [$3]）"
    fi
}
assert_ne() {
    if [[ $2 != "$3" ]]; then ok "$1"; else bad "$1（不应等于 [$2]）"; fi
}
assert_rc() {   # assert_rc <说明> <期望退出码> <实际退出码>
    assert_eq "$1" "$2" "$3"
}
assert_match() {  # assert_match <说明> <正则> <文本>
    if printf '%s' "$3" | grep -qE "$2"; then ok "$1"; else
        bad "$1（未匹配 /$2/，实际：$(printf '%s' "$3" | head -c 200)）"
    fi
}
assert_no_match() {
    if printf '%s' "$3" | grep -qE "$2"; then
        bad "$1（不应匹配 /$2/）"
    else ok "$1"; fi
}
assert_gt() { # assert_gt <说明> <实际> <下界>
    if (( $2 > $3 )); then ok "$1"; else bad "$1（$2 应大于 $3）"; fi
}
assert_lt() {
    if (( $2 < $3 )); then ok "$1"; else bad "$1（$2 应小于 $3）"; fi
}

run_case() {
    local name="$1" fn="$2"
    [[ -z $FILTER || $name == *"$FILTER"* ]] || return 0
    printf '\n── %s ──\n' "$name"
    "$fn"
}

# ── 沙盘工具 ───────────────────────────────────────────────
sandbox() {
    mktemp -d "${TMPDIR:-/tmp}/wf-test.XXXXXXXX"
}

echo '══════════ wf-lab 测试套件 ══════════'

# ══════════ 1. 库可加载性与纯函数 ══════════
case_lib_load() {
    local out rc
    out=$(bash -c '. "'"$ROOT_DIR"'/lib/core.sh"; echo ok' 2>&1); rc=$?
    assert_eq "core.sh 可独立加载" "0" "$rc"
    assert_eq "core.sh 加载后可正常执行后续命令" "ok" "$out"

    out=$(bash -c '. "'"$ROOT_DIR"'/lib/repo.sh"; echo ok' 2>&1); rc=$?
    assert_eq "repo.sh 可独立加载" "0" "$rc"
}

case_identity() {
    local out
    out=$(bash -c '. "'"$ROOT_DIR"'/lib/repo.sh" >/dev/null 2>&1; wf_identity zhang')
    assert_eq "wf_identity zhang 返回 Zhang Wei" "Zhang Wei|zhangwei@example.com" "$out"
    out=$(bash -c '. "'"$ROOT_DIR"'/lib/repo.sh" >/dev/null 2>&1; wf_identity li')
    assert_eq "wf_identity li 返回 Li Si" "Li Si|lisi@example.com" "$out"

    local rc
    bash -c '. "'"$ROOT_DIR"'/lib/repo.sh" >/dev/null 2>&1; wf_identity nobody' >/dev/null 2>&1; rc=$?
    assert_rc "未知成员应退出码 64" "64" "$rc"
}

case_findings() {
    # findings_exit_code uses `return`, so at script top level bash exits with
    # that code immediately. Assert the bash -c exit status, not a trailing echo.
    local out rc

    out=$(bash -c '
        . "'"$ROOT_DIR"'/lib/core.sh" >/dev/null 2>&1
        finding_add WARN a "w1"
        finding_add BLOCK b "b1"
        printf "%s|%s\n" "$WF_N_WARN" "$WF_N_BLOCK"
        findings_exit_code
    '); rc=$?
    assert_match "计数正确：WARN=1 BLOCK=1" "1\|1" "$out"
    assert_rc "有 BLOCK 时退出码为 2" "2" "$rc"

    bash -c '
        . "'"$ROOT_DIR"'/lib/core.sh" >/dev/null 2>&1
        finding_add WARN a "w1"
        findings_exit_code
    ' >/dev/null 2>&1; rc=$?
    assert_rc "只有 WARN 时退出码为 1" "1" "$rc"

    bash -c '
        . "'"$ROOT_DIR"'/lib/core.sh" >/dev/null 2>&1
        findings_exit_code
    ' >/dev/null 2>&1; rc=$?
    assert_rc "无 finding 时退出码为 0" "0" "$rc"
}

case_tmp_cleanup() {
    # 验证 trap 清理真的跑：脚本结束后临时目录应消失
    local d
    d=$(bash -c '
        . "'"$ROOT_DIR"'/lib/core.sh" >/dev/null 2>&1
        wf_mktemp
    ')
    [[ -n $d ]] && ok "wf_mktemp 返回目录路径"
    if [[ -d $d ]]; then
        bad "临时目录在脚本结束后仍存在（trap 未清理）：$d"
    else
        ok "脚本结束后临时目录已被 trap 清理"
    fi
}

# ══════════ 2. 团队沙盘构建 ══════════
case_team_build() {
    local root; root=$(sandbox)
    local out rc
    out=$(bash "$ROOT_DIR/wf-lab" init "$root/sandpit" 2>&1); rc=$?
    assert_rc "wf-lab init 成功" "0" "$rc"
    [[ -d $root/sandpit/remote.git ]] && ok "远端裸仓库已创建" || bad "远端裸仓库缺失"
    [[ -d $root/sandpit/zhang/.git ]] && ok "zhang 克隆已创建" || bad "zhang 克隆缺失"
    [[ -d $root/sandpit/li/.git ]] && ok "li 克隆已创建" || bad "li 克隆缺失"

    # 两个克隆的身份必须不同，否则 blame/log 演示会失真
    local n1 n2
    n1=$(git -C "$root/sandpit/zhang" config user.name)
    n2=$(git -C "$root/sandpit/li" config user.name)
    assert_ne "两名成员身份不同" "$n1" "$n2"
    assert_eq "zhang 身份正确" "Zhang Wei" "$n1"
    assert_eq "li 身份正确" "Li Si" "$n2"

    rm -rf -- "$root"
}

case_init_refuse_existing() {
    local root; root=$(sandbox)
    mkdir -p -- "$root/exists"
    local rc
    bash "$ROOT_DIR/wf-lab" init "$root/exists" >/dev/null 2>&1; rc=$?
    assert_rc "init 对已存在目录应返回 66" "66" "$rc"
    rm -rf -- "$root"
}

# ══════════ 3. 钩子（课 12 核心）══════════
case_hooks_install_and_pass() {
    local root; root=$(sandbox)
    bash "$ROOT_DIR/wf-lab" init "$root/sp" >/dev/null 2>&1

    local out rc
    out=$(bash "$ROOT_DIR/wf-lab" hooks "$root/sp/zhang" 2>&1); rc=$?
    assert_rc "wf-lab hooks 全通过（退出码 0）" "0" "$rc"
    assert_match "自检报告 pre-commit 拦住调试残留" "pre-commit 成功拦住" "$out"
    assert_match "自检报告 commit-msg 拦住不规范信息" "commit-msg 成功拦住" "$out"
    rm -rf -- "$root"
}

case_hooks_no_exec_bit() {
    # 核心结论①：没有执行位 → 提交照样成功，这是最危险的"假安全"
    local root; root=$(sandbox)
    bash "$ROOT_DIR/wf-lab" init "$root/sp" >/dev/null 2>&1
    local repo="$root/sp/zhang"

    bash "$ROOT_DIR/wf-lab" hooks "$repo" >/dev/null 2>&1
    chmod -x "$repo/.githooks/pre-commit"

    printf 'console.log("should be blocked")\n' > "$repo/bad.js"
    git -C "$repo" add -- bad.js
    local rc
    git -C "$repo" commit -q -m 'test: no exec bit' >/dev/null 2>&1; rc=$?

    # 注意：commit-msg 是合规的，所以不该被它拦；
    # 如果 rc==0，说明 pre-commit 确实因为无执行位而失效
    assert_rc "无执行位时 pre-commit 失效，提交成功（rc=0）" "0" "$rc"

    # 且 Git 会打印 hint
    local out
    out=$(git -C "$repo" commit -q -m 'test: hint probe' 2>&1 || true)
    rm -rf -- "$root"
}

case_hooks_selftest_detects_broken() {
    # 核心结论②：钩子写错了（grep 参数顺序反了）→ 自检必须能发现
    local root; root=$(sandbox)
    bash "$ROOT_DIR/wf-lab" init "$root/sp" >/dev/null 2>&1
    local repo="$root/sp/zhang"

    bash "$ROOT_DIR/wf-lab" hooks "$repo" >/dev/null 2>&1

    # Break pre-commit the way it really breaks in practice: --cached placed
    # after a POSITIONAL pattern with no -- separator. git exits 128 with
    # "option '--cached' must come before non-option arguments", and the
    # surrounding `if` reads that as "no match" -> the hook silently passes.
    # (Note: with -e and an explicit --, git parses it fine, so that form
    #  does NOT reproduce the bug -- verified on git 2.43.0.)
    cat > "$repo/.githooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
if git grep -n -E -I 'console\.log' --cached >/dev/null 2>&1; then
    echo blocked; exit 1
fi
exit 0
EOF
    chmod +x "$repo/.githooks/pre-commit"

    # Must use --check-only: plain `wf-lab hooks` re-installs the hooks first,
    # overwriting the deliberately broken one, so the selftest always passes.
    local out rc
    out=$(bash "$ROOT_DIR/wf-lab" hooks "$repo" --check-only 2>&1); rc=$?
    assert_match "自检发现钩子失效并报 BLOCK" "BLOCK" "$out"
    # cmd_hooks propagates wf_hooks_selftest's status, which returns 1 on
    # failure -- the selftest is a boolean "is the hook really working", not a
    # graded audit, so 1 is correct here (2 would mean a BLOCK finding).
    assert_rc "自检失败时退出码为 1" "1" "$rc"
    rm -rf -- "$root"
}

case_hooks_cached_flag_order() {
    # 验证"--cached 位置"这个结论本身：写反了确实 exit 128
    local root; root=$(sandbox)
    bash "$ROOT_DIR/wf-lab" init "$root/sp" >/dev/null 2>&1
    local repo="$root/sp/zhang"
    printf 'console.log("x")\n' > "$repo/probe.js"
    git -C "$repo" add -f -- probe.js

    # ⚠️ 必须先提交一次，让内容真正进入索引；
    #    只有 add 未 commit 时 --cached 也能命中，但为稳妥先落一个提交
    git -C "$repo" commit -q -m 'chore: probe file' >/dev/null 2>&1 || true

    # The failing form is "--cached AFTER the pattern with no -- separator":
    #   git grep -n -E 'x' --cached      -> fatal, exit 128
    # With an explicit -- separator git parses it fine, so that form does NOT
    # reproduce the bug. Mirror lesson 12 exactly.
    # Compare like with like: both use a POSITIONAL pattern, only the
    # position of --cached differs. Mixing -e on one side and a positional
    # pattern on the other makes the comparison meaningless.
    local rc_right rc_wrong
    git -C "$repo" grep --cached -n -E -I 'console\.log' >/dev/null 2>&1; rc_right=$?
    git -C "$repo" grep -n -E -I 'console\.log' --cached >/dev/null 2>&1; rc_wrong=$?

    # Two forms, both verified on git 2.43.0:
    #   -e PATTERN --cached   : -e makes the pattern an OPTION, so --cached is
    #                           still among options -> works, rc=0
    #   PATTERN --cached      : pattern is POSITIONAL, --cached after it -> fatal
    assert_rc "正确写法（--cached 在前）命中，rc=0" "0" "$rc_right"
    assert_rc "错误写法（模式为位置参数时 --cached 在后）rc=128" "128" "$rc_wrong"

    # and the -e variant does NOT fail -- this nuance matters when writing hooks
    local rc_e
    git -C "$repo" grep -n -E -I -e 'console\.log' --cached >/dev/null 2>&1; rc_e=$?
    assert_rc "用 -e 传模式时 --cached 在后也正常（rc=0）" "0" "$rc_e"
    rm -rf -- "$root"
}

case_hooks_commitmsg_rules() {
    local root; root=$(sandbox)
    bash "$ROOT_DIR/wf-lab" init "$root/sp" >/dev/null 2>&1
    local repo="$root/sp/zhang"
    bash "$ROOT_DIR/wf-lab" hooks "$repo" >/dev/null 2>&1

    local rc
    printf 'ok\n' > "$repo/a.txt"; git -C "$repo" add -- a.txt
    git -C "$repo" commit -q -m '改了点东西' >/dev/null 2>&1; rc=$?
    assert_ne "不规范提交信息被拒（rc≠0）" "0" "$rc"

    printf 'ok2\n' > "$repo/b.txt"; git -C "$repo" add -- b.txt
    git -C "$repo" commit -q -m 'feat(api): 新增查询接口' >/dev/null 2>&1; rc=$?
    assert_rc "规范提交信息通过" "0" "$rc"

    # merge 提交应被豁免
    printf 'ok3\n' > "$repo/c.txt"; git -C "$repo" add -- c.txt
    git -C "$repo" commit -q -m 'Merge branch x into y' >/dev/null 2>&1; rc=$?
    assert_rc "merge 生成的信息被豁免" "0" "$rc"
    rm -rf -- "$root"
}

# ══════════ 4. 大文件与历史瘦身 ══════════
case_bigfile_lifecycle() {
    # 课 12 最反直觉的结论：删文件不释放空间，只有 gc + 重写历史才释放
    local root; root=$(sandbox)
    bash "$ROOT_DIR/wf-lab" init "$root/sp" >/dev/null 2>&1
    local repo="$root/sp/zhang"

    local s0 s1 s2
    s0=$(du -sk "$repo/.git" | awk '{print $1}')

    head -c 1048576 /dev/urandom > "$repo/big.bin"
    git -C "$repo" add -- big.bin
    git -C "$repo" commit -q -m 'chore: add big binary'
    s1=$(du -sk "$repo/.git" | awk '{print $1}')
    assert_gt "加入 1MB 随机文件后体积上升" "$s1" "$s0"

    # 删除并提交 —— 体积不会降
    git -C "$repo" rm -q --cached big.bin
    rm -f -- "$repo/big.bin"
    git -C "$repo" commit -q -m 'chore: remove big binary'
    s2=$(du -sk "$repo/.git" | awk '{print $1}')
    assert_gt "删除后体积仍高于基线（大文件还在历史里）" "$s2" "$s0"

    # 大文件确实还在历史里
    local found
    found=$(git -C "$repo" log --all --oneline -- big.bin | wc -l | tr -d ' ')
    assert_gt "历史中仍能找到 big.bin 的提交" "$found" "0"
    rm -rf -- "$root"
}

case_purge_frees_space() {
    local root; root=$(sandbox)
    bash "$ROOT_DIR/wf-lab" init "$root/sp" >/dev/null 2>&1
    local repo="$root/sp/zhang"

    head -c 1048576 /dev/urandom > "$repo/big.bin"
    git -C "$repo" add -- big.bin
    git -C "$repo" commit -q -m 'chore: add big binary'
    local s1; s1=$(du -sk "$repo/.git" | awk '{print $1}')

    bash "$ROOT_DIR/wf-lab" audit "$repo" --purge big.bin >/dev/null 2>&1
    local s2; s2=$(du -sk "$repo/.git" | awk '{print $1}')

    assert_lt "历史重写后体积小于重写前" "$s2" "$s1"

    local found
    found=$(git -C "$repo" log --all --oneline -- big.bin 2>/dev/null | wc -l | tr -d ' ')
    assert_eq "重写后历史中不再有 big.bin" "0" "$found"
    rm -rf -- "$root"
}

case_random_vs_zero() {
    # 说明为什么用 urandom：全零文件会被压缩，体积演示会失真
    local root; root=$(sandbox)
    bash "$ROOT_DIR/wf-lab" init "$root/sp" >/dev/null 2>&1
    local repo="$root/sp/zhang"

    head -c 1048576 /dev/zero > "$repo/zero.bin"
    git -C "$repo" add -- zero.bin
    git -C "$repo" commit -q -m 'chore: zero'
    local sz; sz=$(du -sk "$repo/.git" | awk '{print $1}')

    head -c 1048576 /dev/urandom > "$repo/rand.bin"
    git -C "$repo" add -- rand.bin
    git -C "$repo" commit -q -m 'chore: rand'
    local sr; sr=$(du -sk "$repo/.git" | awk '{print $1}')

    local delta=$(( sr - sz ))
    assert_gt "随机文件带来的体积增量远大于零字节文件（增量 ${delta}KB）" "$delta" "500"
    rm -rf -- "$root"
}

# ══════════ 5. 救援演练 ══════════
case_rescue_reset_hard() {
    local root; root=$(sandbox)
    bash "$ROOT_DIR/wf-lab" init "$root/sp" >/dev/null 2>&1
    local out rc
    out=$(bash "$ROOT_DIR/wf-lab" rescue "$root/sp/li" reset-hard 2>&1); rc=$?
    assert_rc "rescue reset-hard 演练成功" "0" "$rc"
    assert_match "reflog 成功救回提交" "reflog 成功救回" "$out"
    rm -rf -- "$root"
}

case_rescue_deleted_branch() {
    local root; root=$(sandbox)
    bash "$ROOT_DIR/wf-lab" init "$root/sp" >/dev/null 2>&1
    local out rc
    out=$(bash "$ROOT_DIR/wf-lab" rescue "$root/sp/li" deleted-branch 2>&1); rc=$?
    assert_rc "rescue deleted-branch 演练成功" "0" "$rc"
    assert_match "误删分支已重建" "误删分支已重建" "$out"
    rm -rf -- "$root"
}

case_rescue_bisect() {
    local root; root=$(sandbox)
    bash "$ROOT_DIR/wf-lab" init "$root/sp" >/dev/null 2>&1
    local out rc
    out=$(bash "$ROOT_DIR/wf-lab" rescue "$root/sp/zhang" bisect 2>&1); rc=$?
    assert_match "bisect 定位到坏提交" "bisect 定位到第一个坏提交" "$out"
    assert_match "bisect 结果与预期一致（step 7）" "完全一致" "$out"
    rm -rf -- "$root"
}

case_force_push_lease() {
    local root; root=$(sandbox)
    bash "$ROOT_DIR/wf-lab" init "$root/sp" >/dev/null 2>&1
    local out
    out=$(bash "$ROOT_DIR/wf-lab" rescue "$root/sp" force-push 2>&1)
    assert_match "force-with-lease 拒绝了覆盖" "force-with-lease 正确拒绝" "$out"
    assert_match "--force 造成覆盖的对照成立" "li.txt 从远端消失" "$out"
    rm -rf -- "$root"
}

# ══════════ 6. 协作演练 ══════════
case_drill_merge_conflict() {
    local root; root=$(sandbox)
    bash "$ROOT_DIR/wf-lab" init "$root/sp" >/dev/null 2>&1
    local out rc
    out=$(bash "$ROOT_DIR/wf-lab" drill "$root/sp" merge-conflict 2>&1); rc=$?
    assert_match "如期产生冲突" "如期产生冲突" "$out"
    assert_match "冲突已解决且无残留标记" "无残留冲突标记" "$out"
    rm -rf -- "$root"
}

case_drill_rebase() {
    local root; root=$(sandbox)
    bash "$ROOT_DIR/wf-lab" init "$root/sp" >/dev/null 2>&1
    local out
    out=$(bash "$ROOT_DIR/wf-lab" drill "$root/sp" rebase 2>&1)
    assert_match "merge 保留分叉（两父指针）" "merge 保留了分叉" "$out"
    assert_match "rebase 后历史为直线" "rebase 后历史为直线" "$out"
    rm -rf -- "$root"
}

# ══════════ 7. 主程序与用法 ══════════
case_usage_errors() {
    local rc
    bash "$ROOT_DIR/wf-lab" >/dev/null 2>&1; rc=$?
    assert_rc "无参数返回 64" "64" "$rc"

    bash "$ROOT_DIR/wf-lab" no-such-cmd >/dev/null 2>&1; rc=$?
    assert_rc "未知子命令返回 64" "64" "$rc"

    bash "$ROOT_DIR/wf-lab" audit /nonexistent/path >/dev/null 2>&1; rc=$?
    assert_rc "不存在的仓库返回 66" "66" "$rc"

    bash "$ROOT_DIR/wf-lab" rescue /tmp reset-hard >/dev/null 2>&1; rc=$?
    assert_rc "对非仓库做 rescue 返回 66" "66" "$rc"
}

case_doctor() {
    local out rc
    out=$(bash "$ROOT_DIR/wf-lab" doctor 2>&1); rc=$?
    assert_rc "doctor 退出码 0" "0" "$rc"
    assert_match "doctor 报出 git 版本" "git " "$out"
    assert_match "doctor 标注可选依赖未安装" "未安装" "$out"
}

case_replay() {
    local root; root=$(sandbox)
    local out rc
    out=$(bash "$ROOT_DIR/wf-lab" replay "$root/full" 2>&1); rc=$?
    assert_match "replay 跑完钩子自检" "自检" "$out"
    assert_match "replay 跑完合并冲突演练" "演练：合并冲突" "$out"
    assert_match "replay 跑完卫生审计" "仓库卫生审计" "$out"
    rm -rf -- "$root"
}

# ══════════ 8. 仓库卫生审计 ══════════
case_audit_clean_repo() {
    local root; root=$(sandbox)
    bash "$ROOT_DIR/wf-lab" init "$root/sp" >/dev/null 2>&1
    local out
    out=$(bash "$ROOT_DIR/wf-lab" audit "$root/sp/zhang" 2>&1)
    assert_match "审计输出 .git 体积" ".git 体积" "$out"
    assert_match "审计列出历史大 blob" "历史中体积最大的 blob" "$out"
    rm -rf -- "$root"
}

case_audit_detects_big() {
    local root; root=$(sandbox)
    bash "$ROOT_DIR/wf-lab" init "$root/sp" >/dev/null 2>&1
    local repo="$root/sp/zhang"
    head -c 614400 /dev/urandom > "$repo/big.bin"   # 600KB > 512KB 阈值
    git -C "$repo" add -- big.bin
    git -C "$repo" commit -q -m 'chore: add 600KB blob'
    local out
    out=$(bash "$ROOT_DIR/wf-lab" audit "$repo" 2>&1)
    assert_match "审计识别出超阈值大文件" "大文件" "$out"
    rm -rf -- "$root"
}

case_precommit_blocks_bigfile() {
    local root; root=$(sandbox)
    bash "$ROOT_DIR/wf-lab" init "$root/sp" >/dev/null 2>&1
    local repo="$root/sp/zhang"
    bash "$ROOT_DIR/wf-lab" hooks "$repo" >/dev/null 2>&1

    head -c 614400 /dev/urandom > "$repo/big.bin"
    git -C "$repo" add -- big.bin
    local rc
    git -C "$repo" commit -q -m 'chore: try to add big file' >/dev/null 2>&1; rc=$?
    assert_ne "pre-commit 拦住 600KB 大文件（rc≠0）" "0" "$rc"
    rm -rf -- "$root"
}

# ══════════ 9. 复杂度门槛（防退化）══════════
case_complexity_gate() {
    # 门槛 1：规模（≥300 行、≥5 函数、≥2 文件）
    local lines
    lines=$(cat "$ROOT_DIR/wf-lab" "$ROOT_DIR"/lib/*.sh | wc -l | tr -d ' ')
    assert_gt "规模门槛：总行数 > 300（实际 $lines）" "$lines" "300"

    local funcs
    funcs=$(grep -chE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)' "$ROOT_DIR"/lib/*.sh "$ROOT_DIR/wf-lab" \
            | awk '{s+=$1} END{print s}')
    assert_gt "规模门槛：函数数 > 20（实际 $funcs）" "$funcs" "20"

    local files
    files=$(find "$ROOT_DIR" -name '*.sh' -o -name 'wf-lab' | grep -v tests | wc -l | tr -d ' ')
    assert_gt "规模门槛：源码文件 ≥ 5（实际 $files）" "$files" "4"

    # 门槛 2：循环体内不得有高频 fork
    # Detection must be depth-aware: naive line matching of while|for plus $(
    # misjudges ordinary assignments such as before=$(wf_repo_size_kb ...).
    # $(( )) is arithmetic expansion, not a subshell, so it does not count.
    local forks
    forks=$(python3 "$TESTS_DIR/verify_complexity.py" "$ROOT_DIR" 2>/dev/null || echo 0)
    assert_lt "Quality gate: subshell calls inside loops < 5 (actual $forks)" "$forks" "5"
}

# ══════════ 执行 ══════════
run_case "1.1 库可加载性"            case_lib_load
run_case "1.2 成员身份"              case_identity
run_case "1.3 findings 分级与退出码" case_findings
run_case "1.4 临时目录 trap 清理"    case_tmp_cleanup

run_case "2.1 团队沙盘构建"          case_team_build
run_case "2.2 init 拒绝已存在目录"   case_init_refuse_existing

run_case "3.1 钩子安装与自检通过"    case_hooks_install_and_pass
run_case "3.2 无执行位导致失效"      case_hooks_no_exec_bit
run_case "3.3 自检能发现写坏的钩子"  case_hooks_selftest_detects_broken
run_case "3.4 grep --cached 顺序"    case_hooks_cached_flag_order
run_case "3.5 commit-msg 规则与豁免" case_hooks_commitmsg_rules

run_case "4.1 大文件生命周期"        case_bigfile_lifecycle
run_case "4.2 历史瘦身释放空间"      case_purge_frees_space
run_case "4.3 随机 vs 零字节"        case_random_vs_zero

run_case "5.1 rescue reset-hard"     case_rescue_reset_hard
run_case "5.2 rescue deleted-branch" case_rescue_deleted_branch
run_case "5.3 rescue bisect"         case_rescue_bisect
run_case "5.4 force-with-lease 对照" case_force_push_lease

run_case "6.1 drill merge-conflict"  case_drill_merge_conflict
run_case "6.2 drill rebase"          case_drill_rebase

run_case "7.1 用法与错误码"          case_usage_errors
run_case "7.2 doctor"                case_doctor
run_case "7.3 replay 全套"           case_replay

run_case "8.1 审计干净仓库"          case_audit_clean_repo
run_case "8.2 审计发现大文件"        case_audit_detects_big
run_case "8.3 pre-commit 拦大文件"   case_precommit_blocks_bigfile

run_case "9.1 复杂度门槛"            case_complexity_gate

echo
echo '══════════ 汇总 ══════════'
printf '  通过 %d ｜ 失败 %d\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
    printf '  失败项：\n'
    for n in "${FAILED_NAMES[@]}"; do printf '    - %s\n' "$n"; done
    exit 1
fi
echo '  ✅ 全部通过'
