r"""课 6 第二批实操：贝塞尔曲线、沿路径运动与弧线

把"曲线怎么定义"和"沿曲线怎么匀速走"跑出来，生成四组产物：

    bezier_de_casteljau/   24 帧，三次贝塞尔 + 德卡斯特里奥递归插值可视化
    arc_length_vs_param/   24 帧，上行「参数 t 匀速」vs 下行「弧长 s 匀速」
    bezier_basics.png      贝塞尔基础：控制点 / 二次 / 三次 / 曲线不穿过中间控制点
    bezier_smoothing.png   用贝塞尔拟合折线 = 需求文档说的「自动平滑」

运行方式（PowerShell，先切到课程目录）：
    .\playground\.venv\Scripts\python.exe .\playground\lesson-06\bezier_demo.py

依赖：numpy、pillow（已装在 playground/.venv）
"""

import bisect
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Windows 控制台默认用 GBK 输出，中文会变乱码；强制 stdout 用 UTF-8
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

TOTAL = 24          # 帧序列帧数
FW, FH = 320, 140   # 帧序列画布（比课前几课高一点，给德卡斯特里奥的层级留空间）
OUT_DIR = Path(__file__).parent


def _load_cn_font(size: int = 10) -> ImageFont.ImageFont:
    candidates = [
        r"C:\Windows\Fonts\msyh.ttc",
        r"C:\Windows\Fonts\msyhbd.ttc",
        r"C:\Windows\Fonts\msyhl.ttc",
        r"C:\Windows\Fonts\simhei.ttf",
        r"C:\Windows\Fonts\simsun.ttc",
        "/System/Library/Fonts/PingFang.ttc",
        "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    ]
    for path in candidates:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                continue
    return ImageFont.load_default()


FONT = _load_cn_font(10)
FONT_SM = _load_cn_font(9)


def new_canvas(w: int, h: int) -> Image.Image:
    return Image.fromarray(np.full((h, w, 3), 255, dtype=np.uint8))


def to_screen(x: float, y: float, cx: float, cy: float) -> tuple[int, int]:
    """数学坐标 → 屏幕像素（课 4：屏幕 y 向下，要翻转）"""
    return int(round(cx + x)), int(round(cy - y))


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def lerp_point(p0, p1, t):
    return lerp(p0[0], p1[0], t), lerp(p0[1], p1[1], t)


def dist(a, b) -> float:
    return math.hypot(b[0] - a[0], b[1] - a[1])


# ---------- 知识点 3：贝塞尔曲线 ----------

# 三次贝塞尔的 4 个控制点（数学坐标系）
CTRL = [(20.0, 20.0), (70.0, 100.0), (200.0, 100.0), (270.0, 20.0)]


def de_casteljau_levels(points, t):
    """德卡斯特里奥算法：返回每一层的插值点，用于可视化递归过程"""
    levels = [list(points)]
    pts = list(points)
    while len(pts) > 1:
        pts = [lerp_point(pts[i], pts[i + 1], t) for i in range(len(pts) - 1)]
        levels.append(pts)
    return levels


def bezier_point(ctrl, t):
    """三次贝塞尔求一点（德卡斯特里奥递归到只剩一个点）"""
    return de_casteljau_levels(ctrl, t)[-1][0]


def render_bezier_de_casteljau() -> None:
    """24 帧：三次贝塞尔 + 德卡斯特里奥递归插值可视化"""
    out_dir = OUT_DIR / "bezier_de_casteljau"
    out_dir.mkdir(parents=True, exist_ok=True)
    cx, cy = 0, FH - 14

    for f in range(TOTAL):
        img = new_canvas(FW, FH)
        pen = ImageDraw.Draw(img)
        t = f / (TOTAL - 1)

        # 先画完整曲线（浅灰）
        curve = []
        for k in range(101):
            tt = k / 100
            curve.append(to_screen(*bezier_point(CTRL, tt), cx, cy))
        pen.line(curve, fill=(225, 225, 225), width=1)

        levels = de_casteljau_levels(CTRL, t)

        # 控制多边形（虚线感：用浅色实线）
        poly = [to_screen(p[0], p[1], cx, cy) for p in CTRL]
        pen.line(poly, fill=(205, 205, 205), width=1)

        # 各层插值点与连线
        layer_colors = ((60, 100, 200), (60, 160, 90), (200, 140, 40))
        for li in range(1, len(levels)):
            pts = [to_screen(p[0], p[1], cx, cy) for p in levels[li]]
            color = layer_colors[min(li - 1, len(layer_colors) - 1)]
            if len(pts) > 1:
                pen.line(pts, fill=color, width=1)
            for p in pts:
                pen.ellipse([p[0] - 2, p[1] - 2, p[0] + 2, p[1] + 2], fill=color)

        # 控制点（空心方/圆）
        for i, p in enumerate(CTRL):
            sp = to_screen(p[0], p[1], cx, cy)
            pen.ellipse([sp[0] - 4, sp[1] - 4, sp[0] + 4, sp[1] + 4],
                        outline=(200, 60, 60), width=1)
            pen.text((sp[0] + 5, sp[1] - 12), f"P{i}", fill=(200, 60, 60), font=FONT_SM)

        # 最终点（球）
        final = levels[-1][0]
        sp = to_screen(final[0], final[1], cx, cy)
        pen.ellipse([sp[0] - 7, sp[1] - 7, sp[0] + 7, sp[1] + 7], fill=(40, 90, 200))

        pen.text((6, 3), f"f{f:03d}  t = {t:.3f}   德卡斯特里奥：逐层 lerp",
                 fill=(0, 0, 0), font=FONT_SM)
        pen.text((6, 15), f"第1层{len(levels[1])}点 → 第2层{len(levels[2])}点 "
                          f"→ 第3层{len(levels[3])}点 = 曲线上的点",
                 fill=(90, 90, 90), font=FONT_SM)
        pen.text((6, FH - 12), "曲线不穿过中间控制点 P1/P2 —— 它们只是把曲线「拉」过去",
                 fill=(150, 150, 150), font=FONT_SM)

        img.save(out_dir / f"frame_{f:03d}.png")


def render_bezier_basics() -> None:
    """贝塞尔基础：控制点 / 二次 / 三次 / 曲线不穿过中间控制点"""
    cw, ch = 620, 400
    img = new_canvas(cw, ch)
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "贝塞尔曲线：用控制点定义任意曲线", fill=(0, 0, 0), font=FONT)
    pen.text((16, 26), "曲线只保证穿过首末控制点；中间控制点负责把曲线「拉」成想要的形状",
             fill=(80, 80, 80), font=FONT_SM)

    # ---- 左：二次贝塞尔（3 控制点）----
    pen.text((20, 58), "① 二次贝塞尔（3 个控制点）", fill=(0, 0, 0), font=FONT)
    q = [(30.0, 20.0), (110.0, 120.0), (250.0, 20.0)]
    cx, cy = 20, 190
    pts = []
    for k in range(101):
        tt = k / 100
        # 二次贝塞尔：B(t) = (1-t)²P0 + 2(1-t)tP1 + t²P2
        x = (1-tt)**2*q[0][0] + 2*(1-tt)*tt*q[1][0] + tt**2*q[2][0]
        y = (1-tt)**2*q[0][1] + 2*(1-tt)*tt*q[1][1] + tt**2*q[2][1]
        pts.append(to_screen(x, y, cx, cy))
    pen.line(pts, fill=(60, 100, 200), width=3)
    poly = [to_screen(p[0], p[1], cx, cy) for p in q]
    pen.line(poly, fill=(210, 210, 210), width=1)
    for i, p in enumerate(q):
        sp = to_screen(p[0], p[1], cx, cy)
        pen.ellipse([sp[0]-4, sp[1]-4, sp[0]+4, sp[1]+4], outline=(200, 60, 60), width=1)
        pen.text((sp[0]+6, sp[1]-12), f"P{i}", fill=(200, 60, 60), font=FONT_SM)
    pen.text((20, 220), "B(t) = (1-t)²P₀ + 2(1-t)tP₁ + t²P₂", fill=(90, 90, 90), font=FONT_SM)

    # ---- 右：三次贝塞尔（4 控制点）----
    pen.text((330, 58), "② 三次贝塞尔（4 个控制点，最常用）", fill=(0, 0, 0), font=FONT)
    c = [(30.0, 20.0), (90.0, 130.0), (200.0, 130.0), (270.0, 20.0)]
    cx2, cy2 = 330, 190
    pts2 = []
    for k in range(101):
        tt = k / 100
        x = ((1-tt)**3*c[0][0] + 3*(1-tt)**2*tt*c[1][0]
             + 3*(1-tt)*tt**2*c[2][0] + tt**3*c[3][0])
        y = ((1-tt)**3*c[0][1] + 3*(1-tt)**2*tt*c[1][1]
             + 3*(1-tt)*tt**2*c[2][1] + tt**3*c[3][1])
        pts2.append(to_screen(x, y, cx2, cy2))
    pen.line(pts2, fill=(60, 160, 90), width=3)
    poly2 = [to_screen(p[0], p[1], cx2, cy2) for p in c]
    pen.line(poly2, fill=(210, 210, 210), width=1)
    for i, p in enumerate(c):
        sp = to_screen(p[0], p[1], cx2, cy2)
        pen.ellipse([sp[0]-4, sp[1]-4, sp[0]+4, sp[1]+4], outline=(200, 60, 60), width=1)
        pen.text((sp[0]+6, sp[1]-12), f"P{i}", fill=(200, 60, 60), font=FONT_SM)
    pen.text((330, 220), "B(t) = Σ Bernstein(i,n,t)·Pᵢ —— 即 CSS cubic-bezier 的几何含义",
             fill=(90, 90, 90), font=FONT_SM)

    # ---- 底部：Bernstein 与关键性质 ----
    pen.text((16, 260), "Bernstein 基函数（三次，n=3）：", fill=(0, 0, 0), font=FONT)
    pen.text((16, 278), "b₀=(1-t)³   b₁=3(1-t)²t   b₂=3(1-t)t²   b₃=t³      （四个权重，和为 1）",
             fill=(60, 60, 60), font=FONT_SM)

    pen.text((16, 306), "三条关键性质：", fill=(0, 0, 0), font=FONT)
    props = [
        "① 端点插值：B(0)=P₀，B(1)=Pₙ —— 一定穿过首末控制点",
        "② 凸包性：曲线永远在所有控制点的凸包内 —— 不会跑飞",
        "③ 切线：起点切线 = P₀→P₁，终点切线 = Pₙ₋₁→Pₙ —— 便于拼接",
    ]
    for i, ptext in enumerate(props):
        pen.text((20, 324 + i * 15), ptext, fill=(90, 90, 90), font=FONT_SM)

    pen.text((16, 378), "⚠ 曲线「不穿过」中间控制点 P₁/P₂ —— 它们只提供「拉力」，这是新手最常误解的一点",
             fill=(200, 60, 60), font=FONT_SM)

    img.save(OUT_DIR / "bezier_basics.png")


def render_bezier_smoothing() -> None:
    """用贝塞尔拟合折线 = 自动平滑（需求文档的「自动平滑」）"""
    cw, ch = 560, 300
    img = new_canvas(cw, ch)
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "用贝塞尔拟合折线 = 自动平滑", fill=(0, 0, 0), font=FONT)
    pen.text((16, 26), "手绘/AI 生成的线条是锯齿折线 → 把折点当控制点或端点，用贝塞尔重建成平滑曲线",
             fill=(80, 80, 80), font=FONT_SM)

    # 原始折线（锯齿）
    poly = [(30, 200), (80, 120), (130, 180), (180, 100), (230, 170),
            (280, 110), (330, 160), (380, 120), (430, 180), (480, 130)]

    # ---- 上：原始折线 ----
    pen.text((20, 58), "① 原始折线（锯齿、生硬）", fill=(200, 60, 60), font=FONT)
    pen.line(poly, fill=(200, 60, 60), width=2)
    for p in poly:
        pen.ellipse([p[0]-3, p[1]-3, p[0]+3, p[1]+3], fill=(200, 60, 60))

    # ---- 下：贝塞尔平滑后 ----
    pen.text((20, 168), "② 贝塞尔拟合后（平滑、自然）", fill=(60, 160, 90), font=FONT)
    offset = 110
    poly2 = [(p[0], p[1] - offset) for p in poly]

    # 用 Catmull-Rom 风格的方式：每段用三次贝塞尔，控制点由相邻折点推算
    # 简化：对每个内部点，用前后点的方向作为切线方向（这就是自动平滑的核心思路）
    smooth = []
    for i in range(len(poly2) - 1):
        p0 = poly2[i]
        p3 = poly2[i + 1]
        prev_p = poly2[i - 1] if i > 0 else p0
        next_p = poly2[i + 2] if i + 2 < len(poly2) else p3
        # 切线控制点：沿相邻点方向偏移 1/3 段长
        k = 0.28
        c1 = (p0[0] + (p3[0] - prev_p[0]) * k, p0[1] + (p3[1] - prev_p[1]) * k)
        c2 = (p3[0] - (next_p[0] - p0[0]) * k, p3[1] - (next_p[1] - p0[1]) * k)
        for kk in range(21):
            tt = kk / 20
            x = ((1-tt)**3*p0[0] + 3*(1-tt)**2*tt*c1[0]
                 + 3*(1-tt)*tt**2*c2[0] + tt**3*p3[0])
            y = ((1-tt)**3*p0[1] + 3*(1-tt)**2*tt*c1[1]
                 + 3*(1-tt)*tt**2*c2[1] + tt**3*p3[1])
            smooth.append((x, y))
    pen.line(smooth, fill=(60, 160, 90), width=3)
    for p in poly2:
        pen.ellipse([p[0]-3, p[1]-3, p[0]+3, p[1]+3], fill=(150, 150, 150))

    # 说明
    pen.text((20, 250), "核心思路：把每个折点当作贝塞尔的端点，用「相邻点的方向」推算切线控制点 → 段与段平滑衔接",
             fill=(90, 90, 90), font=FONT_SM)
    pen.text((20, 268), "→ 这就是需求文档里「自动平滑」的数学实现；课 2 的小原画（breakdown）也可以这样自动补",
             fill=(90, 90, 90), font=FONT_SM)
    pen.text((20, 288), "⚠ 平滑会「削掉」真实尖角 —— 需要保留尖角的折点要标记为 corner（不参与平滑）",
             fill=(200, 60, 60), font=FONT_SM)

    img.save(OUT_DIR / "bezier_smoothing.png")


# ---------- 知识点 4：沿路径运动（参数 t vs 弧长 s） ----------

PATH_CTRL = [(25.0, 4.0), (80.0, 32.0), (220.0, 32.0), (290.0, 4.0)]
ARC_N = 400


def build_arc_table(ctrl, n: int = ARC_N):
    """预计算弧长表：返回 (ts, 累计弧长列表, 总弧长)"""
    ts = [i / n for i in range(n + 1)]
    pts = [bezier_point(ctrl, t) for t in ts]
    cum = [0.0]
    for i in range(1, len(pts)):
        cum.append(cum[-1] + dist(pts[i - 1], pts[i]))
    return ts, cum, cum[-1]


def point_at_arclength(ctrl, table, s_frac: float):
    """按归一化弧长 s_frac ∈ [0,1] 取曲线上的点（真正匀速）"""
    ts, cum, total = table
    target = s_frac * total
    idx = bisect.bisect_left(cum, target)
    if idx <= 0:
        return bezier_point(ctrl, ts[0])
    if idx >= len(cum):
        return bezier_point(ctrl, ts[-1])
    # 在 [cum[idx-1], cum[idx]] 区间内线性插值出对应的 t
    seg = cum[idx] - cum[idx - 1]
    frac = (target - cum[idx - 1]) / seg if seg > 0 else 0.0
    t = lerp(ts[idx - 1], ts[idx], frac)
    return bezier_point(ctrl, t)


def render_arc_length_vs_param() -> None:
    """上行：参数 t 匀速（速度不均）｜ 下行：弧长 s 匀速（真正匀速）"""
    out_dir = OUT_DIR / "arc_length_vs_param"
    out_dir.mkdir(parents=True, exist_ok=True)
    table = build_arc_table(PATH_CTRL)
    total_len = table[2]

    rows = (
        (40, "上 ❌ 参数 t 匀速", (200, 60, 60), False),
        (100, "下 ✅ 弧长 s 匀速", (60, 160, 90), True),
    )

    for f in range(TOTAL):
        img = new_canvas(FW, FH)
        pen = ImageDraw.Draw(img)
        frac = f / (TOTAL - 1)

        for cy, title, color, use_arc in rows:
            cx = 0
            # 标题
            pen.text((70, cy - 26), title, fill=color, font=FONT_SM)
            # 路径曲线（浅灰）
            curve = [to_screen(*bezier_point(PATH_CTRL, k / 100), cx, cy)
                     for k in range(101)]
            pen.line(curve, fill=(225, 225, 225), width=1)

            # 当前点
            if use_arc:
                pt = point_at_arclength(PATH_CTRL, table, frac)
            else:
                pt = bezier_point(PATH_CTRL, frac)
            sp = to_screen(pt[0], pt[1], cx, cy)

            # 轨迹（过去位置的小点）
            for g in range(f):
                gf = g / (TOTAL - 1)
                if use_arc:
                    gp = point_at_arclength(PATH_CTRL, table, gf)
                else:
                    gp = bezier_point(PATH_CTRL, gf)
                gsp = to_screen(gp[0], gp[1], cx, cy)
                pen.ellipse([gsp[0]-1, gsp[1]-1, gsp[0]+1, gsp[1]+1], fill=(215, 215, 215))

            pen.ellipse([sp[0] - 6, sp[1] - 6, sp[0] + 6, sp[1] + 6], fill=color)

            # 计算本帧走过的距离（spacing）
            if f > 0:
                pf = (f - 1) / (TOTAL - 1)
                if use_arc:
                    pp = point_at_arclength(PATH_CTRL, table, pf)
                else:
                    pp = bezier_point(PATH_CTRL, pf)
                spacing = dist(pp, pt)
            else:
                spacing = float("nan")

            pen.text((6, cy - 14 if use_arc else cy - 14),
                     f"{'弧长' if use_arc else '参数'} s/t={frac:.2f}  spacing="
                     f"{'--' if f == 0 else f'{spacing:.1f}px'}",
                     fill=color, font=FONT_SM)

        pen.text((6, 72), f"f{f:03d}  曲线总长 = {total_len:.0f}px", fill=(0, 0, 0), font=FONT_SM)
        pen.text((6, 82), "上行 spacing 忽大忽小（曲线中段被「拉伸」了）",
                 fill=(200, 60, 60), font=FONT_SM)
        pen.text((6, 92), "下行 spacing 恒定 = 总长/帧数（按实际距离等分）",
                 fill=(60, 160, 90), font=FONT_SM)
        pen.text((6, FH - 12), "→ 沿路径运动要「匀速」，必须用弧长参数化，不能直接用 t",
                 fill=(150, 150, 150), font=FONT_SM)

        img.save(out_dir / f"frame_{f:03d}.png")


# ---------- main ----------

def main() -> None:
    print("=== 知识点 3：贝塞尔曲线 ===")
    render_bezier_de_casteljau()
    print(f"德卡斯特里奥 -> bezier_de_casteljau/ （{TOTAL} 帧，三次贝塞尔 4 控制点）")
    for t in (0.0, 0.5, 1.0):
        lv = de_casteljau_levels(CTRL, t)
        pt = lv[-1][0]
        print(f"    t={t:.1f}  → 点 ({pt[0]:6.1f}, {pt[1]:5.1f})"
              f"   （层级：{len(lv[0])}→{len(lv[1])}→{len(lv[2])}→{len(lv[3])}）")
    print()
    print(f"  端点验证：B(0) = P0 = {CTRL[0]}，B(1) = P3 = {CTRL[3]}")
    mid = bezier_point(CTRL, 0.5)
    print(f"  t=0.5 处的点 = ({mid[0]:.1f}, {mid[1]:.1f})")
    print(f"  → 注意：它不等于任何控制点，也不在 P1/P2 上（曲线不穿过中间控制点）")
    print()

    render_bezier_basics()
    print("贝塞尔基础 -> bezier_basics.png")
    render_bezier_smoothing()
    print("折线→平滑 -> bezier_smoothing.png （需求文档的「自动平滑」）")
    print()

    print("=== 知识点 4：沿路径运动与弧线 ===")
    table = build_arc_table(PATH_CTRL)
    total_len = table[2]
    render_arc_length_vs_param()
    print(f"参数 vs 弧长 -> arc_length_vs_param/ （{TOTAL} 帧）")
    print(f"  曲线总长 = {total_len:.1f}px")
    print()
    print(f"    {'帧':<6}{'参数t spacing':<16}{'弧长s spacing':<16}")
    for f in range(TOTAL):
        frac = f / (TOTAL - 1)
        pt_t = bezier_point(PATH_CTRL, frac)
        pt_s = point_at_arclength(PATH_CTRL, table, frac)
        if f > 0:
            pf = (f - 1) / (TOTAL - 1)
            pp_t = bezier_point(PATH_CTRL, pf)
            pp_s = point_at_arclength(PATH_CTRL, table, pf)
            sp_t = dist(pp_t, pt_t)
            sp_s = dist(pp_s, pt_s)
        else:
            sp_t = sp_s = float("nan")
        if f in (0, 4, 8, 12, 16, 20, 23):
            print(f"    f{f:<5}{'--' if f == 0 else f'{sp_t:.1f}px':<16}"
                  f"{'--' if f == 0 else f'{sp_s:.1f}px':<16}")
    print()
    param_sp = [dist(bezier_point(PATH_CTRL, (g-1)/(TOTAL-1)),
                     bezier_point(PATH_CTRL, g/(TOTAL-1))) for g in range(1, TOTAL)]
    arc_sp = [dist(point_at_arclength(PATH_CTRL, table, (g-1)/(TOTAL-1)),
                   point_at_arclength(PATH_CTRL, table, g/(TOTAL-1))) for g in range(1, TOTAL)]
    print(f"  参数 t：spacing {min(param_sp):.1f} ~ {max(param_sp):.1f}px"
          f"  （最值比 {max(param_sp)/min(param_sp):.1f}×  ← 忽快忽慢）")
    print(f"  弧长 s：spacing {min(arc_sp):.1f} ~ {max(arc_sp):.1f}px"
          f"  （最值比 {max(arc_sp)/min(arc_sp):.2f}×  ← 恒定）")
    print()
    print("  -> 弧长参数化 = 按「实际走过的距离」等分，才能做到真正匀速")
    print("  -> 这对应十二原则第 7 条「弧线运动」：走弧线 + 匀速 = 自然的运动轨迹")


if __name__ == "__main__":
    main()
