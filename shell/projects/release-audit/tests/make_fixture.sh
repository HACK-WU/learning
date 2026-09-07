#!/usr/bin/env bash
#
# tests/make_fixture.sh —— 构造测试用的发布目录样例
#
# 用法：
#   bash tests/make_fixture.sh <输出目录> <样例类型>
#
# 样例类型：
#   clean    全部合规，期望退出码 0
#   warn     含 WARN 项，期望退出码 1
#   block    含 BLOCK 项，期望退出码 2
#   tampered checksum 不匹配，期望退出码 2

set -uo pipefail

fixture_root=$1
kind=${2:-clean}

rm -rf -- "$fixture_root"
mkdir -p -- "$fixture_root"/{bin,conf,lib}

# ── 基础文件 ──
printf '2.1.0\n' >"$fixture_root/VERSION"
printf 'app-binary-placeholder\n' >"$fixture_root/bin/app"
chmod 755 -- "$fixture_root/bin/app"
printf '#!/usr/bin/env bash\nprintf "hello\\n"\n' >"$fixture_root/bin/start.sh"
chmod 755 -- "$fixture_root/bin/start.sh"
printf 'db.host=localhost\n' >"$fixture_root/conf/app.conf"
chmod 644 -- "$fixture_root/conf/app.conf"
printf 'library-placeholder\n' >"$fixture_root/lib/core.jar"
chmod 644 -- "$fixture_root/lib/core.jar"

# ── 清单文件 ──
cat >"$fixture_root/MANIFEST" <<'EOF'
# 发布清单
version=2.1.0
bin/app
bin/start.sh
conf/app.conf
lib/core.jar
VERSION
EOF

# ── checksum ──
(
  cd -- "$fixture_root" || exit 1
  # 只对常规文件求 sum，排除 MANIFEST 与 SHA256SUMS 自身
  find . -type f ! -name 'SHA256SUMS' ! -name 'MANIFEST' -print \
    | sed 's|^\./||' \
    | sort \
    | xargs -r sha256sum >SHA256SUMS
) 

case "$kind" in
  clean)
    # 什么都不改
    ;;
  warn)
    # 私钥文件权限过宽（644）+ shell 脚本缺可执行位
    printf 'PRIVATE KEY PLACEHOLDER\n' >"$fixture_root/conf/server.key"
    chmod 644 -- "$fixture_root/conf/server.key"
    printf '#!/usr/bin/env bash\nprintf "stop\\n"\n' >"$fixture_root/bin/stop.sh"
    chmod 644 -- "$fixture_root/bin/stop.sh"
    # 追加进清单，避免同时触发 BLOCK（本样例只想验 WARN）
    printf 'conf/server.key\nbin/stop.sh\n' >>"$fixture_root/MANIFEST"
    ;;
  block)
    # 硬编码凭证 + 必需文件缺失
    printf 'password = "SuperSecret123"\n' >"$fixture_root/conf/datasource.conf"
    chmod 644 -- "$fixture_root/conf/datasource.conf"
    printf 'db.password=AnotherSecret456\n' >"$fixture_root/conf/app.conf"
    # world-writable 文件
    printf 'world writable\n' >"$fixture_root/lib/world.txt"
    chmod 666 -- "$fixture_root/lib/world.txt"
    # 清单里声明一个不存在的文件
    printf 'lib/missing-file.jar\n' >>"$fixture_root/MANIFEST"
    ;;
  tampered)
    # 先算好 checksum，再篡改文件内容
    printf 'bin/app\n' >/dev/null
    printf 'TAMPERED CONTENT\n' >"$fixture_root/bin/app"
    ;;
  *)
    printf '未知样例类型: %s\n' "$kind" >&2
    exit 64
    ;;
esac

printf '%s\n' "$fixture_root"
