r"""课 8 第二批实操：深度与遮挡、颜色还原与语义标签

把"深度怎么判定"和"颜色标签为什么机器可判定"两件事跑出来，生成四组产物：

    painters_vs_zbuffer.png   画家算法（整层排序）vs z-buffer（逐像素）对比
    zfighting/                24 帧，深度精度不足导致的斑块闪烁
    extreme_color_tag.png     极端颜色标签：标记 → 机器判定 → 还原
    srgb_vs_linear.png        sRGB 直接混合 vs 线性空间混合

运行方式（PowerShell，先切到课程目录）：
    .\playground\.venv\Scripts\python.exe .\playground\lesson-08\depth_color_demo.py

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


# ---------- 知识点 3：深度与遮挡 ----------

def tilted_bar_mask(w: int, h: int, p0, p1, half_width: float) -> np.ndarray:
    """生成一根倾斜长条的布尔掩膜（点到线段距离 <= half_width）"""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    x0, y0 = p0
    x1, y1 = p1
    dx, dy = x1 - x0, y1 - y0
    seg_len2 = dx * dx + dy * dy
    # 投影参数 t（限制在 [0,1] 表示只取线段范围）
    t = ((xx - x0) * dx + (yy - y0) * dy) / seg_len2
    t = np.clip(t, 0.0, 1.0)
    # 到线段上最近点的距离
    px = x0 + t * dx
    py = y0 + t * dy
    dist = np.sqrt((xx - px) ** 2 + (yy - py) ** 2)
    return dist <= half_width


def render_painters_vs_zbuffer() -> None:
    """画家算法（整层一个 z） vs z-buffer（每像素一个 z）

    关键：让每根长条的 z 沿屏幕 x 方向线性变化，于是"谁在前"会在交叉点
    左右两侧发生翻转 —— 整层排序的画家算法无法表达，只能逐像素比较。
    """
    W, H = 300, 200
    color_a = (220, 80, 60)      # 条 A：橙红
    color_b = (60, 110, 210)     # 条 B：蓝

    mask_a = tilted_bar_mask(W, H, (30, 40), (270, 165), 13)
    mask_b = tilted_bar_mask(W, H, (30, 165), (270, 40), 13)

    # 深度图：z 越大 = 越靠近观众
    xx_norm = np.mgrid[0:H, 0:W][1] / (W - 1)
    z_a = 0.15 + 0.70 * xx_norm      # 左→右：远 → 近
    z_b = 0.85 - 0.70 * xx_norm      # 左→右：近 → 远

    # ---- 画家算法：整层只一个 z（用平均 z），排序后依次画 ----
    mean_za, mean_zb = float(z_a[mask_a].mean()), float(z_b[mask_b].mean())
    # 平均 z 几乎相等（都是 0.5），平手时取"后者在上"
    painters = np.zeros((H, W, 3), dtype=np.uint8)
    painters[mask_b] = color_b
    painters[mask_a] = color_a          # A 后画 → A 整根压在 B 上

    # ---- z-buffer：逐像素比较 z ----
    zbuf = np.zeros((H, W, 3), dtype=np.uint8)
    both = mask_a & mask_b
    a_wins = both & (z_a > z_b)
    b_wins = both & (z_b >= z_a)
    zbuf[mask_a & ~both] = color_a
    zbuf[mask_b & ~both] = color_b
    zbuf[a_wins] = color_a
    zbuf[b_wins] = color_b

    # ---- 正确参考（谁 z 大谁在前，同画家算法不同的区域） ----
    # 统计画家算法画错的像素数
    wrong = np.zeros((H, W, 3), dtype=np.uint8)
    # z-buffer 视为正确解
    diff_mask = both & ((painters[:, :, 0] != zbuf[:, :, 0]) |
                        (painters[:, :, 1] != zbuf[:, :, 1]) |
                        (painters[:, :, 2] != zbuf[:, :, 2]))
    n_wrong = int(diff_mask.sum())

    # 把画错的地方标黄
    wrong[diff_mask] = (255, 215, 0)

    # ---- 画图 ----
    cw, ch = 680, 330
    img = Image.fromarray(np.full((ch, cw, 3), 255, dtype=np.uint8))
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "深度与遮挡：画家算法（整层一个 z）vs z-buffer（每像素一个 z）",
             fill=(0, 0, 0), font=FONT)
    pen.text((16, 26), "两根长条的 z 沿 x 方向线性变化 → 交叉点左侧蓝在前、右侧橙在前 —— "
                       "整层排序无法表达", fill=(80, 80, 80), font=FONT_SM)

    # 左：画家算法
    img.paste(Image.fromarray(painters), (20, 50))
    pen.rectangle([20, 50, 20 + W, 50 + H], outline=(100, 100, 100))
    pen.text((20, 258), "❌ 画家算法：整层一个 z，排序后依次画", fill=(200, 60, 60), font=FONT)
    pen.text((20, 274), f"   平均 z：A={mean_za:.3f}  B={mean_zb:.3f}  → 平手，A 整根在上",
             fill=(90, 90, 90), font=FONT_SM)
    pen.text((20, 288), "   结果：左侧该蓝在前的区域被橙盖住 → 错", fill=(200, 60, 60), font=FONT_SM)

    # 中：z-buffer
    img.paste(Image.fromarray(zbuf), (340, 50))
    pen.rectangle([340, 50, 340 + W, 50 + H], outline=(100, 100, 100))
    pen.text((340, 258), "✅ z-buffer：逐像素比较 z，取大者", fill=(60, 160, 90), font=FONT)
    pen.text((340, 274), "   交叉点左侧 z_B > z_A → 蓝在前；右侧 z_A > z_B → 橙在前",
             fill=(90, 90, 90), font=FONT_SM)
    pen.text((340, 288), "   结果：两侧都正确", fill=(60, 160, 90), font=FONT_SM)

    # 右：差异高亮
    diff_img = Image.fromarray(zbuf).copy()
    dpx = diff_img.load()
    for y in range(H):
        for x in range(W):
            if diff_mask[y, x]:
                dpx[x, y] = (255, 200, 0)
    # 差异图缩小显示
    small = diff_img.resize((150, 100), Image.NEAREST)
    img.paste(small, (500, 196))        # 196+100=296 < 330，不超出画布
    pen.text((500, 180), "差异（黄色 = 画错处）", fill=(0, 0, 0), font=FONT_SM)

    # 深度示意小图（放在右侧上方）
    pen.text((500, 50), "深度 z 随 x 变化：", fill=(0, 0, 0), font=FONT_SM)
    dw, dh = 150, 60
    dpanel = Image.fromarray(np.full((dh, dw, 3), 250, dtype=np.uint8))
    dpen = ImageDraw.Draw(dpanel)
    for i in range(dw):
        za_i = 0.15 + 0.70 * (i / (dw - 1))
        zb_i = 0.85 - 0.70 * (i / (dw - 1))
        y_a = int(dh - 5 - za_i * (dh - 12))
        y_b = int(dh - 5 - zb_i * (dh - 12))
        dpen.point((i, y_a), fill=(220, 80, 60))
        dpen.point((i, y_b), fill=(60, 110, 210))
    img.paste(dpanel, (500, 68))
    pen.text((500, 134), "橙线 = z_A   蓝线 = z_B", fill=(90, 90, 90), font=FONT_SM)
    pen.text((500, 148), "两线在中点交叉 →", fill=(90, 90, 90), font=FONT_SM)
    pen.text((500, 162), "左右「谁在前」相反", fill=(90, 90, 90), font=FONT_SM)

    pen.text((16, 312), f"画家算法画错的像素数：{n_wrong:,}（占重叠区的 "
                        f"{100.0 * n_wrong / max(1, int(both.sum())):.1f}%）",
             fill=(0, 0, 0), font=FONT_SM)

    img.save(OUT_DIR / "painters_vs_zbuffer.png")
    return n_wrong, int(both.sum())


def render_zfighting() -> None:
    """24 帧：两个几乎共面的平面，深度缓冲精度不足 → 判定翻转 → 斑块闪烁"""
    out_dir = OUT_DIR / "zfighting"
    out_dir.mkdir(parents=True, exist_ok=True)

    W, H = 300, 190
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)

    depth_bits = 8                    # 故意用很低的深度精度以放大效果
    levels = 2 ** depth_bits
    color_a = (200, 90, 70)
    color_b = (70, 120, 200)

    for f in range(TOTAL):
        # 空间相关的低频扰动：模拟插值/舍入误差
        pattern = (np.sin(xx * 0.075 + f * 0.42) *
                   np.cos(yy * 0.065 - f * 0.31))
        pert = pattern * 0.0022                 # 幅度与量化步长同量级

        drift = 0.0004 * np.sin(f * 0.37)       # 每帧微小漂移

        z_a = 0.5 + pert
        z_b = 0.5 - pert + drift

        # 量化：模拟有限精度的深度缓冲
        q_a = np.round(z_a * levels)
        q_b = np.round(z_b * levels)

        a_top = q_a > q_b
        b_top = q_b > q_a
        tie = q_a == q_b

        out = np.full((H, W, 3), 245, dtype=np.uint8)
        out[a_top] = color_a
        out[b_top] = color_b
        out[tie] = (150, 150, 150)              # 相等处：灰（不确定）

        # 值化展示
        cw, ch = 470, 300
        img = Image.fromarray(np.full((ch, cw, 3), 255, dtype=np.uint8))
        pen = ImageDraw.Draw(img)

        pen.text((16, 8), f"f{f:03d}   z-fighting：深度精度不足 → 判定随扰动翻转 → 斑块闪烁",
                 fill=(0, 0, 0), font=FONT)
        pen.text((16, 24), f"两个平面 z 均 ≈ 0.5（相差 {drift:+.5f}），"
                           f"深度缓冲仅 {depth_bits} bit（{levels} 级）",
                 fill=(80, 80, 80), font=FONT_SM)

        img.paste(Image.fromarray(out), (16, 44))
        pen.rectangle([16, 44, 16 + W, 44 + H], outline=(100, 100, 100))

        # 右侧统计
        pen.text((340, 44), "判定分布：", fill=(0, 0, 0), font=FONT)
        n_a, n_b, n_t = int(a_top.sum()), int(b_top.sum()), int(tie.sum())
        pen.text((348, 62), f"A 在前  {n_a:6,d} px", fill=(200, 90, 70), font=FONT_SM)
        pen.text((348, 78), f"B 在前  {n_b:6,d} px", fill=(70, 120, 200), font=FONT_SM)
        pen.text((348, 94), f"相等    {n_t:6,d} px", fill=(120, 120, 120), font=FONT_SM)

        pen.text((340, 124), "成因：", fill=(0, 0, 0), font=FONT)
        pen.text((348, 142), "① 两面几乎共面", fill=(90, 90, 90), font=FONT_SM)
        pen.text((348, 156), "② 深度缓冲精度有限", fill=(90, 90, 90), font=FONT_SM)
        pen.text((348, 170), "③ 微小误差使比较结果", fill=(90, 90, 90), font=FONT_SM)
        pen.text((360, 184), "在不同像素上翻转", fill=(90, 90, 90), font=FONT_SM)

        pen.text((340, 212), "规避：", fill=(0, 0, 0), font=FONT)
        pen.text((348, 230), "① 拉开 z 间距（别共面）", fill=(60, 140, 80), font=FONT_SM)
        pen.text((348, 244), "② 提高深度缓冲位数", fill=(60, 140, 80), font=FONT_SM)
        pen.text((348, 258), "③ 用整数/定点深度", fill=(60, 140, 80), font=FONT_SM)

        # 底部图例
        pen.rectangle([16, 250, 30, 264], fill=color_a)
        pen.text((36, 250), "A 在前", fill=(90, 90, 90), font=FONT_SM)
        pen.rectangle([96, 250, 110, 264], fill=color_b)
        pen.text((116, 250), "B 在前", fill=(90, 90, 90), font=FONT_SM)
        pen.rectangle([176, 250, 190, 264], fill=(150, 150, 150))
        pen.text((196, 250), "判定相等（灰）", fill=(90, 90, 90), font=FONT_SM)

        pen.text((16, 276), "注意：斑块随时间移动 = 闪烁。真实渲染里这就是"
                            "两平面『打架』的样子", fill=(200, 60, 60), font=FONT_SM)

        img.save(out_dir / f"frame_{f:03d}.png")


# ---------- 知识点 4：颜色还原与语义标签 ----------

def render_extreme_color_tag() -> None:
    """极端颜色标签：标记 → 机器判定（通道阈值）→ 还原成目标内容"""
    W, H = 200, 150

    # 造一张"场景"：背景 + 一个用纯红 (255,0,0) 标记的区域
    scene = Image.fromarray(np.full((H, W, 3), 235, dtype=np.uint8))
    d = ImageDraw.Draw(scene)
    # 一些普通内容（避免纯红）
    d.rectangle([10, 10, W - 10, H - 10], outline=(150, 150, 150))
    d.ellipse([20, 20, 80, 70], fill=(120, 170, 120))
    d.ellipse([100, 30, 170, 90], fill=(140, 140, 190))
    d.rectangle([30, 95, 100, 135], fill=(190, 160, 110))
    # 一个「接近红」的真实内容（暗棕红）—— 用来验证宽松阈值会误伤
    d.rectangle([150, 8, 195, 50], fill=(180, 60, 50))

    # 纯红标记：一个圆形区域（这是"语义标签"）
    tag_color = (255, 0, 0)
    d.ellipse([60, 45, 150, 120], fill=tag_color)

    arr = np.array(scene).astype(int)
    R, G, B = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]

    # ---- 机器判定：通道阈值，零歧义 ----
    mask = (R >= 250) & (G <= 5) & (B <= 5)

    # ---- 还原：把标记区域替换成目标内容（此处用渐变演示）----
    restored = arr.copy().astype(np.uint8)
    yy, xx = np.mgrid[0:H, 0:W]
    grad_r = np.clip(60 + (xx / (W - 1)) * 170, 0, 255).astype(np.uint8)
    grad_g = np.clip(120 + (yy / (H - 1)) * 90, 0, 255).astype(np.uint8)
    grad_b = np.full((H, W), 220, dtype=np.uint8)
    restored[mask, 0] = grad_r[mask]
    restored[mask, 1] = grad_g[mask]
    restored[mask, 2] = grad_b[mask]

    # ---- 画图 ----
    cw, ch = 660, 300
    img = Image.fromarray(np.full((ch, cw, 3), 255, dtype=np.uint8))
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "极端颜色标签：为什么 R=255,G=0,B=0 是「机器可判定」的",
             fill=(0, 0, 0), font=FONT)
    pen.text((16, 26), "不是因为红色好看 —— 是因为它在自然画面里几乎不可能出现，"
                       "所以阈值判定零歧义", fill=(80, 80, 80), font=FONT_SM)

    # 三栏：标记图 / mask / 还原结果
    img.paste(scene, (20, 50))
    pen.rectangle([20, 50, 20 + W, 50 + H], outline=(100, 100, 100))
    pen.text((20, 208), "① 标记图：目标区域填纯红", fill=(0, 0, 0), font=FONT)

    mask_img = Image.fromarray((mask * 255).astype(np.uint8)).convert("RGB")
    img.paste(mask_img, (240, 50))
    pen.rectangle([240, 50, 240 + W, 50 + H], outline=(100, 100, 100))
    pen.text((240, 208), "② 机器判定：mask = (R≥250)&(G≤5)&(B≤5)", fill=(0, 0, 0), font=FONT_SM)
    pen.text((240, 222), f"   命中 {int(mask.sum()):,} 像素，无一处误判", fill=(60, 140, 80), font=FONT_SM)

    img.paste(Image.fromarray(restored), (460, 50))
    pen.rectangle([460, 50, 460 + W, 50 + H], outline=(100, 100, 100))
    pen.text((460, 208), "③ 还原：把 mask 区域换成目标内容", fill=(0, 0, 0), font=FONT_SM)

    # 底部说明
    pen.text((16, 250), "为什么有效：", fill=(0, 0, 0), font=FONT)
    pen.text((28, 268), "• 自然画面里「R 满、G=B=0」几乎不存在 → 不会与真实内容混淆",
             fill=(90, 90, 90), font=FONT_SM)
    pen.text((28, 282), "• 判定只是整数比较，不需要『猜』/不需要 AI 推理 → 确定、可复现、零成本",
             fill=(90, 90, 90), font=FONT_SM)

    # 右侧：反例演示（宽松阈值会误伤右上角的暗棕红真实内容）
    pen.text((430, 250), "反例：阈值放宽到 (R>150)&(G<80)&(B<80)", fill=(0, 0, 0), font=FONT_SM)
    loose = (R > 150) & (G < 80) & (B < 80)
    extra = int(loose.sum()) - int(mask.sum())
    pen.text((442, 268), f"多命中 {extra:,} 像素（右上角暗棕红被误判）",
             fill=(200, 60, 60), font=FONT_SM)
    pen.text((442, 282), "→ 非极端颜色就会误伤 → 不可靠", fill=(200, 60, 60), font=FONT_SM)

    img.save(OUT_DIR / "extreme_color_tag.png")
    return int(mask.sum()), int(loose.sum())


def _srgb_to_linear(c: np.ndarray) -> np.ndarray:
    """sRGB（0~1）→ 线性空间"""
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _linear_to_srgb(c: np.ndarray) -> np.ndarray:
    """线性空间 → sRGB（0~1）"""
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.0031308, c * 12.92,
                    1.055 * np.power(np.clip(c, 0.0, 1.0), 1.0 / 2.4) - 0.055)


def render_srgb_vs_linear() -> None:
    """sRGB 直接混合 vs 线性空间混合 —— 同一个 50/50 混合，结果差很多"""
    cw, ch = 620, 320
    img = Image.fromarray(np.full((ch, cw, 3), 255, dtype=np.uint8))
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "sRGB 与线性空间：混合（插值/合成/模糊）必须在线性空间做",
             fill=(0, 0, 0), font=FONT)
    pen.text((16, 26), "sRGB 是 gamma 编码的「显示值」，不是「物理量」——"
                       "直接对显示值求平均，结果偏暗", fill=(80, 80, 80), font=FONT_SM)

    # 黑白渐变演示
    W, H = 260, 90
    black = np.array([0.0, 0.0, 0.0])
    white = np.array([1.0, 1.0, 1.0])
    t = np.linspace(0.0, 1.0, W)[None, :, None]     # (1, W, 1)

    # ① sRGB 空间直接插值
    srgb_mix = black * (1 - t) + white * t           # 0~1
    srgb_mix = np.repeat(srgb_mix, H, axis=0)

    # ② 转线性 → 插值 → 转回 sRGB
    lin_b = _srgb_to_linear(black)
    lin_w = _srgb_to_linear(white)
    lin_mix = lin_b * (1 - t) + lin_w * t
    lin_back = _linear_to_srgb(lin_mix)
    lin_back = np.repeat(lin_back, H, axis=0)

    strip_srgb = (np.clip(srgb_mix, 0, 1) * 255).astype(np.uint8)
    strip_lin = (np.clip(lin_back, 0, 1) * 255).astype(np.uint8)

    # strip_srgb / strip_lin 已是 (H, W, 3)，直接转图即可
    img.paste(Image.fromarray(strip_srgb), (30, 60))
    img.paste(Image.fromarray(strip_lin), (330, 60))

    pen.text((30, 44), "❌ sRGB 空间直接混合", fill=(200, 60, 60), font=FONT)
    pen.text((330, 44), "✅ 线性空间混合后转回", fill=(60, 160, 90), font=FONT)

    # 中点数值对比
    mid_srgb = float(np.clip(srgb_mix[0, W // 2, 0], 0, 1) * 255)
    mid_lin = float(np.clip(lin_back[0, W // 2, 0], 0, 1) * 255)

    pen.text((30, 165), f"中点值：sRGB 混合 = {mid_srgb:.0f}", fill=(200, 60, 60), font=FONT_SM)
    pen.text((330, 165), f"中点值：线性混合 = {mid_lin:.0f}", fill=(60, 160, 90), font=FONT_SM)

    # 中点色块
    pen.rectangle([30, 182, 90, 212], fill=(int(mid_srgb),) * 3)
    pen.rectangle([330, 182, 390, 212], fill=(int(mid_lin),) * 3)
    pen.text((100, 188), f"({mid_srgb:.0f},{mid_srgb:.0f},{mid_srgb:.0f})  偏暗",
             fill=(90, 90, 90), font=FONT_SM)
    pen.text((400, 188), f"({mid_lin:.0f},{mid_lin:.0f},{mid_lin:.0f})  物理正确的中点",
             fill=(90, 90, 90), font=FONT_SM)

    # 曲线对比
    pen.text((30, 232), "转换曲线：", fill=(0, 0, 0), font=FONT)
    cx, cy, pw, ph = 100, 240, 200, 60
    dpanel = Image.fromarray(np.full((ph, pw, 3), 250, dtype=np.uint8))
    dpen = ImageDraw.Draw(dpanel)
    xs = np.linspace(0, 1, pw)
    ys_lin = _srgb_to_linear(xs)
    for i in range(pw - 1):
        x0 = i
        y0 = int(ph - 3 - xs[i] * (ph - 8))
        x1 = i + 1
        y1 = int(ph - 3 - xs[i + 1] * (ph - 8))
        dpen.line([x0, y0, x1, y1], fill=(150, 150, 150))     # 恒等（sRGB 直接混合）
        y2 = int(ph - 3 - ys_lin[i] * (ph - 8))
        y3 = int(ph - 3 - ys_lin[i + 1] * (ph - 8))
        dpen.line([x0, y2, x1, y3], fill=(60, 110, 210))      # sRGB→linear
    img.paste(dpanel, (cx, cy))
    pen.text((cx + pw + 8, cy + 6), "灰 = 恒等（直接混）", fill=(120, 120, 120), font=FONT_SM)
    pen.text((cx + pw + 8, cy + 22), "蓝 = sRGB→线性", fill=(60, 110, 210), font=FONT_SM)
    pen.text((cx + pw + 8, cy + 38), "线性值更低 →", fill=(90, 90, 90), font=FONT_SM)
    pen.text((cx + pw + 8, cy + 52), "直接混会偏暗", fill=(90, 90, 90), font=FONT_SM)

    pen.text((16, 308), "⚠ 影响范围：alpha 合成、模糊、缩放插值、渐变 —— "
                        "凡是『求平均』的操作都该在线性空间做",
             fill=(200, 60, 60), font=FONT_SM)

    img.save(OUT_DIR / "srgb_vs_linear.png")
    return mid_srgb, mid_lin


# ---------- main ----------

def main() -> None:
    print("=== 知识点 3：深度与遮挡 ===")
    n_wrong, n_both = render_painters_vs_zbuffer()
    print("画家算法 vs z-buffer -> painters_vs_zbuffer.png")
    print("  -> 两根长条的 z 沿 x 线性变化：交叉点左侧蓝在前、右侧橙在前")
    print("  -> 画家算法：整层只有一个 z（平均 0.5，平手）→ 一半区域画错")
    print(f"  -> 画错像素：{n_wrong:,} / 重叠区 {n_both:,} "
          f"= {100.0 * n_wrong / max(1, n_both):.1f}%")
    print("  -> z-buffer：逐像素比较 → 两侧都正确")
    print()

    render_zfighting()
    print(f"z-fighting -> zfighting/ （{TOTAL} 帧）")
    print("  -> 两个平面 z ≈ 0.5，深度缓冲 8 bit（256 级）")
    print("  -> 微小扰动使比较结果在不同像素上翻转 → 斑块闪烁")
    print("  -> 规避：拉开 z 间距 / 提高深度位数 / 用定点深度")
    print()

    print("=== 知识点 4：颜色还原与语义标签 ===")
    n_hit, n_loose = render_extreme_color_tag()
    print("极端颜色标签 -> extreme_color_tag.png")
    print("  -> 标记：目标区域填纯红 (255,0,0)")
    print("  -> 判定：mask = (R>=250)&(G<=5)&(B<=5)")
    print(f"  -> 命中 {n_hit:,} 像素，零误判（自然画面里不会出现 R满 G=B=0）")
    print(f"  -> 反例：阈值放宽到 (R>150)&(G<80)&(B<80) → 多命中 {n_loose - n_hit:,} 像素（误伤）")
    print("  -> 结论：有效性来自『机器可判定』，不是『颜色好看』")
    print()

    mid_s, mid_l = render_srgb_vs_linear()
    print("sRGB vs 线性 -> srgb_vs_linear.png")
    print(f"  -> 黑白 50/50 混合：sRGB 直接混 = {mid_s:.0f}，线性混合 = {mid_l:.0f}")
    print(f"  -> 差 {mid_l - mid_s:.0f} 个灰阶 —— 直接混会明显偏暗")
    print("  -> 转换：linear = ((c+0.055)/1.055)^2.4   （c > 0.04045）")
    print("  -> 反转换：sRGB = 1.055 * c^(1/2.4) - 0.055 （c > 0.0031308）")
    print()


if __name__ == "__main__":
    main()
