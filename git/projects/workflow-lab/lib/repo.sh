#!/usr/bin/env bash
# ── include guard ─────────────────────────────────────────
# 防止重复 source：本文件定义了 readonly 常量 WF_DEV_LEAD / WF_EMAIL_DOMAIN，
# 重复加载会在 set -e 下因 readonly 冲突直接中断。
[[ -n ${_WF_REPO_LOADED:-} ]] && return 0
_WF_REPO_LOADED=1
# lib/repo.sh —— 模拟团队仓库的构建：裸仓库（充当远端）+ 多个成员克隆
#
# 设计要点：整个课程不依赖任何托管平台，远端一律用 file:// 协议的本地裸仓库。
# 这样"推送/拉取/冲突/强推/救援"全都能在本机真实发生，而不是靠文字描述。

# shellcheck source=core.sh
WF_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$WF_LIB_DIR/core.sh"

# 课程约定的人名（与讲义一致，避免 Alice/Bob）
readonly WF_DEV_LEAD='Zhang Wei'
readonly WF_DEV_MATE='Li Si'
readonly WF_EMAIL_DOMAIN='example.com'

# ── 成员身份 ───────────────────────────────────────────────
# 每个克隆都是独立仓库，必须各自设 user.name/email，
# 否则提交者身份会串，blame 与 log 的演示就失真了。
wf_identity() {
    case "$1" in
        zhang) printf '%s|%s\n' "$WF_DEV_LEAD" "zhangwei@$WF_EMAIL_DOMAIN" ;;
        li)    printf '%s|%s\n' "$WF_DEV_MATE" "lisi@$WF_EMAIL_DOMAIN" ;;
        *)     die "$WF_USAGE" "未知成员: $1（可选 zhang / li）" ;;
    esac
}

# ── 新建仓库并落地成员身份 ────────────────────────────────
wf_repo_init() {
    local dir="$1" who="$2"
    local name email
    IFS='|' read -r name email <<<"$(wf_identity "$who")"

    mkdir -p -- "$dir"
    git init -q -- "$dir"
    git -C "$dir" config user.name  "$name"
    git -C "$dir" config user.email "$email"
    # 关掉 GPG 签名与环境差异带来的噪声，保证演练可复现
    git -C "$dir" config commit.gpgsign false
    git -C "$dir" config tag.gpgsign   false
    git -C "$dir" config core.autocrlf false
    log_debug "已初始化仓库 $dir（$name <$email>）"
}

# ── 构建"远端 + 两名成员"的团队沙盘 ────────────────────────
# 布局：
#   $root/remote.git   裸仓库，充当远端
#   $root/zhang/       Zhang Wei 的工作克隆
#   $root/li/          Li Si 的工作克隆
wf_team_build() {
    local root="$1"
    local remote="$root/remote.git"

    mkdir -p -- "$root"
    git init -q --bare -- "$remote"
    git -C "$remote" config receive.denyNonFastForwards false  # 允许演练强推

    wf_repo_init "$root/zhang" zhang
    wf_repo_init "$root/li"    li

    # 种子提交由 Zhang Wei 发起并推送，让远端有历史
    printf '# Team Playbook\n\nSandpit for Git workflow drills.\n' > "$root/zhang/README.md"
    printf 'build/\n*.log\n' > "$root/zhang/.gitignore"
    git -C "$root/zhang" add -A
    git -C "$root/zhang" commit -q -m 'docs: add team playbook and gitignore'

    git -C "$root/zhang" remote add origin "$remote"
    git -C "$root/li"    remote add origin "$remote"
    # ⚠️ 上游用 -u 绑定，否则两名成员的 push/pull 都要写全 refspec，演练会变啰嗦
    git -C "$root/zhang" push -q -u origin HEAD
    git -C "$root/li"    fetch -q origin
    git -C "$root/li"    reset -q --hard origin/HEAD 2>/dev/null \
        || git -C "$root/li" reset -q --hard origin/master

    log_info "团队沙盘已构建：$root（remote.git + zhang + li）"
    printf '%s\n' "$remote"
}

# ── 造一个指定大小的文件（用于大文件/瘦身场景）────────────
# 用 /dev/urandom 而不是 dd if=/dev/zero：零字节会被 git 压缩，
# 体积演示会失真（看起来"瘦身没效果"）。
wf_make_blob() {
    local path="$1" kb="${2:-1024}"
    mkdir -p -- "$(dirname -- "$path")"
    head -c "$((kb * 1024))" /dev/urandom > "$path"
    log_debug "已生成 $((kb))KB 随机文件：$path"
}

# ── 仓库体积（KB）：.git 目录实际占用 ─────────────────────
wf_repo_size_kb() {
    local dir="$1"
    du -sk "$dir/.git" 2>/dev/null | awk '{print $1}'
}

# ── 当前分支名 ────────────────────────────────────────────
wf_current_branch() {
    git -C "$1" symbolic-ref --short HEAD 2>/dev/null || printf 'DETACHED\n'
}

# ── 最近一条提交的主题行 ──────────────────────────────────
wf_last_subject() {
    git -C "$1" log -1 --format=%s 2>/dev/null || printf '(none)\n'
}

# ── 提交总数 ──────────────────────────────────────────────
wf_commit_count() {
    git -C "$1" rev-list --count HEAD 2>/dev/null || printf '0\n'
}

# ── 在指定仓库里做一次提交 ────────────────────────────────
wf_commit() {
    local dir="$1" msg="$2"; shift 2
    # "$@" 是可选的"文件内容"三元组：路径 内容
    local p c
    while (( $# )); do
        p="$1"; c="$2"; shift 2
        mkdir -p -- "$(dirname -- "$dir/$p")"
        printf '%s\n' "$c" > "$dir/$p"
        git -C "$dir" add -- "$p"
    done
    git -C "$dir" commit -q -m "$msg"
    log_debug "提交于 $dir：$msg"
}
