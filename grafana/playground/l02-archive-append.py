# -*- coding: utf-8 -*-
"""往 00-学习档案.md 的评审记录表追加课 2 记录，并更新断点信息。

为什么用 Python：该表每行极长（含大量中文与反引号），replace_in_file 的
old_string 匹配易因长度/转义失败；用 Python 按锚点插入更稳。
"""
import io
import sys

P = "/mnt/d/projects/learning/grafana/00-学习档案.md"
with io.open(P, encoding="utf-8") as f:
    lines = f.readlines()

REC = (
    "| 2026-09-04 | 课 2《第一个面板》 | 主 agent 内联（pedagogy + learner 双视角，"
    "子 agent 未创建，独立性受限） | 0 | "
    "**推翻课 1 一处错误归因（本课最大收获）**：分离变量实测证明 `/api/health` **6 秒**就绪（非 60 秒），"
    "5 个插件在 t+11s~t+19s 才陆续装完——**插件装完晚于 health 就绪 13 秒，不阻塞可用性**。"
    "课 1 判定的「装插件慢 60 秒」为误判，真根因是探测用了紧凑写法 `grep '\"database\":\"ok\"'`，"
    "而 Grafana 实际返回**带空格**的 `\"database\": \"ok\"`——**判据恒假**。"
    "若按「等待时长不够」去改，会把循环从 30 次加到 90 次却永远修不好。"
    "已修 `l00-env-up.sh`（`tr -d ' \\n'` 压平后匹配），并写 `l02-readyfix.sh` 验证：旧判据 ❌／新判据 ✅。"
    "**新增实测发现×3**：①direct 模式报错 `dial tcp [::1]:9201` 证明 **Grafana 后端仍自己发请求**，"
    "direct 并非「浏览器绕过后端直连」，该类比失效边界由实测支撑；"
    "②CORS 对照——Grafana 对外站 Origin 返 **403**，Prometheus 返 200 且**回显** Origin（宽松）；"
    "③unit 改为 bytes 后后端返回值**完全一致**，证明单位是前端格式化。"
    "**P1×3 已修**：①`l00-env-up.sh` 注释「最多 60 秒」与实际 90×2s=180 秒不符；"
    "②uid 论证缺「不可变性」这一关键前提；"
    "③正文用了 5 个端口（3001/3011~3014）却未解释切换原因（各实验需全新实例以避免状态污染），已补端口对照表。"
    "**评审中两次判真伪**：①CORS 实验首轮三项全 401 → 系脚本漏带 cookie，非 CORS 结论，补 cookie 重测得 403/200；"
    "②实验 C 断言报「不一致」→ 系比较了含时间戳的数组（时间戳每次都变），改比数值字段后为「完全一致」。"
    "两次均为**脚本缺陷，未改文档** |\n"
)

# 1) 在课 1 记录行之后插入课 2 记录
anchor = None
for i, ln in enumerate(lines):
    if ln.startswith("| 2026-09-04 | 课 1《Grafana 是谁》"):
        anchor = i
        break
if anchor is None:
    print("FAIL: 未找到课 1 记录行")
    sys.exit(1)
if any(l.startswith("| 2026-09-04 | 课 2《第一个面板》") for l in lines):
    print("SKIP: 课 2 记录已存在")
else:
    lines.insert(anchor + 1, REC)
    print("OK: 已插入课 2 评审记录")

# 2) 更新断点信息
out = []
for ln in lines:
    if ln.startswith("- **当前位置**：阶段 1 课 1 已交付"):
        out.append("- **当前位置**：阶段 1 课 2 已交付（6/36 知识点），等待用户确认后进入课 3\n")
    elif ln.startswith("- **下一批**：阶段 1 课 2"):
        out.append("- **下一批**：阶段 1 课 3《变量与 Dashboard 组织：一张图服务 N 台机器》知识点 3.1 / 3.2 / 3.3\n")
    else:
        out.append(ln)
lines = out
print("OK: 已更新断点信息")

# 3) 补充课 2 新增的实验资产
for i, ln in enumerate(lines):
    if ln.startswith("| 登录 | admin/admin，字段名是 `user` 不是 `username` |"):
        add = (
            "| 一次性测试实例 | 课 2 用 3011=`gf-l02`(全新默认)、3012=`gf-l02b`(计时)、"
            "3013=`gf-l02c`(环境变量口令/不挂卷)、3014=`gf-l02d`(挂卷 `gf-l02d-vol`) |\n"
            "| 内置/外装插件 | 内置 13 个（prometheus/loki/jaeger/elasticsearch/tempo/zipkin 等，"
            "在 `/usr/share/grafana/data/plugins-bundled`）；外装 5 个（metricsdrilldown/exploretraces/"
            "pyroscope/advisor/lokiexplore，在 `/var/lib/grafana/plugins`） |\n"
        )
        if not any("一次性测试实例" in l for l in lines):
            lines.insert(i + 1, add)
            print("OK: 已补充课 2 实验资产")
        break

with io.open(P, "w", encoding="utf-8") as f:
    f.writelines(lines)
print("DONE")
