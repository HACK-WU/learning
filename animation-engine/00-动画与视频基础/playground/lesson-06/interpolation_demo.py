r"""课 6 第一批实操：插值与关键帧补间、缓动函数

把"中间帧怎么算"和"缓动 = 间距分布"跑出来，生成四组产物：

    lerp_basic/          24 帧，A→B 线性插值（匀速），实时显示归一化进度 t
    multi_keyframe/      24 帧，3 个关键帧的分段插值（A→B→C）
    rotation_interp/     24 帧，旋转插值的坑：上行走长路(错) vs 下行走短路(对)
    easing_family.png    常见缓动函数曲线总览 + 缓动↔间距的等价关系

运行方式（PowerShell，先切到课程目录）：
    .\playground\.venv\Scripts\python.exe .\playground\lesson-06\interpolation_demo.py

依赖：numpy、pillow（已装在 playground/.venv）
"""

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Windows 控制台默认用 GBK 输出，中文会变乱码；强制 stdout 用 UTF-8
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

TOTAL = 24          # 帧序列帧数
FW, FH = 320, 120   # 帧序列画布
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


# ---------- 知识点 1：插值 ----------

def lerp(a: float, b: float, t: float) -> float:
    """线性插值：lerp(a, b, t) = a + (b-a)·t = a·(1-t) + b·t"""
    return a + (b - a) * t


def lerp_point(p0, p1, t: float) -> tuple[float, float]:
    """点的线性插值：分别对 x, y 做 lerp"""
    return lerp(p0[0], p1[0], t), lerp(p0[1], p1[1], t)


A_POINT = (30.0, 62.0)
B_POINT = (290.0, 62.0)


def render_lerp_basic() -> None:
    """24 帧：A→B 线性插值（匀速），实时显示归一化进度 t"""
    out_dir = OUT_DIR / "lerp_basic"
    out_dir.mkdir(parents=True, exist_ok=True)

    for f in range(TOTAL):
        img = new_canvas(FW, FH)
        pen = ImageDraw.Draw(img)

        t = f / (TOTAL - 1)                   # 归一化进度 t ∈ [0, 1]
        x, y = lerp_point(A_POINT, B_POINT, t)
        cx, cy = 0, FH - 20                   # 数学原点（只用 y 翻转）

        # 轨迹（过去位置）
        for g in range(f):
            tt = g / (TOTAL - 1)
            gx, gy = lerp_point(A_POINT, B_POINT, tt)
            p = to_screen(gx, gy, cx, cy)
            pen.ellipse([p[0] - 2, p[1] - 2, p[0] + 2, p[1] + 2], fill=(210, 210, 210))

        # 关键帧标记 A / B（空心）
        for name, pt, color in (("A", A_POINT, (200, 60, 60)), ("B", B_POINT, (200, 60, 60))):
            p = to_screen(pt[0], pt[1], cx, cy)
            pen.ellipse([p[0] - 6, p[1] - 6, p[0] + 6, p[1] + 6], outline=color, width=1)
            pen.text((p[0] - 3, p[1] - 18), name, fill=color, font=FONT_SM)

        # 当前球
        p = to_screen(x, y, cx, cy)
        pen.ellipse([p[0] - 9, p[1] - 9, p[0] + 9, p[1] + 9], fill=(40, 90, 200))

        prev_x = lerp_point(A_POINT, B_POINT, (f - 1) / (TOTAL - 1))[0] if f > 0 else x
        sp = x - prev_x if f > 0 else float("nan")
        pen.text((6, 4), f"f{f:03d}  t = {t:.3f}  P = ({x:.0f}, {y:.0f})",
                 fill=(0, 0, 0), font=FONT_SM)
        pen.text((6, 17), f"lerp: P = A·(1-t) + B·t    spacing = "
                          f"{'--' if f == 0 else f'{sp:.1f}px'}",
                 fill=(90, 90, 90), font=FONT_SM)
        pen.text((6, 100), "匀速：spacing 全程恒定（等间距）", fill=(150, 150, 150), font=FONT_SM)

        img.save(out_dir / f"frame_{f:03d}.png")


# 多关键帧：帧号 → 位置
KEYFRAMES = [
    (0,  (30.0, 62.0)),    # 关键帧 A
    (12, (160.0, 44.0)),   # 关键帧 B（小原画，在课 2 叫 breakdown）
    (23, (290.0, 62.0)),   # 关键帧 C
]


def sample_track(f: int):
    """多关键帧分段插值：先找 f 落在哪一段，再在该段内归一化后 lerp"""
    for i in range(len(KEYFRAMES) - 1):
        f0, p0 = KEYFRAMES[i]
        f1, p1 = KEYFRAMES[i + 1]
        if f0 <= f <= f1:
            t = (f - f0) / (f1 - f0)      # 段内归一化进度
            return lerp_point(p0, p1, t), t, i
    # 越界：返回最后一段的终点
    return KEYFRAMES[-1][1], 1.0, len(KEYFRAMES) - 2


def render_multi_keyframe() -> None:
    """24 帧：3 个关键帧的分段插值"""
    out_dir = OUT_DIR / "multi_keyframe"
    out_dir.mkdir(parents=True, exist_ok=True)

    for f in range(TOTAL):
        img = new_canvas(FW, FH)
        pen = ImageDraw.Draw(img)
        (x, y), t, seg = sample_track(f)
        cx, cy = 0, FH - 20

        # 轨迹
        for g in range(f):
            gp, _, _ = sample_track(g)
            p = to_screen(gp[0], gp[1], cx, cy)
            pen.ellipse([p[0] - 2, p[1] - 2, p[0] + 2, p[1] + 2], fill=(210, 210, 210))

        # 关键帧标记
        for name, (kf, kp), color in zip(
            ("A", "B", "C"), KEYFRAMES,
            ((200, 60, 60), (60, 160, 90), (200, 60, 60)),
        ):
            p = to_screen(kp[0], kp[1], cx, cy)
            pen.ellipse([p[0] - 6, p[1] - 6, p[0] + 6, p[1] + 6], outline=color, width=1)
            pen.text((p[0] - 3, p[1] - 18), name, fill=color, font=FONT_SM)
            pen.text((p[0] - 3, p[1] + 8), f"f{kf}", fill=color, font=FONT_SM)

        # 球
        p = to_screen(x, y, cx, cy)
        pen.ellipse([p[0] - 9, p[1] - 9, p[0] + 9, p[1] + 9], fill=(40, 90, 200))

        seg_name = ("A→B" if seg == 0 else "B→C")
        pen.text((6, 4), f"f{f:03d}  段 {seg_name}  段内 t = {t:.3f}  P = ({x:.0f}, {y:.0f})",
                 fill=(0, 0, 0), font=FONT_SM)
        pen.text((6, 17), "多关键帧 = 先定位在哪一段，再在段内做 lerp",
                 fill=(90, 90, 90), font=FONT_SM)
        pen.text((6, 100), "B 是「小原画」(breakdown) —— 课 2 的术语在这里有了数学形式",
                 fill=(150, 150, 150), font=FONT_SM)

        img.save(out_dir / f"frame_{f:03d}.png")


# ---------- 知识点 1：旋转插值的坑 ----------

ANGLE_FROM = 350.0
ANGLE_TO = 10.0


def shortest_angle_delta(a0: float, a1: float) -> float:
    """最短角度差（归一化到 [-180, 180]）——旋转插值必须先做这一步"""
    return ((a1 - a0 + 180.0) % 360.0) - 180.0


def render_rotation_interp() -> None:
    """上行：直接 lerp 角度（走长路 340°，错）｜ 下行：最短路径（走短路 20°，对）"""
    out_dir = OUT_DIR / "rotation_interp"
    out_dir.mkdir(parents=True, exist_ok=True)
    delta = shortest_angle_delta(ANGLE_FROM, ANGLE_TO)

    for f in range(TOTAL):
        img = new_canvas(FW, FH)
        pen = ImageDraw.Draw(img)
        t = f / (TOTAL - 1)

        ang_naive = lerp(ANGLE_FROM, ANGLE_TO, t)              # 走长路
        ang_short = ANGLE_FROM + delta * t                     # 走短路

        rows = (
            (46, "上 ❌ 直接 lerp(350°, 10°) → 倒着走 340°（长路）", (200, 60, 60), ang_naive),
            (100, f"下 ✅ 最短路径 Δ={delta:+.0f}° → 只走 20°（短路）", (60, 160, 90), ang_short),
        )

        for cy, title, color, ang_deg in rows:
            cx = 46
            # 参考圆（半径 18）
            pen.ellipse([cx - 18, cy - 18, cx + 18, cy + 18], outline=(220, 220, 220), width=1)
            # 0° 参考点
            pen.ellipse([cx + 18 - 2, cy - 2, cx + 18 + 2, cy + 2], fill=(220, 220, 220))
            # 指针（注意：屏幕 y 向下，所以角度要取负）
            rad = math.radians(ang_deg)
            tip = (cx + 18 * math.cos(rad), cy - 18 * math.sin(rad))
            pen.line([(cx, cy), tip], fill=color, width=2)
            pen.ellipse([tip[0] - 3, tip[1] - 3, tip[0] + 3, tip[1] + 3], fill=color)
            pen.text((cx + 24, cy - 5), f"{ang_deg % 360:6.1f}°", fill=color, font=FONT_SM)

        pen.text((6, 3), f"f{f:03d}  t = {t:.2f}   起点 350° → 终点 10°",
                 fill=(0, 0, 0), font=FONT_SM)
        pen.text((6, 15), f"最短角差 Δ = ((10-350+180) mod 360) - 180 = {delta:+.0f}°",
                 fill=(90, 90, 90), font=FONT_SM)
        pen.text((6, 112), "位置可直接 lerp；旋转必须先归一化角差，否则会绕远路",
                 fill=(150, 150, 150), font=FONT_SM)

        img.save(out_dir / f"frame_{f:03d}.png")


# ---------- 知识点 2：缓动函数 ----------

def ease_linear(t): return t
def ease_in_quad(t): return t * t
def ease_out_quad(t): return 1 - (1 - t) ** 2
def ease_in_out_quad(t): return 2 * t * t if t < 0.5 else 1 - ((-2 * t + 2) ** 2) / 2
def ease_in_cubic(t): return t ** 3
def ease_out_cubic(t): return 1 - (1 - t) ** 3
def ease_in_out_cubic(t): return 4 * t ** 3 if t < 0.5 else 1 - ((-2 * t + 2) ** 3) / 2


def ease_out_back(t):
    """回弹缓出：冲过终点再弹回来"""
    c1, c3 = 1.70158, 2.70158
    return 1 + c3 * (t - 1) ** 3 + c1 * (t - 1) ** 2


def ease_out_elastic(t):
    """弹性缓出：像弹簧一样来回衰减"""
    if t <= 0: return 0.0
    if t >= 1: return 1.0
    c4 = (2 * math.pi) / 3
    return 2 ** (-10 * t) * math.sin((t * 10 - 0.75) * c4) + 1


EASINGS = [
    ("linear 匀速", ease_linear, (150, 150, 150)),
    ("in-quad 二次缓入", ease_in_quad, (40, 90, 200)),
    ("out-quad 二次缓出", ease_out_quad, (60, 160, 90)),
    ("in-out-cubic 三次缓入缓出", ease_in_out_cubic, (200, 60, 60)),
    ("out-back 回弹", ease_out_back, (150, 80, 190)),
    ("out-elastic 弹性", ease_out_elastic, (220, 140, 40)),
]


def render_easing_family() -> None:
    """常见缓动函数曲线总览 + 缓动↔间距的等价关系"""
    cw, ch = 640, 460
    img = new_canvas(cw, ch)
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "缓动函数 = 把「线性进度 t」映射成「缓动后的进度 t'」",
             fill=(0, 0, 0), font=FONT)
    pen.text((16, 26), "曲线越陡 = 该处间距越大 = 越快；曲线越平 = 间距越小 = 越慢（课 3 的间距 ↔ 课 6 的缓动）",
             fill=(80, 80, 80), font=FONT_SM)

    # 主图：所有缓动曲线叠在一起
    px0, py0, px1, py1 = 60, 50, 580, 300
    pen.rectangle([px0, py0, px1, py1], outline=(200, 200, 200), width=1)
    pen.line([(px0, py1), (px1, py1)], fill=(120, 120, 120), width=1)   # x 轴
    pen.line([(px0, py0), (px0, py1)], fill=(120, 120, 120), width=1)   # y 轴
    pen.text((px1 - 20, py1 + 8), "时间 t", fill=(80, 80, 80), font=FONT_SM)
    pen.text((10, py0 - 6), "进度 t'", fill=(80, 80, 80), font=FONT_SM)
    # (0,0)→(1,1) 参考对角线
    pen.line([(px0, py1), (px1, py0)], fill=(228, 228, 228), width=1)

    legend_y = 320
    for i, (name, fn, color) in enumerate(EASINGS):
        pts = []
        for k in range(201):
            tt = k / 200
            v = fn(tt)
            pts.append((px0 + (px1 - px0) * tt, py1 - (py1 - py0) * v))
        pen.line(pts, fill=color, width=2)
        # 图例（两列）
        col, row = i % 2, i // 2
        lx = 60 + col * 290
        ly = legend_y + row * 16
        pen.line([(lx, ly), (lx + 20, ly)], fill=color, width=3)
        pen.text((lx + 26, ly - 5), name, fill=(60, 60, 60), font=FONT_SM)

    # 底部：缓动 ↔ 间距 的等价关系
    pen.text((16, 400), "缓动 ↔ 间距 的等价关系（课 3 与课 6 在这里对上了）：", fill=(0, 0, 0), font=FONT)
    pen.text((16, 418), "传统动画：画师手工安排「每帧画在哪」→ 间距疏密 = 速度感（经验画法）",
             fill=(90, 90, 90), font=FONT_SM)
    pen.text((16, 434), "数学表达：缓动函数 f(t) 决定进度 → 位置 = lerp(A, B, f(t)) → 间距自动产生（函数表达）",
             fill=(90, 90, 90), font=FONT_SM)
    pen.text((16, 452), "两者是同一件事的两种表达：间距是「结果」，缓动函数是「产生这个结果的规则」",
             fill=(60, 60, 60), font=FONT_SM)

    img.save(OUT_DIR / "easing_family.png")


# ---------- main ----------

def main() -> None:
    print("=== 知识点 1：插值与关键帧补间 ===")
    render_lerp_basic()
    print(f"线性插值 -> lerp_basic/ （{TOTAL} 帧，A(30,62) → B(290,62) 匀速）")
    print()
    print("  lerp: P = A·(1-t) + B·t   （t = f/(N-1) 归一化进度）")
    for f in (0, 6, 12, 18, 23):
        t = f / (TOTAL - 1)
        x, y = lerp_point(A_POINT, B_POINT, t)
        prev_x = lerp_point(A_POINT, B_POINT, (f - 1) / (TOTAL - 1))[0] if f > 0 else x
        sp = x - prev_x if f > 0 else float("nan")
        print(f"    f{f:<3}t={t:.3f}  P=({x:6.1f},{y:5.1f})  "
              f"spacing={'--' if f == 0 else f'{sp:.1f}px'}")
    print("  -> 匀速：spacing 恒定 11.3px（与课 3 的 spacing_uniform 完全一致）")
    print()

    render_multi_keyframe()
    print(f"多关键帧 -> multi_keyframe/ （{TOTAL} 帧，关键帧在 f0 / f12 / f23）")
    for f in (0, 6, 12, 18, 23):
        (x, y), t, seg = sample_track(f)
        seg_name = "A→B" if seg == 0 else "B→C"
        print(f"    f{f:<3}段 {seg_name}  段内 t={t:.3f}  P=({x:6.1f},{y:5.1f})")
    print()

    render_rotation_interp()
    delta = shortest_angle_delta(ANGLE_FROM, ANGLE_TO)
    print(f"旋转插值 -> rotation_interp/ （{TOTAL} 帧，350° → 10°）")
    print(f"  直接 lerp 角度     : Δ = 10 - 350 = -340°   → 倒着走 340°（长路，错误）")
    print(f"  最短角差后再插值   : Δ = {delta:+.0f}°           → 只走 20°（短路，正确）")
    print(f"  公式：Δ = ((a₁ - a₀ + 180) mod 360) - 180")
    print()

    print("=== 知识点 2：缓动函数 ===")
    render_easing_family()
    print(f"缓动曲线总览 -> easing_family.png （{len(EASINGS)} 种）")
    print()
    print("  缓动 → 间距（把 ease-in-out-cubic 套用到 A→B，看间距怎么变）：")
    print(f"    {'帧':<6}{'t':<8}{'eased':<8}{'位置 x':<10}{'spacing':<10}")
    prev_x = A_POINT[0]
    spacings = []
    for f in range(TOTAL):
        t = f / (TOTAL - 1)
        eased = ease_in_out_cubic(t)
        x = lerp(A_POINT[0], B_POINT[0], eased)
        sp = x - prev_x if f > 0 else float("nan")
        if f > 0:
            spacings.append(sp)
        if f in (0, 3, 6, 12, 18, 21, 23):
            print(f"    f{f:<5}{t:<8.3f}{eased:<8.3f}{x:<10.1f}"
                  f"{'--' if f == 0 else f'{sp:.1f}px':<10}")
        prev_x = x
    print()
    print(f"  -> 间距：起点 {spacings[0]:.1f}px（最慢）→ 中间 {max(spacings):.1f}px（最快）"
          f" → 终点 {spacings[-1]:.1f}px（最慢）")
    print(f"     最值比 = {max(spacings) / spacings[0]:.0f}×  ← 这就是课 3 说的「缓入缓出 = 有重量感」")
    print("  -> 结论：缓动函数是「因」，间距是「果」——两者是同一件事的两种表达")


if __name__ == "__main__":
    main()
