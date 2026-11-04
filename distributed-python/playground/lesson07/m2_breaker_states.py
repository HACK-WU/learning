"""M2：熔断器的三个状态 —— 用真实下游把状态机走一遍。

观测的是"状态流转的时刻与原因"，不是"限流是否生效"：
  Closed  —— 连续失败到阈值 → 跳闸
  Open    —— 一律快速失败，且完全不碰下游
  Half-Open —— 计时到了放一个探针；探针成功 → 回 Closed，探针失败 → 回 Open 并重启计时
"""
import time
import urllib.request

from _downstream import Downstream


class Breaker:
    """最小可用的三态熔断器。参数都显式命名，方便对照官方描述。"""

    def __init__(self, fail_threshold=3, open_seconds=0.5,
                 half_open_probes=1, name="cb"):
        self.fail_threshold = fail_threshold
        self.open_seconds = open_seconds
        self.half_open_probes = half_open_probes
        self.name = name
        self.state = "Closed"
        self.fails = 0
        self.opened_at = 0.0
        self.probes_left = 0
        self.log = []

    def _set(self, new, why):
        if new != self.state:
            self.log.append((round(time.perf_counter() - T0, 3),
                             f"{self.state} → {new}", why))
            self.state = new

    def call(self, fn):
        now = time.perf_counter()

        if self.state == "Open":
            if now - self.opened_at < self.open_seconds:
                return "REJECTED"          # 快速失败：一次都不碰下游
            self._set("Half-Open", f"计时 {self.open_seconds}s 到，放探针")
            self.probes_left = self.half_open_probes

        if self.state == "Half-Open":
            if self.probes_left <= 0:
                return "REJECTED"
            self.probes_left -= 1
            ok = fn()
            if ok:
                self.fails = 0
                self._set("Closed", "探针成功，故障已恢复")
            else:
                self.opened_at = time.perf_counter()
                self._set("Open", "探针失败，重启计时")
            return "PROBE_OK" if ok else "PROBE_FAIL"

        # Closed
        ok = fn()
        if ok:
            self.fails = 0
            return "OK"
        self.fails += 1
        if self.fails >= self.fail_threshold:
            self.opened_at = time.perf_counter()
            self._set("Open", f"连续失败 {self.fails} 次 ≥ 阈值 {self.fail_threshold}")
        return "FAIL"


T0 = time.perf_counter()


def main():
    with Downstream(delay=0.01) as ds:
        def probe(desc=""):
            t = time.perf_counter()
            try:
                with urllib.request.urlopen(ds.url, timeout=1.0) as r:
                    r.read()
                ok = True
            except Exception:
                ok = False
            return ok, (time.perf_counter() - t) * 1000

        cb = Breaker(fail_threshold=3, open_seconds=0.5)
        print("=" * 68)
        print(f"熔断参数：失败阈值 3 次 ｜ Open 持续 500ms ｜ Half-Open 放 1 个探针")

        # ---- 1. Closed：正常放行 ----
        print("\n【1】下游健康 —— Closed 正常放行")
        ds.httpd.delay = 0.01
        for i in range(3):
            ok, ms = probe()
            r = cb.call(lambda: ok)
            print(f"  第{i+1}次: 下游 {ms:.0f}ms ok={ok} → 熔断器 {r}｜state={cb.state}")

        # ---- 2. Closed → Open ----
        print("\n【2】下游挂掉（返回 503）—— 连续失败到阈值")
        ds.httpd.code = 503
        for i in range(4):
            ok, ms = probe()
            r = cb.call(lambda: ok)
            print(f"  第{i+1}次: 下游 {ms:.0f}ms ok={ok} → 熔断器 {r}｜state={cb.state}"
                  f"｜fails={cb.fails}")

        # ---- 3. Open：快速失败 ----
        print("\n【3】Open 期间 —— 快速失败，且一次都不碰下游")
        hits_before = ds.hits
        t = time.perf_counter()
        results = [cb.call(lambda: probe()[0]) for _ in range(5)]
        spent = (time.perf_counter() - t) * 1000
        print(f"  5 次调用结果: {results}")
        print(f"  总耗时 {spent:.2f} ms（平均 {spent/5:.3f} ms/次）")
        print(f"  下游被打次数: {ds.hits - hits_before} ← 0 说明真的没去敲下游")

        # ---- 4. Open → Half-Open → Open（探针失败）----
        print("\n【4】等过 500ms 放探针 —— 下游还没好，探针失败")
        time.sleep(0.52)
        ok, ms = probe()
        r = cb.call(lambda: ok)
        print(f"  探针: 下游 {ms:.0f}ms ok={ok} → 熔断器 {r}｜state={cb.state}")
        print(f"  → 回到 Open，计时器重启（opened_at 已刷新）")

        print("\n【5】刚重启计时就试 —— 应当继续被拒")
        t = time.perf_counter()
        r = cb.call(lambda: probe()[0])
        print(f"  → {r}｜耗时 {(time.perf_counter()-t)*1000:.3f} ms｜state={cb.state}")

        # ---- 5. Half-Open → Closed ----
        print("\n【6】下游恢复（200）—— 再等 500ms，探针成功")
        ds.httpd.code = 200
        ds.httpd.delay = 0.01
        time.sleep(0.52)
        ok, ms = probe()
        r = cb.call(lambda: ok)
        print(f"  探针: 下游 {ms:.0f}ms ok={ok} → 熔断器 {r}｜state={cb.state}"
              f"｜fails={cb.fails}")
        print(f"  → 故障计数清零，恢复正常放行")

        # ---- 6. 再连续成功 ----
        print("\n【7】恢复后连续 3 次调用")
        for i in range(3):
            ok, ms = probe()
            r = cb.call(lambda: ok)
            print(f"  第{i+1}次: {r}｜state={cb.state}")

        print("\n" + "=" * 68)
        print("状态流转日志（相对启动时刻）:")
        for ts, trans, why in cb.log:
            print(f"  t={ts:>6.3f}s  {trans:<20} {why}")

        print("\n" + "=" * 68)
        print("结论：Open 的价值是『不碰下游』；Half-Open 的价值是『只放少量探针』——")
        print("      少了 Half-Open，要么永远不恢复，要么一恢复就把刚爬起来的服务再压死。")


if __name__ == "__main__":
    main()
