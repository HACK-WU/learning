r"""课 4 实操：点与向量

把"位置怎么表示"和"移动怎么表示"跑出来，生成四组产物：

    coords_compare.png   同一组数字 (100,50) 在两种坐标系里指向不同像素（1 张）
    y_flip_bug.png       "图片上下颠倒"这个经典 bug 的成因（1 张）
    vector_translate/    24 帧，一个方块沿向量 (4.0, 2.5) 匀速平移
    vector_ops.png       向量运算总览：加法 / 数乘 / 长度 / 归一化（1 张）

运行方式（PowerShell，先切到课程目录）：
    .\playground\.venv\Scripts\python.exe .\playground\lesson-04\point_vector_demo.py

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
FONT_SM = _load_cn_font(9)


def new_canvas(w: int, h: int) -> Image.Image:
    """一张纯白画布（RGB）"""
    return Image.fromarray(np.full((h, w, 3), 255, dtype=np.uint8))


# ---------- 坐标转换（知识点 1 的核心公式） ----------

def screen_to_math(y_screen: float, h: int) -> float:
    """屏幕 y（原点左上，向下增大）→ 数学 y（原点左下，向上增大）"""
    return (h - 1) - y_screen


def math_to_screen(y_math: float, h: int) -> float:
    """数学 y → 屏幕 y（上面那个函数的逆运算，其实就是它自己）"""
    return (h - 1) - y_math


# ---------- 知识点 1：画布与坐标系 ----------

def render_coords_compare() -> None:
    """同一组数字 (100,50) 在两种坐标系里指向不同的像素"""
    cw, ch = 640, 340
    img = new_canvas(cw, ch)
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "同一组数字 (100, 50) —— 两种坐标系指向不同的像素",
             fill=(0, 0, 0), font=FONT)

    # 两个子画布：各 200x200
    size = 200
    boxes = (
        (40,  "屏幕坐标系（图像 / 屏幕）\n原点在左上，y 轴向下增大", (200, 60, 60)),
        (380, "数学坐标系（笛卡尔）\n原点在左下，y 轴向上增大", (60, 100, 200)),
    )

    for x0, title, color in boxes:
        y0 = 40
        pen.rectangle([x0, y0, x0 + size, y0 + size], outline=(150, 150, 150), width=1)

        # 坐标轴
        if x0 == 40:      # 屏幕：原点左上
            pen.line([(x0, y0), (x0, y0 + size)], fill=color, width=2)       # y 轴（向下）
            pen.line([(x0, y0), (x0 + size, y0)], fill=color, width=2)       # x 轴（向右）
            pen.text((x0 + 6, y0 + size - 14), "原点(0,0)", fill=color, font=FONT_SM)
            pen.text((x0 + size - 26, y0 + 6), "x→", fill=color, font=FONT_SM)
            pen.text((x0 + 6, y0 + 26), "y↓", fill=color, font=FONT_SM)
            px, py = x0 + 100, y0 + 50
        else:             # 数学：原点左下
            pen.line([(x0, y0 + size), (x0, y0)], fill=color, width=2)       # y 轴（向上）
            pen.line([(x0, y0 + size), (x0 + size, y0 + size)], fill=color, width=2)  # x 轴（向右）
            pen.text((x0 + 6, y0 + size - 14), "原点(0,0)", fill=color, font=FONT_SM)
            pen.text((x0 + size - 26, y0 + size - 16), "x→", fill=color, font=FONT_SM)
            pen.text((x0 + 6, y0 + 8), "↑y", fill=color, font=FONT_SM)
            px, py = x0 + 100, (y0 + size - 1) - 50

        pen.ellipse([px - 5, py - 5, px + 5, py + 5], fill=color)
        pen.text((px + 8, py - 4), "(100,50)", fill=color, font=FONT_SM)
        pen.text((x0, y0 + size + 8), title.split("\n")[0], fill=(80, 80, 80), font=FONT_SM)
        pen.text((x0, y0 + size + 20), title.split("\n")[1], fill=(80, 80, 80), font=FONT_SM)

    # 底部转换公式（明确放在画布下方）
    pen.text((16, 284), "互转公式（H 为画布高度，像素下标 0 ~ H-1）："
                        "  y_数学 = (H - 1) - y_屏幕      注意那个 -1：像素从 0 开始数",
             fill=(0, 0, 0), font=FONT_SM)
    pen.text((16, 300), "⚠ 漏掉 -1 会造成整幅图偏移 1 像素——这类 off-by-one 是图形代码最常见的 bug",
             fill=(200, 60, 60), font=FONT_SM)
    pen.text((16, 320), "→ 课 8 实战时，所有像素坐标运算都用屏幕系；"
                        "只有与角度/三角函数打交道时才用数学系（避免旋转方向搞反）",
             fill=(0, 0, 0), font=FONT_SM)

    img.save(OUT_DIR / "coords_compare.png")


def render_y_flip_bug() -> None:
    """演示"图片上下颠倒"这个 bug：数据按数学系算，渲染按屏幕系画"""
    cw, ch = 640, 300
    img = new_canvas(cw, ch)
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "经典 bug：用数学坐标系算数据，却按屏幕坐标系画 → 上下颠倒",
             fill=(0, 0, 0), font=FONT)

    size = 200
    # 一个简单的"房子"形状，顶点用数学坐标系定义（原点左下，y 向上）
    house_math = [(20, 20), (100, 20), (100, 80), (60, 120), (20, 80)]

    panels = (
        (30,  "✅ 正确：画之前做了 y 翻转", True),
        (350, "❌ 错误：忘了 y 翻转 → 上下颠倒", False),
    )

    for x0, title, do_flip in panels:
        y0 = 40
        pen.rectangle([x0, y0, x0 + size, y0 + size], outline=(150, 150, 150), width=1)
        # 基线
        pen.line([(x0, y0 + size), (x0 + size, y0 + size)], fill=(190, 190, 190), width=1)

        pts = []
        for mx, my in house_math:
            sx = x0 + mx
            sy = (y0 + size - 1) - my if do_flip else (y0 + my)
            pts.append((sx, sy))
        color = (60, 140, 90) if do_flip else (200, 80, 80)
        pen.polygon(pts, fill=color)

        pen.text((x0, y0 + size + 10), title, fill=(80, 80, 80), font=FONT_SM)

    pen.text((16, 268), "成因：两组坐标「看起来都是 (x, y)」，但 y 轴方向相反——"
                        "数据没标坐标系，渲染时就全错了", fill=(0, 0, 0), font=FONT_SM)
    pen.text((16, 284), "工程对策：① 在数据里显式标注坐标系；② 只在 I/O 边界做一次转换，中间全程用一种",
             fill=(0, 0, 0), font=FONT_SM)

    img.save(OUT_DIR / "y_flip_bug.png")


# ---------- 知识点 2：向量与位移 ----------

VEC = (10.0, 2.5)     # 每帧的位移向量（24 帧内不越界，保证全程可见）
START = (30.0, 42.0)  # 起点（点）


def pos_at(f: int) -> tuple[float, float]:
    """点 + 向量×帧数 = 平移后的新点"""
    return START[0] + VEC[0] * f, START[1] + VEC[1] * f


def render_vector_translate() -> None:
    """24 帧：一个方块沿向量 (4.0, 2.5) 匀速平移"""
    out_dir = OUT_DIR / "vector_translate"
    out_dir.mkdir(parents=True, exist_ok=True)

    for f in range(TOTAL):
        img = new_canvas(FW, FH)
        pen = ImageDraw.Draw(img)
        x, y = pos_at(f)

        # 起点标记
        pen.ellipse([START[0] - 3, START[1] - 3, START[0] + 3, START[1] + 3],
                    fill=(200, 200, 200))
        pen.text((START[0] + 6, START[1] - 4), "P0", fill=(150, 150, 150), font=FONT_SM)

        # 从起点到当前点的位移向量（箭头）
        pen.line([(START[0], START[1]), (x, y)], fill=(90, 90, 90), width=1)
        # 箭头头部（画一个小三角，方向 = 向量方向）
        ang = math.atan2(VEC[1], VEC[0])
        for da in (-2.6, 2.6):
            ax = x + 8 * math.cos(ang + da)
            ay = y + 8 * math.sin(ang + da)
            pen.line([(x, y), (ax, ay)], fill=(90, 90, 90), width=1)

        # 当前方块（点 + 位移向量 的结果）
        pen.rectangle([x - 8, y - 8, x + 8, y + 8], fill=(40, 90, 200))

        # 文字
        total_dx, total_dy = VEC[0] * f, VEC[1] * f
        pen.text((6, 5),
                 f"f{f:03d}  P = P0 + v×{f} = ({x:.0f},{y:.0f})  位移=({total_dx:.0f},{total_dy:.0f})",
                 fill=(0, 0, 0), font=FONT_SM)
        pen.text((6, 20), f"v = ({VEC[0]}, {VEC[1]})   |v| = {math.hypot(*VEC):.3f}",
                 fill=(90, 90, 90), font=FONT_SM)

        img.save(out_dir / f"frame_{f:03d}.png")


def render_vector_ops() -> None:
    """向量运算总览：加法 / 数乘 / 长度 / 归一化"""
    cw, ch = 560, 420
    img = new_canvas(cw, ch)
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "向量运算总览：加法 / 数乘 / 长度 / 归一化", fill=(0, 0, 0), font=FONT)

    def arrow(x0, y0, x1, y1, color, width=2, label=None):
        pen.line([(x0, y0), (x1, y1)], fill=color, width=width)
        ang = math.atan2(y1 - y0, x1 - x0)
        for da in (-2.6, 2.6):
            pen.line([(x1, y1), (x1 + 9 * math.cos(ang + da), y1 + 9 * math.sin(ang + da))],
                     fill=color, width=width)
        if label:
            pen.text((x1 + 6, y1 - 4), label, fill=color, font=FONT_SM)

    # --- 1. 向量加法（三角形法则） ---
    pen.text((20, 40), "① 向量加法（三角形法则）", fill=(0, 0, 0), font=FONT)
    a, b = (60, 40), (40, 70)
    ox, oy = 40, 90
    arrow(ox, oy, ox + a[0], oy + a[1], (60, 100, 200), label="a")
    arrow(ox + a[0], oy + a[1], ox + a[0] + b[0], oy + a[1] + b[1], (60, 160, 90), label="b")
    arrow(ox, oy, ox + a[0] + b[0], oy + a[1] + b[1], (30, 30, 30), width=3, label="a+b")
    pen.text((ox, oy + 130), f"a=({a[0]},{a[1]})  b=({b[0]},{b[1]})  a+b=({a[0]+b[0]},{a[1]+b[1]})",
             fill=(80, 80, 80), font=FONT_SM)

    # --- 2. 数乘 ---
    pen.text((300, 40), "② 数乘（缩放长度，方向不变）", fill=(0, 0, 0), font=FONT)
    v = (50, 35)
    ox2, oy2 = 320, 90
    for k, color in ((1.0, (60, 100, 200)), (2.0, (200, 120, 60)), (0.5, (120, 180, 120))):
        arrow(ox2, oy2, ox2 + v[0] * k, oy2 + v[1] * k, color, label=f"{k}v")
    pen.text((ox2, oy2 + 130), f"v=({v[0]},{v[1]})   k>1 变长 / 0<k<1 变短 / k<0 反向",
             fill=(80, 80, 80), font=FONT_SM)

    # --- 3. 长度与归一化 ---
    pen.text((20, 250), "③ 长度（模）与归一化", fill=(0, 0, 0), font=FONT)
    w = (120, 90)
    ox3, oy3 = 40, 300
    arrow(ox3, oy3, ox3 + w[0], oy3 + w[1], (150, 80, 180), label="v")
    length = math.hypot(*w)
    unit = (w[0] / length, w[1] / length)
    # 单位向量（画在起点，长度缩放到 50 便于观察）
    arrow(ox3, oy3, ox3 + unit[0] * 50, oy3 + unit[1] * 50, (60, 160, 90), label="v̂ (单位)")
    pen.text((ox3 + 140, oy3 - 6), f"|v| = √({w[0]}²+{w[1]}²) = {length:.2f}",
             fill=(80, 80, 80), font=FONT_SM)
    pen.text((ox3 + 140, oy3 + 10), f"v̂ = v/|v| = ({unit[0]:.3f}, {unit[1]:.3f})",
             fill=(80, 80, 80), font=FONT_SM)
    pen.text((ox3 + 140, oy3 + 26), f"|v̂| = {math.hypot(*unit):.3f}  （恒为 1）",
             fill=(80, 80, 80), font=FONT_SM)

    # --- 4. 点 vs 向量（代数规则） ---
    pen.text((20, 380), "④ 点 vs 向量的代数规则（课 5 齐次坐标会解释为什么）",
             fill=(0, 0, 0), font=FONT)
    rules = [
        "点 − 点   = 向量   （两个位置之差 = 位移）",
        "点 + 向量 = 点     （平移，本课核心）",
        "向量 + 向量 = 向量",
        "点 + 点   = 无意义 ← 两个位置相加没有几何含义",
    ]
    for i, r in enumerate(rules):
        pen.text((30 + (i % 2) * 260, 398 + (i // 2) * 14), r,
                 fill=(60, 60, 60), font=FONT_SM)

    img.save(OUT_DIR / "vector_ops.png")


# ---------- main ----------

def main() -> None:
    print("=== 知识点 1：画布与坐标系 ===")
    render_coords_compare()
    print("坐标对比 -> coords_compare.png")
    h = 240
    print(f"  画布高 H={h}，像素下标 0~{h-1}")
    for ys in (0, 50, h - 1):
        print(f"  屏幕 y={ys:<4}-> 数学 y={screen_to_math(ys, h):<4}"
              f" （公式：y_数学 = (H-1) - y_屏幕）")
    render_y_flip_bug()
    print("上下颠倒 bug -> y_flip_bug.png")
    print()

    print("=== 知识点 2：向量与位移 ===")
    render_vector_translate()
    print(f"平移演示 -> vector_translate/ （24 帧，v=({VEC[0]}, {VEC[1]})）")
    length = math.hypot(*VEC)
    print(f"  |v| = √({VEC[0]}² + {VEC[1]}²) = {length:.3f}")
    print(f"  v̂   = ({VEC[0]/length:.3f}, {VEC[1]/length:.3f})   |v̂| = "
          f"{math.hypot(VEC[0]/length, VEC[1]/length):.3f}")
    print()
    print("  P0 + v×f：")
    for f in (0, 6, 12, 23):
        x, y = pos_at(f)
        print(f"    f{f:<3}-> ({x:6.1f}, {y:5.1f})   累计位移 ({VEC[0]*f:5.1f}, {VEC[1]*f:5.1f})")
    print()
    render_vector_ops()
    print("向量运算总览 -> vector_ops.png")


if __name__ == "__main__":
    main()
