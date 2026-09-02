r"""课 9 实操：视频参数与压缩原理

把"文件变大由什么决定"和"为什么闪烁压不动"两件事跑出来，生成四组产物：

    params_calculator.png       四个基本参数的计算（分辨率/帧率/码率/GOP）
    quality_vs_size/            24 帧，JPEG quality 递增 → 画质与体积的权衡
    gif_palette.png             GIF 的 256 色限制：原始 / 无抖动 / 有抖动
    temporal_difference/        24 帧，稳定画面 vs 闪烁画面的帧差对比

运行方式（PowerShell，先切到课程目录）：
    .\playground\.venv\Scripts\python.exe .\playground\lesson-09\video_params_demo.py

依赖：numpy、pillow（已装在 playground/.venv）
"""

import io
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


# ---------- 知识点 1：四个基本参数 ----------

def render_params_calculator() -> None:
    """四个基本参数：分辨率 / 帧率 / 码率 / GOP —— 它们如何决定文件体积"""
    W, H = 1920, 1080
    fps = 24
    seconds = 10
    total_frames = fps * seconds
    bytes_per_frame = W * H * 4                 # RGBA 未压缩
    raw_bytes = bytes_per_frame * total_frames

    # 目标码率与压缩比
    bitrate_mbps = 5.0
    file_bytes = bitrate_mbps * 1_000_000 * seconds / 8
    ratio = raw_bytes / file_bytes

    cw, ch = 660, 460
    img = Image.fromarray(np.full((ch, cw, 3), 255, dtype=np.uint8))
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "四个基本参数：分辨率 × 帧率 × 码率，加上 GOP", fill=(0, 0, 0), font=FONT)
    pen.text((16, 26), "前三个是「三角关系」——给定码率预算，提高一项必然挤压另一项",
             fill=(80, 80, 80), font=FONT_SM)

    # ---- 左侧：参数与计算 ----
    y = 54
    pen.text((16, y), "① 原始数据量（未压缩）", fill=(0, 0, 0), font=FONT)
    rows = [
        ("分辨率", f"{W} × {H}"),
        ("每帧字节数", f"{W} × {H} × 4 = {bytes_per_frame:,} B"),
        ("帧率", f"{fps} fps"),
        ("时长", f"{seconds} s"),
        ("总帧数", f"{fps} × {seconds} = {total_frames} 帧"),
        ("原始数据", f"{bytes_per_frame:,} × {total_frames} = {raw_bytes:,} B"),
    ]
    for i, (k, v) in enumerate(rows):
        yy = y + 18 + i * 16
        pen.text((28, yy), k, fill=(60, 60, 60), font=FONT_SM)
        pen.text((120, yy), v, fill=(0, 0, 0), font=FONT_SM)

    gb = raw_bytes / 1024 ** 3
    pen.text((28, y + 18 + 6 * 16 + 6), f"≈ {gb:.2f} GB（未压缩，全在硬盘/内存里）",
             fill=(200, 60, 60), font=FONT_SM)

    # ---- 右侧：码率与压缩比 ----
    y2 = 54
    pen.text((360, y2), "② 码率：给体积定预算", fill=(0, 0, 0), font=FONT)
    rows2 = [
        ("目标码率", f"{bitrate_mbps} Mbps"),
        ("文件大小", f"{bitrate_mbps} Mbps × {seconds} s ÷ 8"),
        ("", f"= {file_bytes:,.0f} B ≈ {file_bytes/1024/1024:.1f} MB"),
        ("压缩比", f"{gb:.2f} GB ÷ {file_bytes/1024/1024:.1f} MB"),
        ("", f"≈ {ratio:.0f} ×"),
    ]
    for i, (k, v) in enumerate(rows2):
        yy = y2 + 18 + i * 16
        pen.text((372, yy), k, fill=(60, 60, 60), font=FONT_SM)
        pen.text((460, yy), v, fill=(0, 0, 0), font=FONT_SM)

    pen.text((360, y2 + 18 + 5 * 16 + 8), "视频编码的绝大部分工作，"
                                          "就是在不明显损失观感的前提下做到这个压缩比",
             fill=(90, 90, 90), font=FONT_SM)

    # ---- 三角关系示意 ----
    y3 = 200
    pen.text((16, y3), "③ 三角关系：给定码率预算，三者互相挤压", fill=(0, 0, 0), font=FONT)
    tri = [
        ("↑ 分辨率", "画面更清晰，但每帧数据更多 → 码率不够就糊"),
        ("↑ 帧率", "动作更顺滑，但帧数更多 → 码率不够就卡/糊"),
        ("↑ 码率", "画质更好，但文件更大 → 带宽/存储成本"),
    ]
    for i, (t, d) in enumerate(tri):
        yy = y3 + 18 + i * 26
        pen.text((28, yy), t, fill=(40, 90, 200), font=FONT_SM)
        pen.text((100, yy), f"→ {d}", fill=(90, 90, 90), font=FONT_SM)

    # ---- GOP 示意 ----
    y4 = 310
    pen.text((16, y4), "④ GOP（Group of Pictures）：两个 I 帧之间的间隔", fill=(0, 0, 0), font=FONT)
    pen.text((16, y4 + 16), "I 帧 = 完整图像（可独立解码）；P/B 帧 = 只存与参考帧的差异",
             fill=(90, 90, 90), font=FONT_SM)

    gop = 12
    n_show = 26
    cell = 22
    x0 = 28
    yy = y4 + 34
    for i in range(n_show):
        is_i = (i % gop == 0)
        x = x0 + i * cell
        if is_i:
            pen.rectangle([x, yy, x + cell - 3, yy + 26], fill=(200, 60, 60))
            pen.text((x + 4, yy + 6), "I", fill=(255, 255, 255), font=FONT_SM)
        else:
            kind = "P" if (i % 3 != 0) else "B"
            pen.rectangle([x, yy, x + cell - 3, yy + 26],
                          fill=(230, 230, 230), outline=(150, 150, 150))
            pen.text((x + 5, yy + 6), kind, fill=(90, 90, 90), font=FONT_SM)
    # 标注 GOP 边界
    pen.line([x0, yy + 30, x0 + gop * cell - 3, yy + 30], fill=(200, 60, 60), width=1)
    pen.text((x0 + 20, yy + 34), f"← 一个 GOP = {gop} 帧 →", fill=(200, 60, 60), font=FONT_SM)

    # GOP 权衡
    pen.text((16, y4 + 96), "GOP 权衡：", fill=(0, 0, 0), font=FONT_SM)
    pen.text((28, y4 + 112), "GOP 大 → I 帧少 → 体积小、压缩率高，但拖拽定位慢"
                             "（要往前找到最近的 I 帧）",
             fill=(90, 90, 90), font=FONT_SM)
    pen.text((28, y4 + 128), "GOP 小 → I 帧多 → 体积大、压缩率低，但拖拽定位快、容错好",
             fill=(90, 90, 90), font=FONT_SM)

    img.save(OUT_DIR / "params_calculator.png")
    return total_frames, raw_bytes, file_bytes, ratio


def render_quality_vs_size() -> None:
    """24 帧：JPEG quality 递增 → 画质与体积的权衡（码率-画质关系的直观类比）"""
    out_dir = OUT_DIR / "quality_vs_size"
    out_dir.mkdir(parents=True, exist_ok=True)

    # 造一张有细节的测试图（渐变 + 几何 + 文字），压缩损失才看得出来
    W, H = 240, 180
    src = Image.new("RGB", (W, H), (250, 250, 252))
    d = ImageDraw.Draw(src)
    for i in range(W):                      # 横向彩色渐变（对压缩敏感）
        d.line([i, 0, i, H], fill=(int(255 * i / W), 120, int(255 * (1 - i / W))))
    d.ellipse([30, 30, 110, 110], fill=(250, 220, 80))
    d.rectangle([130, 40, 210, 120], fill=(60, 140, 200))
    d.ellipse([80, 90, 170, 160], fill=(220, 70, 70))
    d.text((20, 160), "detail", fill=(30, 30, 30))

    # 先算一遍所有档位的体积，用于统一归一化显示
    sizes = []
    for f in range(TOTAL):
        q = int(round(5 + (95 - 5) * f / (TOTAL - 1)))
        buf = io.BytesIO()
        src.save(buf, format="JPEG", quality=q)
        sizes.append(len(buf.getvalue()))
    max_size = max(sizes)
    min_size = min(sizes)

    for f in range(TOTAL):
        q = int(round(5 + (95 - 5) * f / (TOTAL - 1)))
        buf = io.BytesIO()
        src.save(buf, format="JPEG", quality=q)
        buf.seek(0)
        jpg = Image.open(buf).convert("RGB")
        size = sizes[f]

        cw, ch = 580, 300
        img = Image.fromarray(np.full((ch, cw, 3), 255, dtype=np.uint8))
        pen = ImageDraw.Draw(img)

        pen.text((16, 8), f"f{f:03d}   JPEG quality = {q}   →   "
                          f"体积 = {size:,} B（{size/1024:.1f} KB）",
                 fill=(0, 0, 0), font=FONT)
        pen.text((16, 24), "JPEG quality 是「码率-画质」权衡的直观类比："
                           "质量档位越高，体积越大", fill=(80, 80, 80), font=FONT_SM)

        img.paste(jpg, (16, 46))
        pen.rectangle([16, 46, 16 + W, 46 + H], outline=(100, 100, 100))

        # 右侧：体积条
        pen.text((290, 46), "体积对比：", fill=(0, 0, 0), font=FONT)
        bar_x, bar_w = 300, 240
        frac = (size - min_size) / max(1, (max_size - min_size))
        pen.rectangle([bar_x, 66, bar_x + bar_w, 84], fill=(230, 230, 230))
        pen.rectangle([bar_x, 66, bar_x + int(bar_w * frac), 84], fill=(220, 80, 60))
        pen.text((bar_x, 90), f"{size:,} B", fill=(0, 0, 0), font=FONT_SM)
        pen.text((bar_x, 104), f"最小 {min_size:,} B（q=5）  最大 {max_size:,} B（q=95）",
                 fill=(90, 90, 90), font=FONT_SM)

        pen.text((290, 132), "压缩比：", fill=(0, 0, 0), font=FONT)
        raw_b = W * H * 3
        pen.text((300, 150), f"原始 RGB = {raw_b:,} B", fill=(90, 90, 90), font=FONT_SM)
        pen.text((300, 164), f"压缩后   = {size:,} B", fill=(90, 90, 90), font=FONT_SM)
        pen.text((300, 178), f"压缩比   = {raw_b/size:.1f} ×", fill=(40, 90, 200), font=FONT_SM)

        pen.text((290, 208), "观察点：", fill=(0, 0, 0), font=FONT)
        pen.text((300, 226), "• q 很低时：块状伪影（blocking）", fill=(90, 90, 90), font=FONT_SM)
        pen.text((300, 240), "• 渐变区最易出现色带（banding）", fill=(90, 90, 90), font=FONT_SM)
        pen.text((300, 254), "• 体积增长远快于观感提升", fill=(200, 60, 60), font=FONT_SM)

        pen.text((16, 240), "⚠ 码率同理：过了某个点，"
                            "再加码率观感几乎不变，但体积线性增长",
                 fill=(200, 60, 60), font=FONT_SM)

        img.save(out_dir / f"frame_{f:03d}.png")

    return min_size, max_size


# ---------- 知识点 2：容器与编解码器 ----------

def render_gif_palette() -> None:
    """GIF 的 256 色硬限制：原始渐变 / 无抖动量化 / 有抖动量化"""
    W, H = 200, 140

    # 造一张平滑渐变图（GIF 最怕这个）
    xx = np.linspace(0, 1, W)[None, :, None]
    yy = np.linspace(0, 1, H)[:, None, None]
    grad = np.zeros((H, W, 3), dtype=np.float64)
    grad[:, :, 0] = 0.15 + 0.80 * xx[:, :, 0]        # R 横向渐变
    grad[:, :, 1] = 0.35 + 0.45 * yy[:, :, 0]        # G 纵向渐变
    grad[:, :, 2] = 0.75 - 0.35 * xx[:, :, 0]
    orig = Image.fromarray((np.clip(grad, 0, 1) * 255).astype(np.uint8))

    # 加一个实心图形，便于观察色块
    d = ImageDraw.Draw(orig)
    d.ellipse([60, 30, 150, 110], fill=(240, 200, 60))

    # 量化到 256 色（GIF 的硬限制）
    no_dither = orig.convert("P", palette=Image.ADAPTIVE, colors=256,
                             dither=Image.NONE).convert("RGB")
    dither = orig.convert("P", palette=Image.ADAPTIVE, colors=256,
                          dither=Image.FLOYDSTEINBERG).convert("RGB")

    cw, ch = 660, 360
    img = Image.fromarray(np.full((ch, cw, 3), 255, dtype=np.uint8))
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "容器 ≠ 编解码器：GIF 的 256 色是硬限制", fill=(0, 0, 0), font=FONT)
    pen.text((16, 26), "GIF 最多只能有 256 种颜色 —— 平滑渐变无法表达，"
                       "只能靠「色带」或「抖动」妥协", fill=(80, 80, 80), font=FONT_SM)

    items = [
        (16, "① 原始（约 1600 万色）", orig),
        (230, "② GIF 量化，无抖动", no_dither),
        (444, "③ GIF 量化，有抖动", dither),
    ]
    for x, label, im in items:
        img.paste(im, (x, 50))
        pen.rectangle([x, 50, x + W, 50 + H], outline=(100, 100, 100))
        pen.text((x, 200), label, fill=(0, 0, 0), font=FONT)

    pen.text((16, 222), "观察：", fill=(0, 0, 0), font=FONT)
    pen.text((28, 240), "② 无抖动 → 渐变被切成一条条「色带」（banding），但画面干净",
             fill=(200, 60, 60), font=FONT_SM)
    pen.text((28, 256), "③ 有抖动 → 用噪点打散色带，观感更连续，但引入颗粒感",
             fill=(40, 90, 200), font=FONT_SM)

    pen.text((16, 282), "为什么 GIF 还没被淘汰：", fill=(0, 0, 0), font=FONT)
    pen.text((28, 300), "• 无需播放器，浏览器/微信直接内联播放；"
                        "• 支持简单动画与 1-bit 透明",
             fill=(90, 90, 90), font=FONT_SM)
    pen.text((28, 314), "• 但：256 色上限、无半透明、压缩率远低于 H.264",
             fill=(200, 60, 60), font=FONT_SM)

    pen.text((16, 332), "⚠ 带 alpha 的视频很麻烦：H.264/HEVC 主流配置都不支持 alpha 通道，"
                        "需要 HEVC+alpha 或 WebM/VP9", fill=(200, 60, 60), font=FONT_SM)

    img.save(OUT_DIR / "gif_palette.png")


# ---------- 知识点 3：帧间压缩 ----------

def render_temporal_difference() -> None:
    """24 帧：稳定画面 vs 闪烁画面 → 帧差对比 → 为什么闪烁压不动"""
    out_dir = OUT_DIR / "temporal_difference"
    out_dir.mkdir(parents=True, exist_ok=True)

    W, H = 220, 150
    rng = np.random.default_rng(42)          # 固定种子，结果可复现

    prev_stable = None
    prev_flick = None
    diffs_stable = []
    diffs_flick = []

    for f in range(TOTAL):
        # ---- 稳定序列：平滑移动的圆 + 静止背景 ----
        st = Image.fromarray(np.full((H, W, 3), 245, dtype=np.uint8))
        sd = ImageDraw.Draw(st)
        # 静止背景元素
        sd.rectangle([0, 110, W, H], fill=(120, 170, 110))
        sd.ellipse([10, 20, 60, 60], fill=(150, 150, 190))
        # 平滑移动的圆
        cx = int(30 + (W - 60) * f / (TOTAL - 1))
        sd.ellipse([cx - 22, 60, cx + 22, 104], fill=(220, 80, 60))
        arr_st = np.array(st).astype(np.float64)

        # ---- 闪烁序列：每帧随机噪点（模拟 AI 画面抖动）----
        noise = rng.integers(0, 256, size=(H, W, 3))
        # 让闪烁图"看起来像同一个场景"，但每帧像素都跳变
        base = np.array(st).astype(np.float64)
        fl = np.clip(base * 0.5 + noise * 0.5, 0, 255).astype(np.uint8)
        arr_fl = fl.astype(np.float64)

        # ---- 帧差（与上一帧的平均绝对差）----
        if prev_stable is not None:
            diffs_stable.append(float(np.abs(arr_st - prev_stable).mean()))
            diffs_flick.append(float(np.abs(arr_fl - prev_flick).mean()))
        prev_stable, prev_flick = arr_st, arr_fl

        ds = diffs_stable[-1] if diffs_stable else 0.0
        df = diffs_flick[-1] if diffs_flick else 0.0

        # ---- 画图 ----
        cw, ch = 560, 340
        img = Image.fromarray(np.full((ch, cw, 3), 255, dtype=np.uint8))
        pen = ImageDraw.Draw(img)

        pen.text((16, 8), f"f{f:03d}   帧间压缩：奖励稳定，惩罚闪烁", fill=(0, 0, 0), font=FONT)
        pen.text((16, 24), "上排 = 稳定画面（平滑移动）    下排 = 闪烁画面（每帧像素跳变）",
                 fill=(80, 80, 80), font=FONT_SM)

        img.paste(st, (16, 46))
        pen.rectangle([16, 46, 16 + W, 46 + H], outline=(100, 100, 100))
        img.paste(Image.fromarray(fl), (300, 46))
        pen.rectangle([300, 46, 300 + W, 46 + H], outline=(100, 100, 100))

        pen.text((16, 204), "稳定：帧差小 → 好压缩", fill=(60, 160, 90), font=FONT)
        pen.text((300, 204), "闪烁：帧差大 → 压不动", fill=(200, 60, 60), font=FONT)

        # 帧差数值条
        pen.text((16, 224), f"平均帧差  |Δ| = {ds:6.2f}", fill=(60, 160, 90), font=FONT_SM)
        pen.text((300, 224), f"平均帧差  |Δ| = {df:6.2f}", fill=(200, 60, 60), font=FONT_SM)

        bar_x, bar_w, bar_y = 16, 200, 244
        pen.rectangle([bar_x, bar_y, bar_x + bar_w, bar_y + 12], fill=(230, 240, 230))
        pen.rectangle([bar_x, bar_y, bar_x + int(bar_w * min(1.0, ds / 60.0)), bar_y + 12],
                      fill=(60, 160, 90))
        bar_x2 = 300
        pen.rectangle([bar_x2, bar_y, bar_x2 + bar_w, bar_y + 12], fill=(245, 230, 230))
        pen.rectangle([bar_x2, bar_y, bar_x2 + int(bar_w * min(1.0, df / 60.0)), bar_y + 12],
                      fill=(200, 60, 60))

        # 说明
        pen.text((16, 272), "原理：P/B 帧只存「与参考帧的差异」（运动补偿后的残差）",
                 fill=(90, 90, 90), font=FONT_SM)
        pen.text((16, 288), "稳定画面 → 残差接近 0 → 残差极易压缩 → 压缩率高",
                 fill=(60, 160, 90), font=FONT_SM)
        pen.text((16, 302), "闪烁画面 → 残差≈随机噪点 → 残差压不动 → 压缩率崩掉",
                 fill=(200, 60, 60), font=FONT_SM)

        pen.text((16, 320), "💡 需求文档的「帧间一致性」主张：不只是好看，"
                            "更是压缩率的前提", fill=(40, 90, 200), font=FONT_SM)

        img.save(out_dir / f"frame_{f:03d}.png")

    avg_s = float(np.mean(diffs_stable))
    avg_f = float(np.mean(diffs_flick))
    return avg_s, avg_f


# ---------- main ----------

def main() -> None:
    print("=== 知识点 1：四个基本参数 ===")
    n_frames, raw_b, file_b, ratio = render_params_calculator()
    print("参数计算 -> params_calculator.png")
    gb = raw_b / 1024 ** 3
    print(f"  -> 1920×1080 @ 24fps × 10s = {n_frames} 帧")
    print(f"  -> 原始 RGBA = {raw_b:,} B ≈ {gb:.2f} GB（未压缩）")
    print(f"  -> 目标 5 Mbps → 文件 ≈ {file_b/1024/1024:.1f} MB")
    print(f"  -> 压缩比 ≈ {ratio:.0f} ×  ← 视频编码要做的事")
    print()

    mn, mx = render_quality_vs_size()
    print(f"画质/体积权衡 -> quality_vs_size/ （{TOTAL} 帧，JPEG q=5→95）")
    print(f"  -> 体积从 {mn:,} B（q=5）到 {mx:,} B（q=95），差 {mx/mn:.1f} 倍")
    print("  -> 与码率同理：过了某个点，再加码率观感几乎不变，体积却线性增长")
    print()

    print("=== 知识点 2：容器与编解码器 ===")
    render_gif_palette()
    print("GIF 256 色 -> gif_palette.png")
    print("  -> 容器（.mp4/.gif）≠ 编解码器（H.264/LZW）")
    print("  -> GIF 硬限制：最多 256 色 → 渐变必须靠色带或抖动妥协")
    print("  -> 带 alpha 的视频很麻烦：H.264/HEVC 主流配置不支持 alpha")
    print()

    print("=== 知识点 3：帧间压缩与画面一致性 ===")
    avg_s, avg_f = render_temporal_difference()
    print(f"帧差对比 -> temporal_difference/ （{TOTAL} 帧）")
    print(f"  -> 稳定画面平均帧差 |Δ| = {avg_s:.2f}")
    print(f"  -> 闪烁画面平均帧差 |Δ| = {avg_f:.2f}")
    print(f"  -> 闪烁的帧差是稳定的 {avg_f/max(avg_s, 1e-6):.1f} 倍")
    print()
    print("  -> P/B 帧只存残差：稳定 → 残差≈0 → 好压缩；闪烁 → 残差≈噪点 → 压不动")
    print("  -> 需求文档的「帧间一致性」不只是好看，更是压缩率的前提")
    print()


if __name__ == "__main__":
    main()
