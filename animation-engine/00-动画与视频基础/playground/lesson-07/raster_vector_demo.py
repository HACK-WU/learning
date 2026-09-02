r"""课 7 实操：光栅与矢量

把"像素网格"和"数据即图形"两种世界观跑出来，生成四组产物：

    raster_basics.png        RGBA 画布的 NumPy 结构 + 通道 + 字节数
    resolution_ramp/         24 帧，同一个圆在递增分辨率下渲染（锯齿逐渐消失）
    vector_scaling.png       同一矢量图形渲染到多种分辨率（分辨率无关）
    antialiasing_compare.png 锯齿 vs 抗锯齿（超采样原理）

运行方式（PowerShell，先切到课程目录）：
    .\playground\.venv\Scripts\python.exe .\playground\lesson-07\raster_vector_demo.py

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


def new_canvas(w: int, h: int, rgba: bool = False) -> Image.Image:
    """新建画布；rgba=True 时带 alpha 通道"""
    ch = 4 if rgba else 3
    return Image.fromarray(np.zeros((h, w, ch), dtype=np.uint8))


# ---------- 知识点 1：光栅图像 ----------

def render_raster_basics() -> None:
    """RGBA 画布的 NumPy 结构 + 四个通道 + 字节数"""
    cw, ch = 620, 380
    img = Image.fromarray(np.full((ch, cw, 3), 255, dtype=np.uint8))
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "光栅图像 = 像素网格，每个格子存一个颜色", fill=(0, 0, 0), font=FONT)
    pen.text((16, 26), "NumPy 形状：(H, W, C) —— 行、列、通道；dtype=uint8 → 每通道 0~255",
             fill=(80, 80, 80), font=FONT_SM)

    # ---- 左：小画布的像素网格（6×4，放大显示）----
    pen.text((20, 56), "① 一个 6×4 的画布（每格 = 1 像素，此处放大显示）", fill=(0, 0, 0), font=FONT)

    # 造几个有代表性的像素
    demo = np.zeros((4, 6, 4), dtype=np.uint8)
    demo[:, :] = [255, 255, 255, 255]          # 默认不透明白
    demo[1, 1] = [220, 60, 60, 255]            # 红，不透明
    demo[1, 2] = [60, 140, 220, 128]           # 蓝，半透明
    demo[2, 3] = [60, 180, 90, 255]            # 绿，不透明
    demo[2, 4] = [0, 0, 0, 0]                  # 完全透明

    cell = 34
    ox, oy = 30, 80
    # 先铺棋盘底（表示"透明"）
    for r in range(4):
        for c in range(6):
            x, y = ox + c * cell, oy + r * cell
            pen.rectangle([x, y, x + cell, y + cell],
                          fill=(235, 235, 235) if (r + c) % 2 == 0 else (215, 215, 215))
    # 再画实际像素（按 alpha 与棋盘混合，模拟显示效果）
    for r in range(4):
        for c in range(6):
            px = demo[r, c]
            a = px[3] / 255.0
            base = 235 if (r + c) % 2 == 0 else 215
            shown = tuple(int(round(px[i] * a + base * (1 - a))) for i in range(3))
            x, y = ox + c * cell, oy + r * cell
            pen.rectangle([x, y, x + cell, y + cell], fill=shown, outline=(180, 180, 180))

    # 标注几个特殊像素
    def mark(r, c, text, color):
        x, y = ox + c * cell, oy + r * cell
        pen.rectangle([x, y, x + cell, y + cell], outline=color, width=2)
        pen.text((x + 2, y + cell + 2), text, fill=color, font=FONT_SM)

    mark(1, 1, "R,G,B,A=(220,60,60,255)", (200, 60, 60))
    mark(1, 2, "半透明 A=128", (60, 100, 200))
    mark(2, 4, "完全透明 A=0", (120, 120, 120))

    # ---- 右：通道与位深 ----
    pen.text((330, 56), "② 通道与位深", fill=(0, 0, 0), font=FONT)
    channels = [
        ("R  红", (220, 60, 60), "0~255"),
        ("G  绿", (60, 180, 90), "0~255"),
        ("B  蓝", (60, 140, 220), "0~255"),
        ("A  透明度", (150, 150, 150), "0=全透 / 255=不透"),
    ]
    for i, (name, color, rng) in enumerate(channels):
        y = 84 + i * 26
        pen.rectangle([330, y, 356, y + 18], fill=color, outline=(150, 150, 150))
        pen.text((364, y + 4), f"{name}   每通道 8 bit   {rng}", fill=(60, 60, 60), font=FONT_SM)

    # 位深与字节数
    pen.text((330, 200), "常见位深与存储量：", fill=(0, 0, 0), font=FONT)
    rows = [
        ("RGB  24 bit", "W×H×3 字节"),
        ("RGBA 32 bit", "W×H×4 字节"),
        ("灰度 8 bit", "W×H×1 字节"),
    ]
    for i, (a, b) in enumerate(rows):
        pen.text((340, 222 + i * 16), f"{a}  →  {b}", fill=(60, 60, 60), font=FONT_SM)

    # 实例计算
    w, h = 1920, 1080
    pen.text((330, 286), f"实例：{w}×{h} 的 RGBA 画布", fill=(0, 0, 0), font=FONT)
    pen.text((340, 306), f"= {w} × {h} × 4 = {w*h*4:,} 字节", fill=(60, 60, 60), font=FONT_SM)
    pen.text((340, 322), f"≈ {w*h*4/1024/1024:.1f} MB（未压缩，全在内存里）",
             fill=(200, 60, 60), font=FONT_SM)

    # ---- 底部：锯齿的本质 ----
    pen.text((16, 352), "⚠ 锯齿的本质：连续的数学形状要用离散的像素格子去「近似」，"
                        "边缘只能整格取舍 → 斜线/曲线出现阶梯",
             fill=(200, 60, 60), font=FONT_SM)

    img.save(OUT_DIR / "raster_basics.png")


def render_resolution_ramp() -> None:
    """24 帧：同一个圆在递增分辨率下渲染（锯齿逐渐消失）"""
    out_dir = OUT_DIR / "resolution_ramp"
    out_dir.mkdir(parents=True, exist_ok=True)

    # 24 帧：内部渲染分辨率从 12 递增到 240，显示窗口固定 240
    disp = 240
    for f in range(TOTAL):
        inner = int(round(12 + (240 - 12) * f / (TOTAL - 1)))
        # 在低分辨率画布上画圆，再用最近邻放大到显示尺寸（暴露锯齿）
        small = Image.fromarray(np.zeros((inner, inner, 3), dtype=np.uint8))
        sp = ImageDraw.Draw(small)
        sp.ellipse([inner * 0.06, inner * 0.06, inner * 0.94, inner * 0.94],
                   fill=(40, 90, 200))
        big = small.resize((disp, disp), Image.NEAREST)

        # 画布宽 560：左 16..256、右 296..536，两个 240 的图都能完整放下
        img = Image.fromarray(np.full((300, 560, 3), 255, dtype=np.uint8))
        pen = ImageDraw.Draw(img)
        pen.text((16, 8), f"f{f:03d}   内部渲染分辨率 = {inner}×{inner}"
                          f"（放大到 {disp}×{disp} 显示，最近邻）",
                 fill=(0, 0, 0), font=FONT)
        img.paste(big, (16, 30))

        # 右侧参照：全分辨率 + 4× 超采样抗锯齿
        ss = 4
        hi = Image.fromarray(np.zeros((disp * ss, disp * ss, 3), dtype=np.uint8))
        hp = ImageDraw.Draw(hi)
        hp.ellipse([disp * ss * 0.06, disp * ss * 0.06, disp * ss * 0.94, disp * ss * 0.94],
                   fill=(60, 160, 90))
        ref = hi.resize((disp, disp), Image.LANCZOS)
        pen.text((296, 8), "参照：全分辨率 + 抗锯齿", fill=(60, 160, 90), font=FONT)
        img.paste(ref, (296, 30))

        pen.text((16, 284), f"左：{inner}×{inner} 光栅（放大后锯齿可见）",
                 fill=(200, 60, 60), font=FONT_SM)
        pen.text((296, 284), "右：全分辨率 + 抗锯齿（平滑）",
                 fill=(60, 160, 90), font=FONT_SM)

        img.save(out_dir / f"frame_{f:03d}.png")


# ---------- 知识点 2：矢量图形 ----------

def render_vector_scaling() -> None:
    """同一矢量图形渲染到多种分辨率 —— 分辨率无关"""
    cw, ch = 620, 300
    img = Image.fromarray(np.full((ch, cw, 3), 255, dtype=np.uint8))
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "矢量图形 = 数据即图形：同一份「描述」，可渲染到任意分辨率",
             fill=(0, 0, 0), font=FONT)
    pen.text((16, 26), "下面每个格子里的图形，都由**同一组路径与控制点**生成 —— 只是输出分辨率不同",
             fill=(80, 80, 80), font=FONT_SM)

    # 用五角星（路径 = 10 个顶点）演示，分辨率递增
    def star_points(cx, cy, r_out, r_in, n=5, rot=-math.pi / 2):
        pts = []
        for i in range(n * 2):
            r = r_out if i % 2 == 0 else r_in
            a = rot + i * math.pi / n
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        return pts

    sizes = (32, 64, 128, 256)
    shown_size = 140
    x0 = 16
    for s in sizes:
        tile = Image.fromarray(np.zeros((s, s, 3), dtype=np.uint8))
        tp = ImageDraw.Draw(tile)
        pts = star_points(s / 2, s / 2, s * 0.46, s * 0.19)
        tp.polygon(pts, fill=(40, 90, 200), outline=(20, 50, 120))
        # 统一放大到 140 显示（用最近邻，暴露各自真实的像素密度）
        shown = tile.resize((shown_size, shown_size), Image.NEAREST)
        img.paste(shown, (x0, 50))
        pen.text((x0 + 44, 200), f"{s}×{s}", fill=(60, 60, 60), font=FONT)
        pen.text((x0 + 30, 216), f"{s * s:,} px", fill=(150, 150, 150), font=FONT_SM)
        x0 += shown_size + 10

    # 右侧说明
    pen.text((16, 248), "同一份矢量数据（10 个顶点的星形路径）→ 渲染到 32² / 64² / 128² / 256² 都成立",
             fill=(90, 90, 90), font=FONT_SM)
    pen.text((16, 264), "分辨率无关 = 存的是「公式」不是「结果」；"
                        "放大时重新求值，而不是把已有像素拉大",
             fill=(60, 60, 60), font=FONT_SM)
    pen.text((16, 284), "⚠ 对比：光栅图像放大 = 把像素格子拉大（插值猜测新像素）→ 必然模糊",
             fill=(200, 60, 60), font=FONT_SM)

    img.save(OUT_DIR / "vector_scaling.png")


# ---------- 知识点 3：抗锯齿 ----------

def render_antialiasing_compare() -> None:
    """锯齿 vs 抗锯齿（超采样原理）"""
    cw, ch = 620, 320
    img = Image.fromarray(np.full((ch, cw, 3), 255, dtype=np.uint8))
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "抗锯齿（anti-aliasing）：边缘像素按「覆盖率」取中间色，而不是二选一",
             fill=(0, 0, 0), font=FONT)
    pen.text((16, 26), "超采样做法：先按 4× 分辨率画，再用 LANCZOS 缩回 —— 边缘得到加权平均",
             fill=(80, 80, 80), font=FONT_SM)

    base = 120   # 逻辑尺寸
    ss = 4       # 超采样倍数

    # ---- 左：无抗锯齿 ----
    aliased = Image.fromarray(np.zeros((base, base, 3), dtype=np.uint8))
    ap = ImageDraw.Draw(aliased)
    ap.ellipse([base * 0.1, base * 0.1, base * 0.9, base * 0.9], fill=(200, 60, 60))
    aliased_big = aliased.resize((240, 240), Image.NEAREST)

    # ---- 右：抗锯齿（4× 超采样）----
    hi = Image.fromarray(np.zeros((base * ss, base * ss, 3), dtype=np.uint8))
    hp = ImageDraw.Draw(hi)
    hp.ellipse([base * ss * 0.1, base * ss * 0.1, base * ss * 0.9, base * ss * 0.9],
               fill=(60, 160, 90))
    aa_big = hi.resize((240, 240), Image.LANCZOS)

    img.paste(aliased_big, (30, 50))
    img.paste(aa_big, (350, 50))

    pen.text((30, 30), "❌ 无抗锯齿（硬边 0/1 取舍）", fill=(200, 60, 60), font=FONT)
    pen.text((350, 30), "✅ 抗锯齿（覆盖率加权）", fill=(60, 160, 90), font=FONT)

    pen.text((30, 300), "边缘像素非黑即白 → 阶梯", fill=(200, 60, 60), font=FONT_SM)
    pen.text((350, 300), "边缘像素取中间色 → 视觉平滑", fill=(60, 160, 90), font=FONT_SM)

    img.save(OUT_DIR / "antialiasing_compare.png")


# ---------- main ----------

def main() -> None:
    print("=== 知识点 1：光栅图像 ===")
    render_raster_basics()
    print("RGBA 画布结构 -> raster_basics.png")

    # 用 NumPy 演示画布
    W, H = 320, 240
    canvas = np.zeros((H, W, 4), dtype=np.uint8)
    print(f"  canvas = np.zeros(({H}, {W}, 4), dtype=np.uint8)")
    print(f"    .shape  = {canvas.shape}      # (H, W, C) 行 / 列 / 通道")
    print(f"    .dtype  = {canvas.dtype}            # 每通道 8 bit，取值 0~255")
    print(f"    .nbytes = {canvas.nbytes:,} 字节  = {canvas.nbytes/1024:.1f} KB")
    print()
    print("  单像素读写（行在前、列在后）：")
    canvas[10, 20] = [220, 60, 60, 255]
    print(f"    canvas[10, 20] = [220, 60, 60, 255]   # 第 10 行、第 20 列")
    print(f"    读回：{list(canvas[10, 20])}   R={canvas[10,20][0]} "
          f"G={canvas[10,20][1]} B={canvas[10,20][2]} A={canvas[10,20][3]}")
    print()
    print("  ⚠ 常见坑：数组索引是 [y, x]（先行后列），"
          "但坐标常写成 (x, y) —— 两者顺序相反")
    print()

    render_resolution_ramp()
    print(f"分辨率递增 -> resolution_ramp/ （{TOTAL} 帧，12×12 → 240×240）")
    print("  -> 分辨率越低，锯齿越明显；分辨率足够高时阶梯消失")
    print()

    print("=== 知识点 2：矢量图形 ===")
    render_vector_scaling()
    print("矢量渲染到多分辨率 -> vector_scaling.png")
    print("  -> 同一份路径数据（10 个顶点的星形）→ 32/64/128/256 都成立")
    print("  -> 分辨率无关 = 存公式而非结果；放大时重新求值")
    print()

    print("=== 知识点 3：两种表示的分工 ===")
    render_antialiasing_compare()
    print("抗锯齿对比 -> antialiasing_compare.png")
    print("  -> 超采样：按 4× 画 → LANCZOS 缩回 → 边缘按覆盖率取中间色")
    print()
    print("  引擎流水线：")
    print("    矢量数据（路径/控制点/变换矩阵）")
    print("      → 几何变换（课 5 矩阵）")
    print("      → 光栅化 + 抗锯齿   ← 本课的关键一步")
    print("      → 图层合成（课 8 alpha / z 排序）")
    print("      → 编码导出（阶段 4）")
    print()


if __name__ == "__main__":
    main()
