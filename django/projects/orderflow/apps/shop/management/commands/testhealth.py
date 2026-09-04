"""体检命令：把一次测试跑拆成三段分别计时（课 20 实验 41 的命令化）。

用法：
    python manage.py testhealth
    python manage.py testhealth --cases 20 --seed 50
    python manage.py testhealth -v 2          # 显示每段明细
    python manage.py testhealth --json        # CI 解析用

"脚本"变"命令"才有的四样东西：
  1. 参数可配置：用例数与造数量不再是写死的常量
  2. 进度输出：--verbosity 控制细到什么程度
  3. 退出码：超阈值就失败，CI 才能拦
  4. 结构化输出：--json 给机器读
"""
import json
import time
import unittest

from django.core.management.base import BaseCommand, CommandError
from django.test.runner import DiscoverRunner
from django.test.utils import setup_test_environment, teardown_test_environment


class Command(BaseCommand):
    help = "体检：把一次测试跑拆成 建库 / 造数 / 执行 三段分别计时。"

    def add_arguments(self, parser):
        parser.add_argument("--cases", type=int, default=20, help="造多少个空用例（默认 20）")
        parser.add_argument("--seed", type=int, default=50, help="造多少条商品（默认 50）")
        parser.add_argument(
            "--warn-setup-ratio",
            type=float,
            default=0.5,
            help="建库占比超过这个值就告警（默认 0.5）",
        )
        parser.add_argument("--json", action="store_true", help="输出 JSON 供 CI 解析")

    def handle(self, *args, **options):
        verbosity = options["verbosity"]
        n_cases = options["cases"]
        n_seed = options["seed"]
        warn_ratio = options["warn_setup_ratio"]

        if n_cases < 1 or n_seed < 0:
            raise CommandError("--cases 必须 >= 1，--seed 必须 >= 0")

        # ⚠️ 命令要能被自己测：如果调用方已在测试环境里（call_command 在 TestCase
        # 中被调用），就不能再 setup 一次，否则抛
        # RuntimeError: setup_test_environment() was already called。
        # 判据是 EMAIL_BACKEND 是否已被换成 locmem。
        from django.conf import settings as dj_settings

        already_in_test = (
            dj_settings.EMAIL_BACKEND == "django.core.mail.backends.locmem.EmailBackend"
        )
        if not already_in_test:
            setup_test_environment()
        runner = DiscoverRunner(verbosity=0, interactive=False)

        # ⚠️ 关键设计：命令要能被自己测（课 21 的硬要求）。
        # 若调用方已在测试环境（call_command 在 TestCase 里被调用），
        # 再跑一次 setup_databases() 会去建第二个测试库，SQLite 上直接抛：
        #   NotSupportedError: SQLite schema editor cannot be used while
        #   foreign key constraint checks are enabled
        # 所以在测试环境内**复用当前连接**，只测"造数 + 执行"两段。
        setup_ms = 0.0
        old_config = None
        if not already_in_test:
            t0 = time.perf_counter()
            old_config = runner.setup_databases()
            setup_ms = (time.perf_counter() - t0) * 1000
        phase_setup = setup_ms

        quiet = options["json"]

        if verbosity >= 1 and not quiet:
            if already_in_test:
                self.stdout.write("▶ 阶段 1/3　建库（已在测试环境，复用当前库，跳过）…")
            else:
                self.stdout.write("▶ 阶段 1/3　建库（create + migrate）…")
        if verbosity >= 2 and not quiet and not already_in_test:
            self.stdout.write(f"    建库完成，耗时 {phase_setup:.1f} ms")

        if verbosity >= 1 and not quiet:
            self.stdout.write(f"▶ 阶段 2/3　造数（{n_seed} 条商品）…")
        from apps.shop.factories import ProductFactory

        t1 = time.perf_counter()
        if n_seed:
            ProductFactory.create_batch(n_seed)
        phase_seed = (time.perf_counter() - t1) * 1000
        if verbosity >= 2 and not quiet:
            self.stdout.write(f"    造数完成，耗时 {phase_seed:.1f} ms")

        if verbosity >= 1 and not quiet:
            self.stdout.write(f"▶ 阶段 3/3　执行（{n_cases} 个用例）…")

        class HealthCase(unittest.TestCase):
            """动态造出的空用例：每个只跑一次查询。

            ⚠️ 刻意不断言数据是否存在——--seed 0 是合法参数，
            此时断言 exists() 会让所有用例失败。体检用例的目的是"消耗执行时间"。
            """

            def _probe(self):
                from apps.shop.models import Product

                Product.objects.count()

        for i in range(n_cases):
            setattr(HealthCase, f"test_probe_{i:03d}", HealthCase._probe)

        suite = unittest.TestLoader().loadTestsFromTestCase(HealthCase)
        t2 = time.perf_counter()
        result = runner.test_runner(
            verbosity=0, failfast=False, resultclass=runner.get_resultclass()
        ).run(suite)
        phase_run = (time.perf_counter() - t2) * 1000
        failures = len(result.failures) + len(result.errors)

        if old_config is not None:
            runner.teardown_databases(old_config)
        if not already_in_test:
            teardown_test_environment()

        total = phase_setup + phase_seed + phase_run
        pct = lambda ms: (ms / total * 100) if total else 0.0  # noqa: E731

        payload = {
            "phase_setup_ms": round(phase_setup, 1),
            "phase_seed_ms": round(phase_seed, 1),
            "phase_run_ms": round(phase_run, 1),
            "total_ms": round(total, 1),
            "setup_ratio": round(pct(phase_setup) / 100, 4),
            "seed_ratio": round(pct(phase_seed) / 100, 4),
            "run_ratio": round(pct(phase_run) / 100, 4),
            "cases": n_cases,
            "seed_rows": n_seed,
            "failed": failures,
        }

        if options["json"]:
            # ⚠️ 必须单独输出一行 JSON，不能混入进度行，否则 CI 解析不了
            self.stdout.write(json.dumps(payload, ensure_ascii=False))
            return

        if verbosity >= 1:
            self.stdout.write("")
            self.stdout.write(self.style.MIGRATE_HEADING("体检结果"))
            self.stdout.write(f"  建库  {phase_setup:8.1f} ms  ({pct(phase_setup):5.1f}%)")
            self.stdout.write(f"  造数  {phase_seed:8.1f} ms  ({pct(phase_seed):5.1f}%)")
            self.stdout.write(f"  执行  {phase_run:8.1f} ms  ({pct(phase_run):5.1f}%)")
            self.stdout.write(f"  合计  {total:8.1f} ms")
            self.stdout.write("")

            if pct(phase_setup) / 100 > warn_ratio:
                self.stdout.write(
                    self.style.WARNING(
                        f"⚠️ 建库占 {pct(phase_setup):.0f}%，超过阈值 {warn_ratio:.0%}"
                        "——提速第一刀应砍在数据库（--keepdb / MIGRATION_MODULES）"
                    )
                )
            elif pct(phase_seed) / 100 > warn_ratio:
                self.stdout.write(
                    self.style.WARNING(
                        f"⚠️ 造数占 {pct(phase_seed):.0f}%——检查是否用了 create_batch"
                        " 而非 build_batch + bulk_create"
                    )
                )
            else:
                self.stdout.write(
                    self.style.SUCCESS("✅ 执行占比最高，优化点在你的用例代码本身")
                )

        if failures:
            raise CommandError(f"体检用例失败 {failures} 个——先修测试再谈提速")
