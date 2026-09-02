r"""课 8 实操：图层、alpha 与颜色合成

把"图层即独立画布"和"over 运算符是精确公式"两件事跑出来，生成三组产物：

    layer_stack.png            4 个独立 RGBA 图层 + 自底向上合成结果
    over_ramp/                 24 帧，alpha 0→1，逐帧验证 over 公式
    premultiplied_compare.png  非预乘（脏边）vs 预乘（干净）对比

运行方式（PowerShell，先切到课程目录）：
    .\playground\.venv\Scripts\python.exe .\playground\lesson-08\layer_alpha_demo.py

依赖：numpy、pillow（已装在 playground/.venv）
"""

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


def checkerboard(w: int, h: int, cell: int = 8) -> Image.Image:
    """棋盘底：用来表示"透明"区域"""
    yy, xx = np.mgrid[0:h, 0:w]
    board = (((xx // cell) + (yy // cell)) % 2 == 0)
    arr = np.where(board[..., None], 235, 210).astype(np.uint8)
    arr = np.repeat(arr, 3, axis=2)
    return Image.fromarray(arr)


def over_np(src: np.ndarray, dst: np.ndarray, alpha: float) -> np.ndarray:
    """over 运算符：out = src·α + dst·(1-α)

    src/dst 是 (H, W, 3) 的 float 数组，alpha 是标量或 (H, W, 1)
    """
    return src * alpha + dst * (1.0 - alpha)


def composite_rgba(layers, w, h):
    """自底向上依次合成 RGBA 图层，返回 (H, W, 3) 的 uint8 结果

    layers: 自底向上的 RGBA 图像列表（前面的在下面）
    """
    acc = np.zeros((h, w, 3), dtype=np.float64)   # 从全黑开始
    for layer in layers:
        arr = np.array(layer.convert("RGBA")).astype(np.float64)
        rgb = arr[:, :, :3]
        a = arr[:, :, 3:4] / 255.0
        acc = over_np(rgb, acc, a)                # 新层在上，作为 src
    return Image.fromarray(np.clip(acc, 0, 255).astype(np.uint8))


# ---------- 知识点 1：图层模型 ----------

def _make_layers(w: int, h: int):
    """造 4 个独立 RGBA 图层（自底向上）：背景 / 远山 / 角色 / 前景"""
    layers = []

    # 层 0：背景（不透明）—— 天空 + 地面
    bg = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(bg)
    d.rectangle([0, 0, w, int(h * 0.68)], fill=(150, 200, 235, 255))      # 天空
    d.rectangle([0, int(h * 0.68), w, h], fill=(120, 175, 95, 255))       # 草地
    layers.append(("背景 ground", bg, "z=0  不透明"))

    # 层 1：远山
    mt = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(mt)
    d.polygon([(0, int(h * 0.68)), (int(w * 0.28), int(h * 0.30)),
               (int(w * 0.55), int(h * 0.68))], fill=(110, 130, 150, 255))
    d.polygon([(int(w * 0.45), int(h * 0.68)), (int(w * 0.75), int(h * 0.22)),
               (w, int(h * 0.68))], fill=(95, 115, 135, 255))
    layers.append(("远山 mountain", mt, "z=1  半透明 70%"))
    mt.putalpha(Image.fromarray(
        (np.array(mt.convert("RGBA"))[:, :, 3].astype(float) * 0.7).astype(np.uint8)))

    # 层 2：角色（一个简单火柴人，透明背景）
    ch = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(ch)
    cx = int(w * 0.52)
    d.ellipse([cx - 11, int(h * 0.40), cx + 11, int(h * 0.62)], fill=(235, 200, 120, 255))  # 头
    d.line([cx, int(h * 0.62), cx, int(h * 0.86)], fill=(220, 70, 70, 255), width=6)        # 身
    d.line([cx, int(h * 0.68), cx - 18, int(h * 0.78)], fill=(220, 70, 70, 255), width=5)   # 左手
    d.line([cx, int(h * 0.68), cx + 18, int(h * 0.80)], fill=(220, 70, 70, 255), width=5)   # 右手
    d.line([cx, int(h * 0.86), cx - 13, int(h * 0.97)], fill=(60, 90, 170, 255), width=5)   # 左腿
    d.line([cx, int(h * 0.86), cx + 13, int(h * 0.97)], fill=(60, 90, 170, 255), width=5)   # 右腿
    layers.append(("角色 character", ch, "z=2  大部分透明"))

    # 层 3：前景（底部草丛）
    fg = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(fg)
    for i in range(9):
        x = int(w * (0.03 + i * 0.115))
        d.line([x, h, x + 6, int(h * 0.80)], fill=(60, 130, 60, 255), width=4)
    layers.append(("前景 fore", fg, "z=3  大部分透明"))

    return layers


def render_layer_stack() -> None:
    """4 个独立 RGBA 图层 + 自底向上合成结果"""
    cw, ch = 700, 470
    img = Image.fromarray(np.full((ch, cw, 3), 255, dtype=np.uint8))
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "图层模型：每个图层 = 一张独立的 RGBA 画布，自底向上叠加",
             fill=(0, 0, 0), font=FONT)
    pen.text((16, 26), "下面的缩略图铺在棋盘底上 —— 棋盘 = 该处完全透明（A=0）",
             fill=(80, 80, 80), font=FONT_SM)

    lw, lh = 150, 110
    layers = _make_layers(lw, lh)

    # 逐个图层：铺在棋盘底上显示，暴露透明区域
    for i, (name, layer, note) in enumerate(layers):
        x = 20 + i * 165
        board = checkerboard(lw, lh)
        board.paste(layer, (0, 0), layer)          # 用 alpha 作为蒙版
        img.paste(board, (x, 60))
        pen.rectangle([x, 60, x + lw, 60 + lh], outline=(120, 120, 120))
        pen.text((x, 44), f"层{i}  {name}", fill=(0, 0, 0), font=FONT_SM)
        pen.text((x, 176), note, fill=(90, 90, 90), font=FONT_SM)

    # 合成结果（自底向上）
    comp = composite_rgba([l for _, l, _ in layers], lw, lh)
    big = comp.resize((lw * 2, lh * 2), Image.NEAREST)
    img.paste(big, (200, 215))
    pen.rectangle([200, 215, 200 + lw * 2, 215 + lh * 2], outline=(0, 0, 0), width=2)
    pen.text((200, 195), "合成结果（自底向上：背景 → 远山 → 角色 → 前景）",
             fill=(0, 0, 0), font=FONT)

    # 右侧：图层树
    pen.text((520, 215), "图层树 / group", fill=(0, 0, 0), font=FONT)
    tree = [
        "scene (根)",
        "├─ background",
        "│   └─ ground",
        "├─ midground",
        "│   └─ mountain",
        "├─ actors",
        "│   └─ character",
        "└─ foreground",
        "    └─ grass",
    ]
    for i, t in enumerate(tree):
        pen.text((522, 236 + i * 15), t, fill=(60, 60, 60), font=FONT_SM)
    pen.text((520, 380), "group 的作用：", fill=(0, 0, 0), font=FONT_SM)
    pen.text((522, 396), "整组移动/显隐/改不透明度", fill=(90, 90, 90), font=FONT_SM)
    pen.text((522, 410), "组内仍保各自 z 顺序", fill=(90, 90, 90), font=FONT_SM)

    pen.text((16, 448), "⚠ 合成顺序不能错：over 运算符不满足交换律 —— 先画角色再画背景，"
                        "角色会被背景盖住", fill=(200, 60, 60), font=FONT_SM)

    img.save(OUT_DIR / "layer_stack.png")


# ---------- 知识点 2：alpha 与颜色合成 ----------

def render_over_ramp() -> None:
    """24 帧：红色方块以 alpha 0→1 叠在蓝色背景上，逐帧验证 over 公式"""
    out_dir = OUT_DIR / "over_ramp"
    out_dir.mkdir(parents=True, exist_ok=True)

    src_rgb = (220, 40, 40)      # 前景：红
    dst_rgb = (40, 90, 200)      # 背景：蓝
    size = 130

    for f in range(TOTAL):
        alpha = f / (TOTAL - 1)          # 0 → 1
        a = np.full((size, size, 1), alpha, dtype=np.float64)
        src = np.full((size, size, 3), src_rgb, dtype=np.float64)
        dst = np.full((size, size, 3), dst_rgb, dtype=np.float64)
        out = over_np(src, dst, a)
        out_u8 = np.clip(out, 0, 255).astype(np.uint8)

        patch = Image.fromarray(out_u8)

        cw, ch = 460, 260
        img = Image.fromarray(np.full((ch, cw, 3), 255, dtype=np.uint8))
        pen = ImageDraw.Draw(img)

        pen.text((16, 8), f"f{f:03d}   alpha = {alpha:.3f}   "
                          f"out = src·α + dst·(1-α)", fill=(0, 0, 0), font=FONT)

        # 左：源色；中：目标色；右：合成结果
        sw = Image.new("RGB", (size, size), src_rgb)
        dw = Image.new("RGB", (size, size), dst_rgb)
        img.paste(sw, (16, 40))
        img.paste(dw, (160, 40))
        img.paste(patch, (304, 40))
        for x, label in ((16, "src 红"), (160, "dst 蓝"), (304, "over 结果")):
            pen.rectangle([x, 40, x + size, 40 + size], outline=(120, 120, 120))
            pen.text((x, 178), label, fill=(60, 60, 60), font=FONT_SM)

        # 手算三通道
        r = src_rgb[0] * alpha + dst_rgb[0] * (1 - alpha)
        g = src_rgb[1] * alpha + dst_rgb[1] * (1 - alpha)
        b = src_rgb[2] * alpha + dst_rgb[2] * (1 - alpha)

        pen.text((16, 200), f"R = {src_rgb[0]}×{alpha:.3f} + {dst_rgb[0]}×{1-alpha:.3f} = {r:6.1f}",
                 fill=(180, 40, 40), font=FONT_SM)
        pen.text((16, 214), f"G = {src_rgb[1]}×{alpha:.3f} + {dst_rgb[1]}×{1-alpha:.3f} = {g:6.1f}",
                 fill=(40, 140, 70), font=FONT_SM)
        pen.text((16, 228), f"B = {src_rgb[2]}×{alpha:.3f} + {dst_rgb[2]}×{1-alpha:.3f} = {b:6.1f}",
                 fill=(40, 90, 200), font=FONT_SM)
        pen.text((240, 214), f"→ 取整 ({r:.0f}, {g:.0f}, {b:.0f})", fill=(0, 0, 0), font=FONT)

        # 进度条（放在标签下方，避免压住文字）
        pen.rectangle([304, 192, 304 + size, 200], fill=(220, 220, 220))
        pen.rectangle([304, 192, 304 + int(size * alpha), 200], fill=(220, 40, 40))

        img.save(out_dir / f"frame_{f:03d}.png")


def render_premultiplied_compare() -> None:
    """非预乘（脏边）vs 预乘（干净）—— 缩放插值时的边缘污染

    关键：原图必须用**软边圆**（边缘有 alpha 渐变），否则硬边圆在 BILINEAR
    下插值带只有 1 原像素宽，放大后也几乎不可见。
    """
    cw, ch = 640, 380
    img = Image.fromarray(np.full((ch, cw, 3), 255, dtype=np.uint8))
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "预乘 alpha（premultiplied alpha）：解决缩放/插值时的「脏边」伪影",
             fill=(0, 0, 0), font=FONT)
    pen.text((16, 26), "透明区域的 RGB 本无意义，但非预乘插值会把它算进去 → 边缘被污染",
             fill=(80, 80, 80), font=FONT_SM)
    y_img = 62
    pen.text((40, 42), "❌ 非预乘（RGBA 直接插值）", fill=(200, 60, 60), font=FONT)
    pen.text((360, 42), "✅ 预乘（先 ×α 再插值再 ÷α）", fill=(60, 160, 90), font=FONT)

    # 造一个软边红色圆：内部实心 (220,40,40) 不透明，边缘 6 像素渐变到完全透明 (0,0,0,0)
    base = 60
    edge_w = 6
    radius = base // 2 - edge_w
    yy, xx = np.mgrid[0:base, 0:base].astype(np.float64)
    dist = np.sqrt((yy - base / 2 + 0.5) ** 2 + (xx - base / 2 + 0.5) ** 2)
    alpha01 = np.clip(1.0 - (dist - radius) / edge_w, 0.0, 1.0)
    arr = np.zeros((base, base, 4), dtype=np.uint8)
    arr[:, :, 0] = 220
    arr[:, :, 1] = 40
    arr[:, :, 2] = 40
    arr[:, :, 3] = (alpha01 * 255).astype(np.uint8)
    src = Image.fromarray(arr)

    scale = 4
    big = base * scale     # 240

    # ① 非预乘：直接对 RGBA 四个通道各自 BILINEAR 插值
    naive = src.resize((big, big), Image.BILINEAR)

    # ② 预乘：先 rgb×α，再 BILINEAR，再除回
    src_f = arr.astype(np.float64)
    a01_src = src_f[:, :, 3:4] / 255.0
    premult = np.concatenate([src_f[:, :, :3] * a01_src, src_f[:, :, 3:4]], axis=2)
    premult_img = Image.fromarray(np.clip(premult, 0, 255).astype(np.uint8))
    resized = premult_img.resize((big, big), Image.BILINEAR)
    out_f = np.array(resized).astype(np.float64)
    a01_out = np.maximum(out_f[:, :, 3:4] / 255.0, 1e-6)   # 防除零
    rgb_un = np.clip(out_f[:, :, :3] / a01_out, 0, 255)
    proper = Image.fromarray(
        np.concatenate([rgb_un, out_f[:, :, 3:4]], axis=2).astype(np.uint8))

    # 合成到白色底上，脏边会呈现为暗色光晕
    bg_color = (255, 255, 255)
    board_l = Image.new("RGB", (big, big), bg_color)
    board_l.paste(naive, (0, 0), naive)
    board_r = Image.new("RGB", (big, big), bg_color)
    board_r.paste(proper, (0, 0), proper)

    # 布局：上方两张大图，下方数值对比
    img.paste(board_l, (40, y_img))
    img.paste(board_r, (360, y_img))

    # 自动找一个边缘像素（alpha 约 100~150 处）来取证
    n_arr = np.array(naive).astype(np.float64)
    p_arr = np.array(proper).astype(np.float64)
    # 在 y=big/2 一行找 alpha 处于 (80, 200) 的最左像素
    row = big // 2
    n_alpha_row = n_arr[row, :, 3]
    p_alpha_row = p_arr[row, :, 3]
    n_pxs = np.where((n_alpha_row > 80) & (n_alpha_row < 200))[0]
    p_pxs = np.where((p_alpha_row > 80) & (p_alpha_row < 200))[0]
    n_idx = n_pxs[0] if len(n_pxs) else 0
    p_idx = p_pxs[0] if len(p_pxs) else 0
    nv, pv = n_arr[row, n_idx], p_arr[row, p_idx]

    y_take = y_img + big + 12
    pen.text((16, y_take),
             f"取证（边缘 α≈{nv[3]:.0f} 的像素）：",
             fill=(0, 0, 0), font=FONT)
    pen.text((16, y_take + 18),
             f"  非预乘 RGB = ({nv[0]:.0f}, {nv[1]:.0f}, {nv[2]:.0f})   ← 被 (0,0,0) 污染，颜色发暗",
             fill=(200, 60, 60), font=FONT_SM)
    pen.text((16, y_take + 34),
             f"  预   乘 RGB = ({pv[0]:.0f}, {pv[1]:.0f}, {pv[2]:.0f})   ← 保持纯红，边缘干净",
             fill=(60, 160, 90), font=FONT_SM)

    img.save(OUT_DIR / "premultiplied_compare.png")


# ---------- main ----------

def main() -> None:
    print("=== 知识点 1：图层模型 ===")
    render_layer_stack()
    print("图层栈 -> layer_stack.png")
    print("  -> 每个图层是一张独立 RGBA 画布；棋盘底表示该处 A=0（完全透明）")
    print("  -> 合成 = 自底向上反复套用 over：背景 → 远山 → 角色 → 前景")
    print("  ⚠ over 不满足交换律：顺序颠倒，角色会被背景盖住")
    print()

    print("=== 知识点 2：alpha 与颜色合成 ===")
    render_over_ramp()
    print(f"over 运算符 -> over_ramp/ （{TOTAL} 帧，alpha 0→1）")

    # 手算验证：红 (220,40,40) 叠在蓝 (40,90,200) 上，alpha=0.5
    src = np.array([220.0, 40.0, 40.0])
    dst = np.array([40.0, 90.0, 200.0])
    print()
    print("  手算验证  src=(220,40,40)  dst=(40,90,200)  alpha=0.5：")
    for a in (0.0, 0.25, 0.5, 0.75, 1.0):
        out = over_np(src, dst, a)
        print(f"    alpha={a:.2f}  →  ({out[0]:6.1f}, {out[1]:6.1f}, {out[2]:6.1f})"
              f"  取整 ({out[0]:.0f}, {out[1]:.0f}, {out[2]:.0f})")
    print()
    print("  边界检查：")
    print("    alpha=0 → 完全取 dst（前景不存在）")
    print("    alpha=1 → 完全取 src（前景不透明，盖住背景）")
    print()

    render_premultiplied_compare()
    print("预乘 alpha -> premultiplied_compare.png")
    print("  -> 非预乘：透明区 RGB=(0,0,0) 被插值算进去 → 边缘发暗（脏边）")
    print("  -> 预乘：先 rgb×a 再插值再除回 → 纯色保持，边缘干净")
    print()
    print("  ⚠ 预乘不是「更清晰的画质」，是「让插值数学正确」——")
    print("    透明像素的 RGB 本无意义，非预乘却让它参与了平均")
    print()


if __name__ == "__main__":
    main()
