# -*- coding: utf-8 -*-
"""
L16 实验 A：Telegraf 配置体检器
================================
把「Telegraf → InfluxDB 3」的常见配置错误做成 CI 门禁。

用法:
    python l16_telegraf_lint.py                      # 演示模式：内置反面 + 正面样例各跑一遍
    python l16_telegraf_lint.py telegraf.conf        # 体检真实配置
    python l16_telegraf_lint.py a.conf b.conf -v 1.40.0

退出码:
    0 = 无 P0 / P1（可用）
    1 = 存在 P0 或 P1（建议拦截）
"""
import argparse
import re
import sys
import tomllib

# ========== 常量（均取自官方一手文档，见讲义「📚 官方文档」）==========
MIN_VER_V3 = (1, 38)      # outputs.influxdb_v3 自 Telegraf v1.38.0 引入
CORE_DB_LIMIT = 5         # Core 硬限制：最多 5 个库（回扣 L6）
CORE_HTTP_PORT = 8181     # Core HTTP 默认端口（回扣 L3：8086 是 1.x/2.x）
V1V2_HTTP_PORT = 8086
DEFAULT_ENCODING = "gzip"
DEFAULT_TIMEOUT = "5s"

# ========== 内置样例 ==========

BAD_SAMPLE = """\
# ❌ 反面教材：一份"能跑通但浑身是坑"的 Telegraf 配置
[agent]
  interval = "1s"

[[inputs.cpu]]
  percpu = true

[[outputs.influxdb_v3]]
  urls = ["http://influxdb-a.internal:8086", "http://influxdb-b.internal:8086"]
  token = "apiv3_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJ"
  database = "metrics"
  content_encoding = "none"
  sync = false
  database_tag = "host"
"""

GOOD_SAMPLE = """\
# ✅ 正面教材：面向 Core 生产环境的推荐写法
[agent]
  interval = "10s"
  flush_interval = "10s"
  metric_batch_size = 5000
  metric_buffer_limit = 50000

[[inputs.cpu]]
  percpu = false
  totalcpu = true

[[outputs.influxdb_v3]]
  urls = ["https://influxdb.internal:8181"]
  token = "${INFLUX_TOKEN}"
  database = "metrics"
  content_encoding = "gzip"
  sync = true
  timeout = "10s"
"""

LEVEL_ORDER = {"P0": 0, "P1": 1, "P2": 2, "INFO": 3}
ICON = {"P0": "[P0]", "P1": "[P1]", "P2": "[P2]", "INFO": "[i] "}


# ========== 工具 ==========

def hr(title=""):
    if title:
        print("\n" + "=" * 74)
        print("  " + title)
        print("=" * 74)
    else:
        print("-" * 74)


def parse_ver(s):
    """把 '1.38.0' / 'v1.38' 解析成 (1, 38, 0)。"""
    nums = re.findall(r"\d+", s or "")
    while len(nums) < 3:
        nums.append("0")
    return tuple(int(x) for x in nums[:3])


def ver_str(v):
    return ".".join(str(x) for x in v)


def is_env_ref(val):
    """token 是否是环境变量/密钥仓库引用（${...} 形式）。"""
    return isinstance(val, str) and val.strip().startswith("${")


def host_of(url):
    m = re.match(r"(https?)://([^:/]+)", url or "")
    return (m.group(2) if m else (url or "")).lower()


def port_of(url):
    m = re.search(r":(\d+)\s*$", url or "")
    return int(m.group(1)) if m else None


def is_local(h):
    return h in ("localhost", "127.0.0.1", "::1")


# ========== 检查项 ==========

def check(cfg, telegraf_ver):
    """返回 findings 列表，每项 (level, rule_id, title, detail, fix)。"""
    f = []
    add = lambda lv, rid, t, d, fix: f.append((lv, rid, t, d, fix))

    outputs = cfg.get("outputs", {}) or {}
    inputs = cfg.get("inputs", {}) or {}
    v3_list = outputs.get("influxdb_v3", []) or []
    v2_list = outputs.get("influxdb_v2", []) or []
    v1_list = outputs.get("influxdb", []) or []

    if isinstance(v3_list, dict):
        v3_list = [v3_list]
    if isinstance(v2_list, dict):
        v2_list = [v2_list]
    if isinstance(v1_list, dict):
        v1_list = [v1_list]

    # ---- T0-3：没有任何 output ----
    if not (v3_list or v2_list or v1_list):
        add("P0", "T0-3", "没有任何 output 插件",
            "Telegraf 配置必须至少一个 output，采集到的数据无处可去。",
            "添加 [[outputs.influxdb_v3]]（Telegraf ≥ 1.38）或 [[outputs.influxdb_v2]]。")
        return f

    # ---- T0-1：版本门槛 ----
    if v3_list and telegraf_ver < MIN_VER_V3:
        add("P0", "T0-1", f"Telegraf 版本不支持 influxdb_v3 输出",
            f"当前 {ver_str(telegraf_ver)}，而 outputs.influxdb_v3 自 "
            f"Telegraf v{ver_str(MIN_VER_V3)} 才引入（走 /api/v3/write_lp 原生端点）。",
            f"升级到 Telegraf ≥ v{ver_str(MIN_VER_V3)}，或改用 "
            f"[[outputs.influxdb_v2]] 走 v2 兼容端点（organization 必须留空串）。")

    for idx, o in enumerate(v3_list):
        tag = f"outputs.influxdb_v3"
        if len(v3_list) > 1:
            tag += f"[{idx}]"
        urls = o.get("urls", []) or []
        first = urls[0] if urls else ""

        # ---- T0-2：token 硬编码 ----
        tok = o.get("token", "")
        if tok and not is_env_ref(tok):
            add("P0", "T0-2", "token 以明文硬编码在配置文件里",
                f"{tag}.token 是明文字符串（长度 {len(tok)}）。"
                "配置文件通常进 Git，等同于把数据库写权限提交到仓库。",
                'token = "${INFLUX_TOKEN}"，运行时由环境变量或 Telegraf secret store 注入。')
        elif not tok:
            add("P2", "T0-2", "token 为空",
                f"{tag}.token 未设置。若服务端开了认证，写入会 401。",
                '填 ${INFLUX_TOKEN}；若确实关闭了认证请显式注释说明。')

        # ---- T0-4：database_tag 的路由基数撞 Core 5 库上限 ----
        dbtag = o.get("database_tag", "")
        if dbtag:
            add("P0", "T0-4", f"database_tag 按 tag 分库，可能撞 Core 的 {CORE_DB_LIMIT} 库上限",
                f"{tag}.database_tag = \"{dbtag}\" → 目标库数量 = 该 tag 的**去重值个数**。\n"
                f"        Core 硬上限 {CORE_DB_LIMIT} 个库（回扣 L6）；一旦超出，写入直接失败且不易定位。",
                f"先自数：SELECT COUNT(DISTINCT(\"{dbtag}\")) FROM <源表>；\n"
                f"        > {CORE_DB_LIMIT} 就必须改成单库 + 该维度降级为 tag/field，或迁 Enterprise。")

            # ---- T2-2：exclude_database_tag ----
            if not o.get("exclude_database_tag", False):
                add("P2", "T2-2", "database_tag 未配 exclude_database_tag",
                    f"{tag} 未设置 exclude_database_tag = true → 路由用的 tag 会随数据一起写进库，\n"
                    "        多一列冗余数据（回扣 L7：稀疏 schema 会拖慢查询）。",
                    "exclude_database_tag = true")

        # ---- T1-1：压缩 ----
        enc = o.get("content_encoding", DEFAULT_ENCODING)
        if enc != "gzip":
            add("P1", "T1-1", f"content_encoding = \"{enc}\"，未启用 gzip",
                f"{tag} 关掉压缩后，line protocol 明文上行。line protocol 是文本协议，\n"
                "        实测压缩比通常很高（回扣 L12：批量上限 10MB 也可能是压缩后）。",
                'content_encoding = "gzip"（这也是插件默认值，建议显式写出）')

        # ---- T1-2：sync / 持久性 ----
        if o.get("sync", True) is False:
            add("P1", "T1-2", "sync = false（用持久性换延迟）",
                f"{tag}.sync = false → 不等 WAL 持久化就确认，延迟更低但**崩溃时已确认的数据可能丢**。\n"
                "        这正是 L10 讲的 no_sync=true 的同一枚开关，只是换了个名字。",
                "核心业务数据保持 sync = true；只有可重建的、丢得起的数据才关。")

        # ---- T1-4：明文 http + 非本机 ----
        for u in urls:
            if u.startswith("http://") and not is_local(host_of(u)):
                add("P1", "T1-4", "明文 http 访问非本机地址",
                    f"{tag}.urls 含 {u} → token 以 Bearer 明文在网络上传输。",
                    "改用 https://，或在确认网络可信的前提下显式接受风险。")
                break

        # ---- T1-5：多 url 的真实语义 ----
        if len(urls) > 1:
            add("INFO", "T1-5", f"配置了 {len(urls)} 个 urls —— 注意它不是双写、也不是负载均衡",
                "官方语义：**每个 flush 周期只随机挑一个 URL 写入**，"
                "失败才换下一个，直到全部试完或成功。\n"
                "        所以它是「故障转移」，不是「双写」，也不是「分摊流量」。",
                "要双写 → 写两个 [[outputs.influxdb_v3]] 块；\n"
                "        要分摊 → 在 Telegraf 前面做 LB，或拆成多个 output 块配筛选。")

        # ---- T2-3：端口指纹 ----
        p = port_of(first)
        if p == V1V2_HTTP_PORT:
            add("P2", "T2-3", f"端口 {V1V2_HTTP_PORT} 是 InfluxDB 1.x / 2.x 的端口",
                f"{tag}.urls[0] 指向 :{V1V2_HTTP_PORT}。Core 的 HTTP 端口是 "
                f"{CORE_HTTP_PORT}（回扣 L3：看到 8086 基本可判断起的不是 3.x）。",
                f"改成 :{CORE_HTTP_PORT}（若确实在代理 1.x/2.x，请确认目标实例版本）。")
        elif p is not None and p != CORE_HTTP_PORT:
            add("P2", "T2-3", f"端口 {p} 不是 Core 默认的 {CORE_HTTP_PORT}",
                f"{tag}.urls[0] 端口为 {p}。",
                f"确认是该实例显式改过 --http-bind，否则应为 {CORE_HTTP_PORT}。")

        # ---- T2-4：timeout ----
        if "timeout" not in o:
            add("P2", "T2-4", f"未显式设置 timeout（默认 {DEFAULT_TIMEOUT}）",
                f"{tag} 未配置 timeout。默认 5s 在跨地域/高负载时可能偏紧，\n"
                "        超时后该批会留在 buffer 里下轮重试，堆积会触发丢点。",
                'timeout = "10s"（配合 metric_buffer_limit 一起调）')

    # ---- T1-3：v2 兼容插件的 organization ----
    for o in v2_list:
        org = o.get("organization", None)
        if org not in ("", None):
            add("P1", "T1-3", "influxdb_v2 的 organization 不是空串",
                f"organization = \"{org}\"。官方明确要求：写 InfluxDB 3 Core 时 "
                "organization 必须设为空字符串。",
                'organization = ""（bucket 填 Core 的 database 名）')

    # ---- T2-1：批量参数 ----
    agent = cfg.get("agent", {}) or {}
    if "metric_batch_size" not in agent:
        add("P2", "T2-1", "agent 未设置 metric_batch_size",
            "未显式配置批量大小。批量是摊销连接与请求开销的关键手段（回扣 L12），\n"
            "        默认值不一定适合你的点密度。",
            "metric_batch_size = 5000（配合 metric_buffer_limit = 50000）")

    # ---- 信息：input 数量 ----
    n_in = sum(len(v) if isinstance(v, list) else 1 for v in inputs.values())
    if n_in == 0:
        add("P1", "T1-6", "没有任何 input 插件",
            "Telegraf 配置必须至少一个 input，否则没有数据来源。",
            "添加 [[inputs.cpu]] 等采集插件。")

    return f


def render(name, cfg, findings, telegraf_ver):
    hr(f"体检对象：{name}")
    n_in = len(cfg.get("inputs", {}) or {})
    outs = cfg.get("outputs", {}) or {}
    print(f"  Telegraf 版本 : {ver_str(telegraf_ver)}")
    print(f"  input 插件类  : {n_in} 类  {list((cfg.get('inputs') or {}).keys())}")
    print(f"  output 插件类 : {len(outs)} 类  {list(outs.keys())}")

    if not findings:
        print("\n  ✅ 未发现 P0 / P1 / P2 问题")
        return 0

    findings.sort(key=lambda x: LEVEL_ORDER[x[0]])
    counts = {}
    for lv, *_ in findings:
        counts[lv] = counts.get(lv, 0) + 1

    print("\n  " + "  ".join(f"{lv}={counts.get(lv, 0)}"
                             for lv in ("P0", "P1", "P2", "INFO") if counts.get(lv)))
    hr()
    for lv, rid, title, detail, fix in findings:
        print(f"\n{ICON[lv]} {rid}  {title}")
        for line in detail.split("\n"):
            print("      " + line)
        print(f"      修法: {fix}")
    hr()

    worst = min((LEVEL_ORDER[lv] for lv, *_ in findings), default=3)
    if worst <= 1:
        print("  ❌ 存在 P0 / P1 —— 建议拦截，不要合入")
        return 1
    print("  ⚠️  仅有 P2 / INFO —— 可合入，但建议处理")
    return 0


def main():
    ap = argparse.ArgumentParser(description="Telegraf → InfluxDB 3 配置体检器")
    ap.add_argument("files", nargs="*", help="telegraf.conf 路径；留空则用内置样例演示")
    ap.add_argument("-v", "--telegraf-version", default="1.38.0",
                    help="你的 Telegraf 版本（默认 1.38.0）")
    args = ap.parse_args()

    ver = parse_ver(args.telegraf_version)

    print("=" * 74)
    print("  L16 实验 A：Telegraf 配置体检器")
    print("=" * 74)
    print(f"  指定 Telegraf 版本: {ver_str(ver)}")
    print(f"  outputs.influxdb_v3 门槛: v{ver_str(MIN_VER_V3)}")
    print(f"  Core 库上限: {CORE_DB_LIMIT}    Core HTTP 端口: {CORE_HTTP_PORT}")

    rc = 0
    if args.files:
        for path in args.files:
            try:
                with open(path, "rb") as fh:
                    cfg = tomllib.load(fh)
            except Exception as e:
                print(f"\n❌ 解析失败 {path}: {e}")
                rc = 1
                continue
            rc |= render(path, cfg, check(cfg, ver), ver)
    else:
        print("\n（未传入配置文件 → 演示模式：反面样例用旧版本 1.36，正面样例用 1.40）")

        cfg_bad = tomllib.loads(BAD_SAMPLE)
        rc |= render("内置【反面教材】（Telegraf 1.36.0）", cfg_bad,
                     check(cfg_bad, (1, 36, 0)), (1, 36, 0))

        cfg_good = tomllib.loads(GOOD_SAMPLE)
        rc |= render("内置【正面教材】（Telegraf 1.40.0）", cfg_good,
                     check(cfg_good, (1, 40, 0)), (1, 40, 0))

        hr("演示模式小结")
        print("  反面样例把本课讲的坑几乎踩了一遍：")
        print("    · token 明文写进配置（会进 Git）")
        print("    · database_tag=\"host\" —— 路由基数撞 Core 5 库上限")
        print("    · content_encoding=\"none\" 关掉 gzip")
        print("    · sync=false 用持久性换延迟")
        print("    · 两个 urls 以为是双写/负载均衡（其实是故障转移）")
        print("    · 端口 8086 —— 那是 1.x/2.x 的端口，Core 是 8181")
        print("    · Telegraf 1.36 根本不认 influxdb_v3 这个插件")
        print("\n  正面样例逐条规避，输出「未发现 P0 / P1 / P2 问题」。")

    print("\n" + "=" * 74)
    print("  用法提示：")
    print("    python l16_telegraf_lint.py /etc/telegraf/telegraf.conf -v 1.40.0")
    print("    有 P0/P1 时进程退出码为 1，可直接挂到 CI / pre-commit。")
    print("=" * 74)
    return rc


if __name__ == "__main__":
    sys.exit(main())
