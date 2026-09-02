r"""课 5 第一批实操：仿射变换的直觉、2D 变换矩阵

把"线性 vs 仿射"和"矩阵怎么表示变换"跑出来，生成四组产物：

    linear_vs_affine.png   线性变换（原点不动）vs 仿射变换（原点可动）
    basis_vectors.png      2×2 矩阵列的含义 + 旋转 / 缩放 / 错切矩阵
    rotation_demo/         24 帧，三角形绕原点旋转（数学系逆时针）
    order_matters/         24 帧，先旋转后平移 vs 先平移后旋转（上下对比）

运行方式（PowerShell，先切到课程目录）：
    .\playground\.venv\Scripts\python.exe .\playground\lesson-05\transform_demo.py

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


# ---------- 课 4 的坐标转换在这里落地 ----------

def to_screen(x: float, y: float, cx: float, cy: float) -> tuple[int, int]:
    """数学坐标 (x, y) → 屏幕像素（课 4：屏幕 y 向下，所以要翻转）

    返回整数：PIL 的 line/polygon 对浮点坐标兼容不佳，统一取整最稳。
    """
    return int(round(cx + x)), int(round(cy - y))


# ---------- 2×2 变换矩阵 ----------

def mat_rotate(theta: float) -> np.ndarray:
    """旋转矩阵（数学系：逆时针为正）"""
    c, s = math.cos(theta), math.sin(theta)
    return np.array([[c, -s], [s, c]])


def mat_scale(sx: float, sy: float) -> np.ndarray:
    """缩放矩阵"""
    return np.array([[sx, 0.0], [0.0, sy]])


def mat_shear(k: float) -> np.ndarray:
    """错切矩阵（x 方向）"""
    return np.array([[1.0, k], [0.0, 1.0]])


def apply_mat(M: np.ndarray, v) -> np.ndarray:
    """矩阵 × 列向量"""
    return M @ np.asarray(v, dtype=float)


# 待变换的形状：一个不对称三角形（旋转方向看得出来）
TRI = [(0.0, 0.0), (34.0, 0.0), (0.0, 22.0)]


# ---------- 知识点 1：线性 vs 仿射 ----------

def render_linear_vs_affine() -> None:
    """线性变换（原点不动）vs 仿射变换（原点可动）"""
    cw, ch = 640, 320
    img = new_canvas(cw, ch)
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "线性变换 vs 仿射变换：唯一区别是「原点动不动」", fill=(0, 0, 0), font=FONT)
    pen.text((16, 26), "线性 v' = M·v    ｜    仿射 v' = M·v + t   （= 线性 + 平移）",
             fill=(80, 80, 80), font=FONT_SM)

    size = 230
    panels = (
        (30,  "① 线性变换：缩放 1.6×", (200, 60, 60), False),
        (360, "② 仿射变换：缩放 1.6× 后再平移 (45, 25)", (60, 100, 200), True),
    )

    M = mat_scale(1.6, 1.6)
    TVEC = np.array([45.0, 25.0])

    for x0, title, color, do_translate in panels:
        y0 = 46
        pen.rectangle([x0, y0, x0 + size, y0 + size], outline=(160, 160, 160), width=1)
        # 数学原点放在画布偏左下，留出平移空间
        cx, cy = x0 + 40, y0 + size - 40

        # 坐标轴（数学系：y 向上）
        pen.line([(cx, cy), (cx, y0 + 12)], fill=(200, 200, 200), width=1)          # y 轴
        pen.line([(cx, cy), (x0 + size - 12, cy)], fill=(200, 200, 200), width=1)   # x 轴
        pen.text((cx + 4, y0 + 14), "y", fill=(180, 180, 180), font=FONT_SM)
        pen.text((x0 + size - 22, cy + 4), "x", fill=(180, 180, 180), font=FONT_SM)

        # 原形状（浅灰）
        orig_pts = [to_screen(p[0], p[1], cx, cy) for p in TRI]
        pen.polygon(orig_pts, fill=(225, 225, 225))

        # 变换后
        new_pts = []
        for p in TRI:
            v = apply_mat(M, p)
            if do_translate:
                v = v + TVEC
            new_pts.append(to_screen(v[0], v[1], cx, cy))
        pen.polygon(new_pts, fill=color)

        # 原点：变换前后各标一次
        o0 = to_screen(0, 0, cx, cy)
        pen.ellipse([o0[0] - 7, o0[1] - 7, o0[0] + 7, o0[1] + 7], fill=(90, 90, 90))
        pen.text((o0[0] + 9, o0[1] - 4), "原点", fill=(90, 90, 90), font=FONT_SM)

        # 变换后的原点位置（关键对比点）
        ov = apply_mat(M, [0.0, 0.0])
        if do_translate:
            ov = ov + TVEC
        o1 = to_screen(ov[0], ov[1], cx, cy)
        mark = "✗ 原点跑了" if do_translate else "✓ 原点还在原地"
        pen.ellipse([o1[0] - 4, o1[1] - 4, o1[0] + 4, o1[1] + 4],
                    fill=(200, 60, 60) if do_translate else (60, 160, 90))
        pen.text((o1[0] + 8, o1[1] - 4), mark,
                 fill=(200, 60, 60) if do_translate else (60, 160, 90), font=FONT_SM)

        pen.text((x0, y0 + size + 8), title, fill=(80, 80, 80), font=FONT_SM)

    pen.text((16, 300), "结论：线性变换必须满足 T(0)=0（原点映到原点），平移把原点挪走了 → "
                        "平移不是线性变换；所以「仿射 = 线性 + 平移」要分开处理",
             fill=(0, 0, 0), font=FONT_SM)

    img.save(OUT_DIR / "linear_vs_affine.png")


# ---------- 知识点 2：2×2 矩阵列的含义 ----------

def render_basis_vectors() -> None:
    """2×2 矩阵的列 = 基向量变换后去了哪里"""
    cw, ch = 620, 380
    img = new_canvas(cw, ch)
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "2×2 矩阵的列 = 基向量 î, ĵ 变换后去了哪里", fill=(0, 0, 0), font=FONT)
    pen.text((16, 26), "M = [ c₁  c₂ ]，其中 c₁ = M·(1,0)，c₂ = M·(0,1) —— 知道两列就知道整个变换",
             fill=(80, 80, 80), font=FONT_SM)

    def draw_panel(x0, y0, size, M, title, note, color):
        cx, cy = x0 + 30, y0 + size - 30
        pen.rectangle([x0, y0, x0 + size, y0 + size], outline=(160, 160, 160), width=1)

        # 原始基向量（浅灰虚线感）
        pen.line([(cx, cy), to_screen(30, 0, cx, cy)], fill=(210, 210, 210), width=1)
        pen.line([(cx, cy), to_screen(0, 30, cx, cy)], fill=(210, 210, 210), width=1)

        # 变换后的基向量
        i2 = apply_mat(M, [30.0, 0.0])
        j2 = apply_mat(M, [0.0, 30.0])
        pen.line([(cx, cy), to_screen(i2[0], i2[1], cx, cy)], fill=color, width=3)
        pen.line([(cx, cy), to_screen(j2[0], j2[1], cx, cy)], fill=color, width=3)
        pen.text((to_screen(i2[0], i2[1], cx, cy)[0] + 4, to_screen(i2[0], i2[1], cx, cy)[1] - 12),
                 "c₁", fill=color, font=FONT_SM)
        pen.text((to_screen(j2[0], j2[1], cx, cy)[0] + 4, to_screen(j2[0], j2[1], cx, cy)[1] - 12),
                 "c₂", fill=color, font=FONT_SM)

        # 单位正方形（变换后的平行四边形，直观显示"格子怎么歪"）
        quad = [to_screen(*apply_mat(M, p), cx, cy)
                for p in ((0.0, 0.0), (30.0, 0.0), (30.0, 30.0), (0.0, 30.0))]
        light = tuple(min(255, c + 150) for c in color)   # RGB 画布：fill 只吃 3 元组
        pen.polygon(quad, fill=light, outline=color)

        pen.text((x0, y0 + size + 6), title, fill=(80, 80, 80), font=FONT_SM)
        pen.text((x0, y0 + size + 18), note, fill=(120, 120, 120), font=FONT_SM)

    th = math.radians(35)
    draw_panel(20, 46, 180, mat_scale(1.7, 1.7),
               "缩放 sx=sy=1.7", "两列同向拉长 → 格子放大但不变形", (200, 60, 60))
    draw_panel(215, 46, 180, mat_rotate(th),
               f"旋转 {math.degrees(th):.0f}° (数学系逆时针)",
               "î→(cos,sin), ĵ→(-sin,cos)", (60, 100, 200))
    draw_panel(410, 46, 180, mat_shear(0.9),
               "错切 k=0.9", "只推 î 的 y 分量 → 格子歪了但面积不变", (60, 160, 90))

    # 矩阵形式
    pen.text((16, 262), "三种矩阵的标准形式：", fill=(0, 0, 0), font=FONT)
    forms = [
        ("缩放", "M = ⎡ sx    0  ⎤\n      ⎣  0   sy ⎦", 20),
        ("旋转", "M = ⎡ cosθ  -sinθ ⎤\n      ⎣ sinθ   cosθ ⎦", 230),
        ("错切", "M = ⎡ 1    k ⎤\n      ⎣ 0    1 ⎦", 450),
    ]
    for name, form, fx in forms:
        pen.text((fx, 280), f"{name}：", fill=(60, 60, 60), font=FONT)
        for i, line in enumerate(form.split("\n")):
            pen.text((fx + 34, 278 + i * 13), line, fill=(40, 40, 40), font=FONT_SM)

    pen.text((16, 336), "记忆口诀：矩阵乘法 M·v 的结果，就是「v 的 x 分量 × 第 1 列 + v 的 y 分量 × 第 2 列」",
             fill=(0, 0, 0), font=FONT_SM)
    pen.text((16, 352), "⚠ 屏幕 y 向下，所以数学系的「逆时针」在屏幕上看起来是顺时针 —— 课 4 的 y 翻转在这里生效",
             fill=(200, 60, 60), font=FONT_SM)

    img.save(OUT_DIR / "basis_vectors.png")


# ---------- 知识点 2：旋转动画 ----------

def render_rotation_demo() -> None:
    """24 帧：三角形绕原点旋转一整圈（数学系逆时针）"""
    out_dir = OUT_DIR / "rotation_demo"
    out_dir.mkdir(parents=True, exist_ok=True)

    for f in range(TOTAL):
        img = new_canvas(FW, FH)
        pen = ImageDraw.Draw(img)
        theta = 2 * math.pi * f / TOTAL
        M = mat_rotate(theta)
        cx, cy = 70, 78          # 数学原点在画布偏左下

        # 坐标轴
        pen.line([(cx, cy), (cx, 12)], fill=(215, 215, 215), width=1)
        pen.line([(cx, cy), (FW - 14, cy)], fill=(215, 215, 215), width=1)

        # 原形状（浅灰）
        pen.polygon([to_screen(p[0], p[1], cx, cy) for p in TRI], fill=(232, 232, 232))

        # 旋转后
        pts = [to_screen(*apply_mat(M, p), cx, cy) for p in TRI]
        pen.polygon(pts, fill=(40, 90, 200))

        # 原点
        pen.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=(90, 90, 90))

        deg = math.degrees(theta)
        pen.text((6, 5), f"f{f:03d}  θ = {deg:6.1f}°  （数学系逆时针）", fill=(0, 0, 0), font=FONT_SM)
        pen.text((6, 19), f"M = ⎡{math.cos(theta):6.3f} {math.sin(theta):6.3f}⎤"
                          f"   注意屏幕 y 向下 → 视觉上是顺时针",
                 fill=(90, 90, 90), font=FONT_SM)
        pen.text((6, 33), f"    ⎣{-math.sin(theta):6.3f} {math.cos(theta):6.3f}⎦",
                 fill=(90, 90, 90), font=FONT_SM)

        img.save(out_dir / f"frame_{f:03d}.png")


# ---------- 知识点 2：顺序不可交换 ----------

TVEC = np.array([62.0, 34.0])


def render_order_matters() -> None:
    """24 帧：上行 T·R（先旋转后平移）vs 下行 R·T（先平移后旋转）"""
    out_dir = OUT_DIR / "order_matters"
    out_dir.mkdir(parents=True, exist_ok=True)

    for f in range(TOTAL):
        img = new_canvas(FW, FH)
        pen = ImageDraw.Draw(img)
        theta = math.radians(90) * f / (TOTAL - 1)
        M = mat_rotate(theta)

        rows = (
            (52, "上：先旋转后平移  P' = T·R·P = R·P + t", (60, 100, 200)),
            (106, "下：先平移后旋转  P' = R·T·P = R·(P + t)", (200, 90, 60)),
        )

        for cy, title, color in rows:
            cx = 62
            # 坐标轴（淡）
            pen.line([(cx, cy), (cx + 40, cy)], fill=(225, 225, 225), width=1)
            # 原形状
            pen.polygon([to_screen(p[0], p[1], cx, cy) for p in TRI], fill=(235, 235, 235))

            if "先旋转后平移" in title:
                pts = [to_screen(*(apply_mat(M, p) + TVEC), cx, cy) for p in TRI]
            else:
                pts = [to_screen(*apply_mat(M, np.asarray(p) + TVEC), cx, cy) for p in TRI]
            pen.polygon(pts, fill=color)

            # 原点
            pen.ellipse([cx - 3, cy - 3, cx + 3, cy + 3], fill=(120, 120, 120))

        deg = math.degrees(theta)
        # 两条路径的终点差
        p1 = apply_mat(M, TRI[1]) + TVEC
        p2 = apply_mat(M, np.asarray(TRI[1]) + TVEC)
        diff = math.hypot(p1[0] - p2[0], p1[1] - p2[1])

        pen.text((6, 4), f"f{f:03d}  θ={deg:5.1f}°  两行终点相距 {diff:5.1f}px",
                 fill=(0, 0, 0), font=FONT_SM)
        pen.text((6, 90), "上行 T·R：转完再搬 —— 平移向量不被旋转",
                 fill=(60, 100, 200), font=FONT_SM)
        pen.text((6, 100), "下行 R·T：先搬再转 —— 平移向量也被转了",
                 fill=(200, 90, 60), font=FONT_SM)
        pen.text((6, 112), "→ R·T·P = R·P + R·t，而 T·R·P = R·P + t；"
                          " R·t ≠ t 时两者不同", fill=(120, 120, 120), font=FONT_SM)

        img.save(out_dir / f"frame_{f:03d}.png")


# ---------- main ----------

def main() -> None:
    print("=== 知识点 1：仿射变换的直觉 ===")
    render_linear_vs_affine()
    print("线性 vs 仿射 -> linear_vs_affine.png")
    M = mat_scale(1.6, 1.6)
    o_lin = apply_mat(M, (0.0, 0.0))
    o_aff = apply_mat(M, (0.0, 0.0)) + np.array([45.0, 25.0])
    print(f"  线性：v' = M·v      → T(0) = ({o_lin[0]:.1f}, {o_lin[1]:.1f})   原点还在原点 ✓")
    print(f"  仿射：v' = M·v + t  → T(0) = ({o_aff[0]:.1f}, {o_aff[1]:.1f})  原点被挪走 → 不是线性 ✗")
    print()

    print("=== 知识点 2：2D 变换矩阵 ===")
    render_basis_vectors()
    print("矩阵列的含义 -> basis_vectors.png")
    th = math.radians(90)
    i2 = apply_mat(mat_rotate(th), (1.0, 0.0))
    j2 = apply_mat(mat_rotate(th), (0.0, 1.0))
    print(f"  旋转 90°：î=(1,0) → ({i2[0]:.0f}, {i2[1]:.0f})    ĵ=(0,1) → ({j2[0]:.0f}, {j2[1]:.0f})")
    print("  （第 1 列就是 î 去哪、第 2 列就是 ĵ 去哪 —— 这就是矩阵列的几何含义）")
    print()

    render_rotation_demo()
    print(f"旋转动画 -> rotation_demo/ （{TOTAL} 帧，绕原点转一整圈）")

    render_order_matters()
    print(f"顺序不可交换 -> order_matters/ （{TOTAL} 帧，上行 T·R / 下行 R·T）")
    print()
    print("  顺序对比（θ 从 0° 到 90°，t = (62, 34)）：")
    for f in (0, 8, 16, 23):
        theta = math.radians(90) * f / (TOTAL - 1)
        M = mat_rotate(theta)
        p1 = apply_mat(M, TRI[1]) + TVEC
        p2 = apply_mat(M, np.asarray(TRI[1]) + TVEC)
        d = math.hypot(p1[0] - p2[0], p1[1] - p2[1])
        print(f"    f{f:<3}θ={math.degrees(theta):5.1f}°  "
              f"T·R→({p1[0]:6.1f},{p1[1]:5.1f})  R·T→({p2[0]:6.1f},{p2[1]:5.1f})  "
              f"相距 {d:5.1f}px")
    print()
    print("  -> θ=0 时两者相同（还没转）；θ>0 后越差越远")


if __name__ == "__main__":
    main()
