"""生成一个 OpenMetrics 文件，供 promtool 生成真实 TSDB block。

时间跨度 1 小时，每 60 秒一个点。
注意：promtool 的文本解析器不接受空行，且要求按"指标块"组织
（同一指标的 TYPE/HELP 后紧跟该指标的所有样本，不同指标之间不留空行）。
"""

import datetime

OUT = "/mnt/d/projects/learning/prometheus/labs/lesson-03/blocks-input/samples.om"

# 固定基准时间（UTC），保证可复现
BASE = datetime.datetime(2026, 9, 4, 0, 0, 0)
STEP = 60                # 60 秒一个点
POINTS = 61              # 0..60 分钟，共 61 个点

# 按指标组织：(name, [(labels, value_fn), ...])
GROUPS = [
    ("app_demo_temperature", [
        ({"region": "cn-south", "sensor": "s1"}, lambda i: 20.0 + (i % 12) * 0.5),
        ({"region": "cn-north", "sensor": "s2"}, lambda i: 15.0 + (i % 9) * 0.7),
    ]),
    ("app_demo_pressure", [
        ({"region": "cn-south"}, lambda i: 1013.0 + (i % 5) * 0.1),
    ]),
]


def main():
    lines = []
    for name, series_list in GROUPS:
        lines.append("# TYPE %s gauge" % name)
        lines.append("# HELP %s demo metric for block generation" % name)
        for i in range(POINTS):
            ts = int((BASE + datetime.timedelta(seconds=i * STEP)).timestamp() * 1000)
            for labels, fn in series_list:
                label_str = ",".join('%s="%s"' % (k, v) for k, v in sorted(labels.items()))
                lines.append("%s{%s} %s %d" % (name, label_str, fn(i), ts))
    # 末尾不留空行，直接 EOF
    lines.append("# EOF")

    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    n_series = sum(len(s) for _, s in GROUPS)
    print("wrote %s (%d lines, %d series x %d points)" % (OUT, len(lines), n_series, POINTS))
    print("time range: %s .. %s"
          % (BASE.isoformat(),
             (BASE + datetime.timedelta(seconds=(POINTS - 1) * STEP)).isoformat()))


if __name__ == "__main__":
    main()
