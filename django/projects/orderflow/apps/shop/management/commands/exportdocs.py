"""导出 OpenAPI 文档（课 20 实验 30 的命令化）。

用法：
    python manage.py exportdocs --file schema.yaml
    python manage.py exportdocs --file schema.yaml --check    # CI 用，不同步就退出码非 0
    python manage.py exportdocs --file schema.yaml -v 2       # 显示子进程命令

设计要点：
  --check 是给 CI 用的：它不写文件，只比对，不一致就非 0 退出。
  这样"文档过期"能在 CI 阶段被拦住，而不是等前端来对线。
"""
import os
import subprocess
import sys
from pathlib import Path

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError


class Command(BaseCommand):
    help = "导出 OpenAPI 文档；--check 用于 CI 校验文档是否与代码同步。"

    def add_arguments(self, parser):
        # ⚠️ 不能叫 --version：BaseCommand 自带 --version（显示 Django 版本），
        # 撞名会抛 argparse.ArgumentError: conflicting option string
        parser.add_argument("--file", default="schema.yaml", help="输出文件路径")
        parser.add_argument(
            "--check",
            action="store_true",
            help="只检查：与已有文件比对，不一致就退出码非 0（CI 用）",
        )
        parser.add_argument("--fail-on-warn", action="store_true", help="schema 有 warning 也算失败")

    def handle(self, *args, **options):
        out = Path(options["file"])
        if not out.is_absolute():
            out = Path(settings.BASE_DIR) / out
        check_only = options["check"]
        verbosity = options["verbosity"]
        target = out if not check_only else Path(str(out) + ".tmp-check")

        if verbosity >= 1:
            self.stdout.write(
                f"▶ {'校验' if check_only else '导出'} OpenAPI 文档 → {out}"
            )

        env = dict(os.environ)
        env["DJANGO_SETTINGS_MODULE"] = os.environ.get(
            "DJANGO_SETTINGS_MODULE", "config.settings"
        )
        env["PYTHONIOENCODING"] = "utf-8"

        cmd = [
            sys.executable, "manage.py", "spectacular",
            "--file", str(target), "--validate",
        ]
        if options["fail_on_warn"]:
            cmd.append("--fail-on-warn")

        proc = subprocess.run(
            cmd,
            cwd=str(settings.BASE_DIR),
            env=env,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )

        if verbosity >= 2:
            self.stdout.write(f"    [debug] 子进程命令：{' '.join(cmd)}")
            if proc.stderr.strip():
                self.stdout.write(f"    [debug] stderr: {proc.stderr.strip()[:400]}")

        if proc.returncode != 0:
            if target.exists() and check_only:
                target.unlink()
            raise CommandError(f"文档导出失败：\n{proc.stderr[-800:]}")

        if not check_only:
            size = target.stat().st_size
            self.stdout.write(self.style.SUCCESS(f"✅ 文档已写入 {target}（{size} 字节）"))
            return

        if not out.exists():
            target.unlink(missing_ok=True)
            raise CommandError(f"{out} 不存在——先跑一次不带 --check 的导出并提交该文件")

        old = out.read_text(encoding="utf-8")
        new = target.read_text(encoding="utf-8")
        target.unlink(missing_ok=True)

        if old == new:
            self.stdout.write(self.style.SUCCESS("✅ 文档与代码同步（无差异）"))
            return

        diff_lines = [
            f"{i}: - {a}\n     + {b}"
            for i, (a, b) in enumerate(zip(old.splitlines(), new.splitlines()), 1)
            if a != b
        ]
        raise CommandError(
            f"❌ 文档已过期（{len(diff_lines)} 处差异）：\n"
            + "\n".join(diff_lines[:20])
            + f"\n\n请重新导出并提交：python manage.py exportdocs --file {out}"
        )
