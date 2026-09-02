r"""课 3 实操：动画十二原则

把"怎么让动作好看"的几条原则跑出来，生成六组产物：

    spacing_uniform/    匀速（等间距）—— 24 帧
    spacing_ease/       缓入缓出（两端密、中间疏）—— 24 帧
    squash_stretch/     挤压拉伸（保持面积恒定）—— 24 帧
    anticipation/       预备动作对比（上：无预备 / 下：有预备）—— 24 帧
    follow_through/     跟随与重叠（身体停了尾巴继续）—— 24 帧
    easing_compare.png  四种缓动曲线对比图（1 张）

运行方式（PowerShell，先切到课程目录）：
    .\playground\.venv\Scripts\python.exe .\playground\lesson-03\principles_demo.py

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

FPS = 24
DURATION = 1.0
TOTAL = max(1, int(round(DURATION * FPS)))  # 24
W, H = 320, 120
OUT_DIR = Path(__file__).parent


def _load_cn_font(size: int = 10) -> ImageFont.ImageFont:
    """按顺序尝试加载支持中文的字体；全失败则回退默认"""
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


# ---------- 通用工具 ----------

def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def new_canvas() -> Image.Image:
    """一张纯白画布（RGB）"""
    return Image.fromarray(np.full((H, W, 3), 255, dtype=np.uint8))


# ---------- 缓动函数（知识点 3 的核心：慢入慢出 = 缓动函数） ----------

def ease_linear(t: float) -> float:
    """匀速：进度随时间线性增长"""
    return t


def ease_in(t: float) -> float:
    """缓入（慢起快收）：起步慢，越到后面越快"""
    return t * t


def ease_out(t: float) -> float:
    """缓出（快起慢收）：起步快，越接近终点越慢"""
    return 1 - (1 - t) ** 2


def ease_in_out(t: float) -> float:
    """缓入缓出（慢入慢出）：两端慢、中间快 —— 对应十二原则第 6 条"""
    return t * t * (3 - 2 * t)   # smoothstep


# ---------- 知识点 1：时间与间距 ----------

SPACING_X0, SPACING_X1 = 30, 290
SPACING_Y = 62


def spacing_pos(f: int, ease_fn) -> float:
    """第 f 帧球的 x 坐标"""
    t = f / (TOTAL - 1)
    return lerp(SPACING_X0, SPACING_X1, ease_fn(t))


def render_spacing(name: str, ease_fn, label: str) -> list[float]:
    """渲染一组间距演示帧，返回每帧的位移量（spacing）列表"""
    out_dir = OUT_DIR / name
    out_dir.mkdir(parents=True, exist_ok=True)
    spacings = []
    prev_x = spacing_pos(0, ease_fn)

    for f in range(TOTAL):
        x = spacing_pos(f, ease_fn)
        spacings.append(x - prev_x if f > 0 else float("nan"))
        prev_x = x

        img = new_canvas()
        pen = ImageDraw.Draw(img)

        # 过去位置的轨迹点（点的疏密 = 间距 = 速度）
        for g in range(f):
            gx = spacing_pos(g, ease_fn)
            pen.ellipse([gx - 2, SPACING_Y - 2, gx + 2, SPACING_Y + 2], fill=(210, 210, 210))

        # 当前球
        pen.ellipse([x - 9, SPACING_Y - 9, x + 9, SPACING_Y + 9], fill=(40, 90, 200))

        # 文字：帧号 / 位置 / 本帧位移（间距）
        sp = spacings[f]
        sp_text = "--" if f == 0 else f"{sp:.0f}px"
        pen.text((6, 5), f"{label}  f{f:003d}  x={x:.0f}  spacing={sp_text}", fill=(0, 0, 0), font=FONT)

        # 底部标尺：起点 / 终点
        pen.line([(SPACING_X0, SPACING_Y + 22), (SPACING_X1, SPACING_Y + 22)], fill=(200, 200, 200), width=1)
        pen.text((SPACING_X0 - 4, SPACING_Y + 25), "A", fill=(150, 150, 150), font=FONT)
        pen.text((SPACING_X1 - 4, SPACING_Y + 25), "C", fill=(150, 150, 150), font=FONT)

        img.save(out_dir / f"frame_{f:03d}.png")

    return spacings


# ---------- 知识点 2：挤压拉伸 ----------

BALL_R = 16
GROUND_Y = 96


def deform(r: float, d: float) -> tuple[float, float]:
    """d>0 拉伸（变高变瘦），d<0 挤压（变矮变胖）；保持面积恒定 rx*ry = r²"""
    ry = r * (1 + d)
    rx = r * r / ry
    return rx, ry


def squash_state(f: int) -> tuple[float, float, float]:
    """返回 (cy, rx, ry)：球心 y + 半宽 + 半高。一次落地弹跳。"""
    # 关键：cy 用「GROUND_Y - ry」定位，保证球底始终贴地、不穿地
    if f < 9:                     # 下落：越接近地面越快 → 拉伸越明显
        t = f / 8
        rx, ry = deform(BALL_R, 0.30 * t)
        cy = lerp(30, GROUND_Y - ry, t)
    elif f < 12:                  # 触地：挤压后回弹
        t = (f - 9) / 2
        rx, ry = deform(BALL_R, -0.42 * (1 - abs(2 * t - 1)))
        cy = GROUND_Y - ry
    elif f < 21:                  # 弹起：上升中拉伸逐渐减弱
        t = (f - 12) / 8
        rx, ry = deform(BALL_R, 0.30 * (1 - t))
        cy = lerp(GROUND_Y - ry, 44, ease_out(t))
    else:                         # 顶点：恢复正常形状
        cy = 44
        rx = ry = float(BALL_R)
    return cy, rx, ry


def render_squash_stretch() -> None:
    out_dir = OUT_DIR / "squash_stretch"
    out_dir.mkdir(parents=True, exist_ok=True)
    for f in range(TOTAL):
        cy, rx, ry = squash_state(f)
        img = new_canvas()
        pen = ImageDraw.Draw(img)

        # 地面
        pen.rectangle([0, GROUND_Y, W, H], fill=(170, 215, 170))

        # 球（椭圆：rx 半宽、ry 半高）
        pen.ellipse([160 - rx, cy - ry, 160 + rx, cy + ry], fill=(40, 90, 200))

        # 文字：形状状态
        d = ry / rx - 1
        state = "拉伸 stretch" if d > 0.05 else ("挤压 squash" if d < -0.05 else "正常")
        pen.text((6, 5), f"f{f:03d}  {state}  面积≈恒定", fill=(0, 0, 0), font=FONT)
        img.save(out_dir / f"frame_{f:03d}.png")


# ---------- 知识点 2：预备动作 ----------

ANTI_X0, ANTI_X1 = 60, 255


def anti_no(f: int) -> float:
    """无预备：直接冲出去（缓出：起步快、收尾慢）"""
    t = min(f, 18) / 18
    return lerp(ANTI_X0, ANTI_X1, ease_out(t))


def anti_yes(f: int) -> float:
    """有预备：先后退蓄力（0-5），再快速冲出（6-17），最后稳定（18-23）"""
    if f <= 5:                                  # 蓄力后退
        return lerp(ANTI_X0, ANTI_X0 - 22, ease_out(f / 5))
    if f <= 17:                                 # 冲出
        return lerp(ANTI_X0 - 22, ANTI_X1, ease_out((f - 5) / 12))
    return lerp(ANTI_X1, ANTI_X1 - 8, (f - 17) / 6)   # 缓冲稳定


def render_anticipation() -> None:
    out_dir = OUT_DIR / "anticipation"
    out_dir.mkdir(parents=True, exist_ok=True)
    for f in range(TOTAL):
        img = new_canvas()
        pen = ImageDraw.Draw(img)
        # 上行：无预备
        pen.text((6, 6), "上：无预备（直接冲）", fill=(120, 120, 120), font=FONT)
        pen.ellipse([anti_no(f) - 8, 32, anti_no(f) + 8, 48], fill=(200, 80, 80))
        # 下行：有预备
        pen.text((6, 60), "下：有预备（先后退蓄力）", fill=(120, 120, 120), font=FONT)
        pen.ellipse([anti_yes(f) - 8, 86, anti_yes(f) + 8, 102], fill=(60, 140, 90))
        # 起点 / 终点参考线
        pen.line([(ANTI_X0, 20), (ANTI_X0, 110)], fill=(225, 225, 225), width=1)
        pen.line([(ANTI_X1, 20), (ANTI_X1, 110)], fill=(225, 225, 225), width=1)
        img.save(out_dir / f"frame_{f:03d}.png")


# ---------- 知识点 2：跟随与重叠 ----------

FT_X0, FT_X1 = 60, 205
FT_STOP = 12     # 身体在第 12 帧停下


def ft_body(f: int) -> float:
    """身体：0-12 帧从 X0 走到 X1 后停住"""
    return lerp(FT_X0, FT_X1, min(f, FT_STOP) / FT_STOP)


def ft_tail(i: int, f: int) -> float:
    """尾巴第 i 节：延迟跟随 + 身体停下后过冲（overshoot）再回弹"""
    delay = 2 * (i + 1)
    ff = f - delay
    if ff < 0:
        return FT_X0
    base = lerp(FT_X0, FT_X1, min(ff, FT_STOP) / FT_STOP)
    if ff > FT_STOP:                                     # 身体已停，尾巴继续前冲再回弹
        base += 14 * math.sin((ff - FT_STOP) / (TOTAL - 1 - FT_STOP) * math.pi)
    return base


def render_follow_through() -> None:
    out_dir = OUT_DIR / "follow_through"
    out_dir.mkdir(parents=True, exist_ok=True)
    for f in range(TOTAL):
        img = new_canvas()
        pen = ImageDraw.Draw(img)
        pen.text((6, 5), f"f{f:03d}  身体{'已停止' if f >= FT_STOP else '移动中'}  尾巴继续跟随",
                 fill=(0, 0, 0), font=FONT)
        pen.rectangle([0, 100, W, H], fill=(170, 215, 170))       # 地面

        # 尾巴（从后往前画，让身体盖在最上层）
        for i in (2, 1, 0):
            tx = ft_tail(i, f)
            r = 7 - i * 1.5
            pen.ellipse([tx - r, 68 - r, tx + r, 68 + r], fill=(120, 180, 220))

        # 身体
        bx = ft_body(f)
        pen.ellipse([bx - 12, 56, bx + 12, 80], fill=(40, 90, 200))

        # 停止线参考
        pen.line([(FT_X1, 40), (FT_X1, 100)], fill=(225, 225, 225), width=1)
        img.save(out_dir / f"frame_{f:03d}.png")


# ---------- 知识点 3：缓动曲线对比 ----------

def render_easing_compare() -> None:
    """一张图对比四种缓动曲线（慢入慢出 = ease_in_out）"""
    cw, ch = 400, 300
    pad = 46
    img = Image.fromarray(np.full((ch, cw, 3), 255, dtype=np.uint8))
    pen = ImageDraw.Draw(img)

    px0, py0 = pad, pad                      # 绘图区左上角
    px1, py1 = cw - pad, ch - pad            # 绘图区右下角

    # 坐标轴
    pen.line([(px0, py0), (px0, py1)], fill=(120, 120, 120), width=1)   # y 轴
    pen.line([(px0, py1), (px1, py1)], fill=(120, 120, 120), width=1)   # x 轴
    pen.text((px1 - 22, py1 + 8), "时间 t", fill=(80, 80, 80), font=FONT)
    pen.text((4, py0 - 14), "进度", fill=(80, 80, 80), font=FONT)

    # 参考虚线（匀速 = 对角线）
    pen.line([(px0, py1), (px1, py0)], fill=(215, 215, 215), width=1)

    curves = (
        ("linear 匀速", ease_linear, (150, 150, 150)),
        ("ease-in 缓入", ease_in, (40, 90, 200)),
        ("ease-out 缓出", ease_out, (60, 160, 80)),
        ("ease-in-out 慢入慢出", ease_in_out, (200, 60, 60)),
    )

    legend_y = 14
    for name, fn, color in curves:
        pts = []
        for k in range(101):
            t = k / 100
            v = fn(t)
            pts.append((px0 + (px1 - px0) * t, py1 - (py1 - py0) * v))
        pen.line(pts, fill=color, width=2)
        # 图例
        pen.line([(px0, legend_y), (px0 + 22, legend_y)], fill=color, width=3)
        pen.text((px0 + 28, legend_y - 6), name, fill=(60, 60, 60), font=FONT)
        legend_y += 15

    # 标注：慢入慢出的两端很平（= 间距小）
    pen.text((px0 + 4, py1 - 16), "两端平缓 = 间距小 = 慢", fill=(200, 60, 60), font=FONT)
    pen.text((px1 - 128, py0 + 4), "中间陡峭 = 间距大 = 快", fill=(200, 60, 60), font=FONT)

    img.save(OUT_DIR / "easing_compare.png")


# ---------- main ----------

def main() -> None:
    print("=== 知识点 1：时间与间距 ===")
    u = render_spacing("spacing_uniform", ease_linear, "匀速")
    print(f"匀速（等间距）：每帧都移动 {260 / (TOTAL - 1):.1f}px")
    e = render_spacing("spacing_ease", ease_in_out, "缓入缓出")
    print("缓入缓出（两端密、中间疏）：")
    print()
    print(f"{'帧':<6}{'匀速 spacing':<16}{'缓入缓出 spacing':<16}")
    for f in (0, 3, 6, 12, 18, 21, 23):
        us = "--" if f == 0 else f"{u[f]:.0f}px"
        es = "--" if f == 0 else f"{e[f]:.0f}px"
        tag = ""
        if f == 0:
            tag = "  <- 起步"
        elif f == 12:
            tag = "  <- 中点（最快）"
        elif f == 23:
            tag = "  <- 收尾"
        print(f"f{f:<5}{us:<16}{es:<16}{tag}")
    print()
    print("-> 匀速：spacing 全程恒定 = 没有加速度 = 机械感")
    print("-> 缓入缓出：spacing 两端小、中间大 = 有加速度 = 重量感")
    print()

    print("=== 知识点 2：挤压拉伸 / 预备动作 / 跟随与重叠 ===")
    render_squash_stretch()
    print("挤压拉伸 -> squash_stretch/  （面积守恒：rx*ry = R²）")
    render_anticipation()
    print("预备动作 -> anticipation/    （上行无预备 / 下行有预备）")
    render_follow_through()
    print("跟随重叠 -> follow_through/  （身体 f12 停止，尾巴继续过冲回弹）")
    print()

    print("=== 知识点 3：慢入慢出 = 缓动函数 ===")
    render_easing_compare()
    print("四种缓动曲线对比 -> easing_compare.png")
    print()
    print(f"{'t':<6}{'linear':<10}{'ease-in':<10}{'ease-out':<10}{'ease-in-out':<10}")
    for k in (0, 25, 50, 75, 100):
        t = k / 100
        print(f"{t:<6.2f}{ease_linear(t):<10.3f}{ease_in(t):<10.3f}"
              f"{ease_out(t):<10.3f}{ease_in_out(t):<10.3f}")
    print()
    print("-> ease-in-out 就是十二原则第 6 条「慢入慢出」的数学形式")
    print("-> 课 6 会用贝塞尔曲线把这些函数参数化，做成可调的缓动")


if __name__ == "__main__":
    main()
