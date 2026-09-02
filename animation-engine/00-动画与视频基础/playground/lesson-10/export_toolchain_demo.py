r"""课 10 实操：动手导出与工具链

真跑一遍完整导出链路：Pillow/NumPy 生成帧序列 → ffmpeg 编 MP4/GIF → ffprobe 验收。

    frames/                 48 张零补位 PNG 帧序列（frame_0000.png …）
    output.mp4              ffmpeg 编码的 H.264 MP4
    output.gif              ffmpeg 两遍调色板编码的 GIF
    naming_zeropad.png      序列帧命名坑：不补零 → 字典序错乱
    gif_transparency.png    透明 GIF 的局限：只有 1-bit 透明
    pipeline_report.png     完整流水线 + 实际命令 + ffprobe 验收结果

运行方式（PowerShell，先切到课程目录）：
    .\playground\.venv\Scripts\python.exe .\playground\lesson-10\export_toolchain_demo.py

依赖：numpy、pillow（已装）；ffmpeg/ffprobe 由 static-ffmpeg 提供（首次运行会下载）
"""

import contextlib
import os
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Windows 控制台默认用 GBK 输出，中文会变乱码；强制 stdout 用 UTF-8
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


@contextlib.contextmanager
def _quiet_stderr():
    """吞掉 stderr 的 fd 2 级别重定向

    static_ffmpeg 在 Windows 中文环境下用 subprocess + text=True（不指定 encoding），
    读 ffmpeg 输出时撞 GBK 会在后台 _readerthread 抛 UnicodeDecodeError。
    路径获取是成功的，只是异常堆栈很吵。把 stderr 临时重定向到 devnull 就安静了。
    """
    devnull = os.open(os.devnull, os.O_WRONLY)
    saved = os.dup(2)
    try:
        os.dup2(devnull, 2)
        yield
    finally:
        os.dup2(saved, 2)
        os.close(devnull)
        os.close(saved)

OUT_DIR = Path(__file__).parent
FRAMES_DIR = OUT_DIR / "frames"

TOTAL_FRAMES = 48
FPS = 24
GIF_FPS = 12
W, H = 320, 240


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
    for p in candidates:
        if Path(p).exists():
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                continue
    return ImageFont.load_default()


FONT = _load_cn_font(10)
FONT_SM = _load_cn_font(9)


# ---------- 工具发现 ----------

def find_tools():
    """定位 ffmpeg / ffprobe，按「噪音从小到大」的顺序尝试

    ① 直接 glob static_ffmpeg/bin 下已下载的二进制
       —— 刻意不走它的 Python API：那个 API 每次都会起 subprocess 做版本检查，
          而它在 Windows 中文环境下用 GBK 解码 ffmpeg 输出，会在后台 reader 线程
          抛 UnicodeDecodeError，堆栈很吵（不影响功能，但看着像出错了）
    ② 没找到才触发它的下载（此时用 _quiet_stderr 尽量吞掉噪音）
    ③ 最后退回 imageio-ffmpeg（只有 ffmpeg，没有 ffprobe）
    """
    ff = fp = None

    # ① 直接定位已下载的二进制
    try:
        import static_ffmpeg
        base = Path(static_ffmpeg.__file__).parent / "bin"
        ffs = sorted(base.rglob("ffmpeg.exe"))
        fps = sorted(base.rglob("ffprobe.exe"))
        if ffs:
            ff = str(ffs[0])
        if fps:
            fp = str(fps[0])
    except Exception:
        pass

    # ② 触发下载（仅首次运行会走到这里）
    if not ff:
        try:
            from static_ffmpeg import run
            with _quiet_stderr():
                ff, fp = run.get_or_fetch_platform_executables_else_raise()
        except Exception:
            pass

    # ③ 退回 imageio-ffmpeg
    if not ff:
        try:
            import imageio_ffmpeg
            ff = imageio_ffmpeg.get_ffmpeg_exe()
        except Exception:
            pass

    return ff, fp


def run_cmd(cmd, label=""):
    """跑一条命令，返回 (rc, stdout, stderr)

    注意：显式指定 encoding/errors，避开 Windows GBK 解码崩溃
    （static_ffmpeg 内部就是没指定，才会在后台线程抛 UnicodeDecodeError）
    """
    r = subprocess.run(cmd, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    if label:
        print(f"  $ {label}")
        print(f"    rc = {r.returncode}")
    return r.returncode, r.stdout, r.stderr


# ---------- 知识点 1：生成帧序列 + ffmpeg 编码 ----------

def generate_frames() -> None:
    """用 Pillow/NumPy 生成 48 张零补位 PNG 帧"""
    if FRAMES_DIR.exists():
        shutil.rmtree(FRAMES_DIR)
    FRAMES_DIR.mkdir(parents=True)

    for i in range(TOTAL_FRAMES):
        t = i / TOTAL_FRAMES
        img = Image.new("RGB", (W, H), (245, 248, 252))
        d = ImageDraw.Draw(img)

        # 背景：静止元素（帧间压缩的"好朋友"）
        d.rectangle([0, int(H * 0.75), W, H], fill=(120, 170, 110))
        d.ellipse([20, 30, 90, 95], fill=(150, 160, 200))

        # 运动元素：一个横向平移的圆
        cx = int(40 + (W - 80) * t)
        cy = int(H * 0.45 + 18 * np.sin(t * 2 * np.pi))
        d.ellipse([cx - 26, cy - 26, cx + 26, cy + 26], fill=(220, 80, 60))

        # 帧号（便于肉眼验证顺序）
        d.text((8, H - 18), f"f{i:03d}", fill=(40, 40, 40))

        # ⚠ 关键：%04d 零补位命名
        img.save(FRAMES_DIR / f"frame_{i:04d}.png")


def render_naming_zeropad() -> None:
    """序列帧命名坑：不补零 → 字典序错乱"""
    cw, ch = 620, 330
    img = Image.fromarray(np.full((ch, cw, 3), 255, dtype=np.uint8))
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "序列帧命名坑：不补零 → ffmpeg 按字典序读取 → 顺序错乱",
             fill=(0, 0, 0), font=FONT)
    pen.text((16, 26), "这是新手导出视频时最常见、也最难察觉的一个 bug",
             fill=(80, 80, 80), font=FONT_SM)

    # 不补零的排序结果
    bad = [f"frame_{i}.png" for i in range(1, 13)]
    bad_sorted = sorted(bad)          # 字典序
    good = [f"frame_{i:04d}.png" for i in range(1, 13)]
    good_sorted = sorted(good)

    pen.text((16, 56), "❌ 不补零  frame_%d.png   →  字典序排序结果：",
             fill=(200, 60, 60), font=FONT)
    for i, name in enumerate(bad_sorted[:12]):
        col, row = i % 3, i // 3
        x = 24 + col * 190
        y = 76 + row * 20
        pen.text((x, y), name, fill=(90, 90, 90), font=FONT_SM)

    pen.text((16, 176), "✅ 补零 4 位  frame_%04d.png   →  字典序排序结果：",
             fill=(60, 160, 90), font=FONT)
    for i, name in enumerate(good_sorted[:12]):
        col, row = i % 3, i // 3
        x = 24 + col * 190
        y = 196 + row * 20
        pen.text((x, y), name, fill=(90, 90, 90), font=FONT_SM)

    pen.text((16, 288), "看出问题了吗：不补零时 frame_10.png 排在 frame_2.png 前面 —— "
                        "视频会「跳帧」",
             fill=(200, 60, 60), font=FONT_SM)
    pen.text((16, 304), "💡 规则：位数必须覆盖最大帧号。1000 帧用 %04d，"
                        "100 帧用 %03d 就够",
             fill=(60, 90, 200), font=FONT_SM)

    img.save(OUT_DIR / "naming_zeropad.png")


def encode_mp4(ff: str) -> Path:
    """帧序列 → H.264 MP4"""
    out = OUT_DIR / "output.mp4"
    if out.exists():
        out.unlink()

    cmd = [
        ff, "-y",
        "-framerate", str(FPS),
        "-i", str(FRAMES_DIR / "frame_%04d.png"),
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        "-crf", "23",
        "-movflags", "+faststart",
        str(out),
    ]
    print("  [MP4] 帧序列 → H.264 MP4")
    print(f"    $ ffmpeg -y -framerate {FPS} -i frames/frame_%04d.png "
          f"-c:v libx264 -pix_fmt yuv420p -crf 23 -movflags +faststart output.mp4")
    rc, _, err = run_cmd(cmd)
    if rc != 0:
        print(f"    FAILED rc={rc}")
        print(err[-800:])
        return None
    print(f"    -> {out.name}  {out.stat().st_size:,} B")
    return out


# ---------- 知识点 2：GIF 与透明 ----------

def encode_gif(ff: str) -> Path:
    """帧序列 → GIF（两遍法：先生成调色板，再应用）"""
    out = OUT_DIR / "output.gif"
    if out.exists():
        out.unlink()

    # 两遍法：palettegen 生成最优 256 色调色板，paletteuse 应用
    fc = ("[0:v] split [a][b];"
          "[a] palettegen=max_colors=256 [p];"
          "[b][p] paletteuse=dither=bayer")
    cmd = [
        ff, "-y",
        "-framerate", str(GIF_FPS),
        "-i", str(FRAMES_DIR / "frame_%04d.png"),
        "-filter_complex", fc,
        "-loop", "0",
        str(out),
    ]
    print("  [GIF] 帧序列 → GIF（两遍法 palettegen + paletteuse）")
    print(f"    $ ffmpeg -y -framerate {GIF_FPS} -i frames/frame_%04d.png "
          f"-filter_complex \"...palettegen...paletteuse...\" -loop 0 output.gif")
    rc, _, err = run_cmd(cmd)
    if rc != 0:
        print(f"    FAILED rc={rc}")
        print(err[-800:])
        return None
    print(f"    -> {out.name}  {out.stat().st_size:,} B")
    return out


def render_gif_transparency() -> None:
    """透明 GIF 的局限：只有 1-bit 透明，没有半透明"""
    size = 130

    # 造一个软边（抗锯齿）红圆，背景全透明
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    dist = np.sqrt((yy - size / 2 + 0.5) ** 2 + (xx - size / 2 + 0.5) ** 2)
    radius = size // 2 - 12
    alpha01 = np.clip(1.0 - (dist - radius) / 6.0, 0.0, 1.0)   # 6px 软边

    rgba = np.zeros((size, size, 4), dtype=np.uint8)
    rgba[:, :, 0] = 220
    rgba[:, :, 1] = 40
    rgba[:, :, 2] = 40
    rgba[:, :, 3] = (alpha01 * 255).astype(np.uint8)
    src = Image.fromarray(rgba)

    # PNG：完整 alpha（半透明保留）
    png_path = OUT_DIR / "_tmp_alpha.png"
    src.save(png_path)

    # GIF：只有 1-bit 透明（半透明像素被迫二选一）
    gif_path = OUT_DIR / "_tmp_alpha.gif"
    src.convert("RGBA").save(gif_path, transparency=0, dispose=2)
    gif_img = Image.open(gif_path).convert("RGBA")

    # 合成到棋盘底上对比
    def on_board(im):
        board = Image.new("RGB", (size, size), (235, 235, 235))
        for y in range(0, size, 8):
            for x in range(0, size, 8):
                if (x // 8 + y // 8) % 2 == 0:
                    ImageDraw.Draw(board).rectangle(
                        [x, y, x + 7, y + 7], fill=(210, 210, 210))
        board.paste(im, (0, 0), im)
        return board

    png_board = on_board(src)
    gif_board = on_board(gif_img)

    # 统计半透明像素数（证明确实丢了）
    n_semi_png = int(((alpha01 > 0.02) & (alpha01 < 0.98)).sum())
    gif_a = np.array(gif_img)[:, :, 3]
    n_semi_gif = int(((gif_a > 5) & (gif_a < 250)).sum())

    cw, ch = 620, 320
    img = Image.fromarray(np.full((ch, cw, 3), 255, dtype=np.uint8))
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "透明 GIF 的局限：只有 1-bit 透明，没有半透明",
             fill=(0, 0, 0), font=FONT)
    pen.text((16, 26), "GIF 的透明通道只有「全透 / 不透」两种状态 —— "
                       "抗锯齿的软边会被迫二选一", fill=(80, 80, 80), font=FONT_SM)

    img.paste(png_board, (30, 50))
    pen.rectangle([30, 50, 30 + size, 50 + size], outline=(100, 100, 100))
    pen.text((30, 190), "✅ PNG：完整 alpha（0~255）", fill=(60, 160, 90), font=FONT)
    pen.text((30, 206), f"   半透明像素 {n_semi_png:,} 个 → 边缘平滑",
             fill=(90, 90, 90), font=FONT_SM)

    img.paste(gif_board, (330, 50))
    pen.rectangle([330, 50, 330 + size, 50 + size], outline=(100, 100, 100))
    pen.text((330, 190), "❌ GIF：只有 1-bit 透明", fill=(200, 60, 60), font=FONT)
    pen.text((330, 206), f"   半透明像素 {n_semi_gif:,} 个 → 软边丢失",
             fill=(90, 90, 90), font=FONT_SM)

    pen.text((16, 240), "后果：", fill=(0, 0, 0), font=FONT)
    pen.text((28, 258), "• 抗锯齿边缘变成硬边（锯齿/白边）", fill=(200, 60, 60), font=FONT_SM)
    pen.text((28, 274), "• 阴影、发光、羽化等半透明效果无法保留", fill=(200, 60, 60), font=FONT_SM)

    pen.text((16, 300), "💡 需要真 alpha 的视频：用 WebM/VP9（APNG 也行），"
                        "不要用 GIF", fill=(60, 90, 200), font=FONT_SM)

    img.save(OUT_DIR / "gif_transparency.png")

    # 清理临时文件
    for p in (png_path, gif_path):
        try:
            p.unlink()
        except Exception:
            pass

    return n_semi_png, n_semi_gif


# ---------- 知识点 3：ffprobe 验收 ----------

def probe_video(fp: str, path: Path) -> dict:
    """用 ffprobe 读取视频的真实参数"""
    cmd = [
        fp, "-v", "error",
        "-select_streams", "v:0",
        "-count_frames",
        "-show_entries",
        "stream=width,height,r_frame_rate,nb_read_frames,codec_name,pix_fmt",
        "-show_entries", "format=duration,size,bit_rate",
        "-of", "default=noprint_wrappers=1",
        str(path),
    ]
    rc, out, err = run_cmd(cmd)
    if rc != 0:
        print(f"    ffprobe FAILED: {err[-400:]}")
        return {}

    info = {}
    for line in out.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            info[k.strip()] = v.strip()
    return info


def render_pipeline_report(mp4: Path, gif: Path, info: dict) -> None:
    """完整流水线 + 实际命令 + 验收结果"""
    cw, ch = 640, 460
    img = Image.fromarray(np.full((ch, cw, 3), 255, dtype=np.uint8))
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "导出流水线与 ffprobe 验收", fill=(0, 0, 0), font=FONT)
    pen.text((16, 26), "导出不是「跑完命令就完事」——必须用 ffprobe 核对结果是否符合预期",
             fill=(80, 80, 80), font=FONT_SM)

    # 流水线
    pen.text((16, 54), "① 流水线：", fill=(0, 0, 0), font=FONT)
    steps = [
        "Pillow/NumPy 生成帧序列（零补位命名）",
        "ffmpeg -framerate 24 -i frame_%04d.png",
        "ffmpeg -c:v libx264 -pix_fmt yuv420p -crf 23",
        "ffprobe 验收（帧率 / 帧数 / 分辨率 / 时长）",
    ]
    for i, s in enumerate(steps):
        pen.text((28, 74 + i * 18), f"{i+1}. {s}", fill=(60, 60, 60), font=FONT_SM)

    # 产物
    pen.text((16, 160), "② 产物：", fill=(0, 0, 0), font=FONT)
    y = 180
    if mp4 and mp4.exists():
        pen.text((28, y), f"output.mp4   {mp4.stat().st_size:,} B",
                 fill=(0, 0, 0), font=FONT_SM)
        y += 18
    if gif and gif.exists():
        pen.text((28, y), f"output.gif   {gif.stat().st_size:,} B",
                 fill=(0, 0, 0), font=FONT_SM)
        y += 18

    # ffprobe 结果
    pen.text((16, y + 12), "③ ffprobe 实测输出：", fill=(0, 0, 0), font=FONT)
    y2 = y + 32

    if info:
        checks = [
            ("分辨率", f"{info.get('width','?')} × {info.get('height','?')}",
             (f"{info.get('width','?')}" == str(W) and f"{info.get('height','?')}" == str(H))),
            ("帧率", info.get("r_frame_rate", "?"), None),
            ("帧数", info.get("nb_read_frames", "?"),
             info.get("nb_read_frames") == str(TOTAL_FRAMES)),
            ("编码", info.get("codec_name", "?"), None),
            ("像素格式", info.get("pix_fmt", "?"), None),
            ("时长(s)", info.get("duration", "?"), None),
            ("码率(bps)", info.get("bit_rate", "?"), None),
        ]
        for i, (k, v, ok) in enumerate(checks):
            yy = y2 + i * 19
            color = (0, 0, 0)
            mark = ""
            if ok is True:
                color = (60, 160, 90)
                mark = "  ✓"
            elif ok is False:
                color = (200, 60, 60)
                mark = "  ✗"
            pen.text((28, yy), f"{k:<10} {v}{mark}", fill=color, font=FONT_SM)
    else:
        pen.text((28, y2), "(ffprobe 不可用)", fill=(200, 60, 60), font=FONT_SM)

    # 验收要点（与 ③ 留出 20px 间距）
    pen.text((16, 402), "④ 验收要点：", fill=(0, 0, 0), font=FONT)
    pen.text((28, 420), "• 帧数 = 时长 × 帧率（对不上就是丢帧/补帧）",
             fill=(90, 90, 90), font=FONT_SM)
    pen.text((28, 436), "• 分辨率与源一致；pix_fmt 必须是 yuv420p（否则 QuickTime 打不开）",
             fill=(90, 90, 90), font=FONT_SM)
    pen.text((28, 452), "• -movflags +faststart：把 moov 头前移，网页才能边下边播",
             fill=(90, 90, 90), font=FONT_SM)

    img.save(OUT_DIR / "pipeline_report.png")


# ---------- main ----------

def main() -> None:
    print("=== 工具发现 ===")
    ff, fp = find_tools()
    print(f"  ffmpeg  : {ff or '(未找到)'}")
    print(f"  ffprobe : {fp or '(未找到)'}")
    if not ff:
        print()
        print("  ⚠ 未找到 ffmpeg。请先安装（任选一种）：")
        print("     uv pip install static-ffmpeg      # 本脚本所用，自带 ffmpeg+ffprobe")
        print("     winget install Gyan.FFmpeg        # 系统级安装")
        print("  帧序列生成部分仍会执行，但编码/验收会跳过。")
    print()

    print("=== 知识点 1：命令行导出工具链 ===")
    generate_frames()
    n_png = len(list(FRAMES_DIR.glob("frame_*.png")))
    print(f"帧序列 -> frames/ （{n_png} 张，frame_%04d.png 零补位）")
    print(f"  -> Pillow/NumPy 生成 {TOTAL_FRAMES} 帧 {W}×{H}")
    print("  ⚠ 零补位是硬要求：frame_%d.png 会让 frame_10 排在 frame_2 前面")
    print()

    render_naming_zeropad()
    print("命名坑 -> naming_zeropad.png")
    print("  -> 不补零：frame_10.png 排在 frame_2.png 前 → 视频跳帧")
    print("  -> 补零 4 位：frame_0002 / frame_0010 → 字典序 = 正确顺序")
    print()

    mp4 = encode_mp4(ff) if ff else None
    print()

    print("=== 知识点 2：GIF、透明与常见坑 ===")
    gif = encode_gif(ff) if ff else None
    print("  -> 两遍法：palettegen 先算出最优 256 色调色板，paletteuse 再套用")
    print("  -> 比直接 -i 转 GIF 质量高得多（后者用默认调色板，色带严重）")
    print()

    n_png_semi, n_gif_semi = render_gif_transparency()
    print("透明 GIF -> gif_transparency.png")
    print(f"  -> PNG 半透明像素 {n_png_semi:,} 个（软边完整）")
    print(f"  -> GIF 半透明像素 {n_gif_semi:,} 个（被迫二选一，软边丢失）")
    print("  -> GIF 透明通道只有 1-bit：全透 / 不透，没有中间态")
    print()

    print("=== 知识点 3：输出验收 ===")
    info = {}
    if fp and mp4 and mp4.exists():
        print("  $ ffprobe -v error -select_streams v:0 -count_frames "
              "-show_entries stream=... -show_entries format=... output.mp4")
        info = probe_video(fp, mp4)
        for k in ("width", "height", "r_frame_rate", "nb_read_frames",
                  "codec_name", "pix_fmt", "duration", "bit_rate"):
            if k in info:
                print(f"    {k:<16} = {info[k]}")
        # 校验
        print()
        exp_frames = TOTAL_FRAMES
        got_frames = info.get("nb_read_frames", "")
        ok_f = (got_frames == str(exp_frames))
        print(f"  帧数校验：期望 {exp_frames}，实测 {got_frames}  "
              f"{'✓' if ok_f else '✗'}")
        ok_wh = (info.get("width") == str(W) and info.get("height") == str(H))
        print(f"  分辨率校验：期望 {W}×{H}，实测 {info.get('width')}×{info.get('height')}  "
              f"{'✓' if ok_wh else '✗'}")
    elif not fp:
        print("  ⚠ 无 ffprobe，跳过验收。安装：uv pip install static-ffmpeg")
    print()

    render_pipeline_report(mp4, gif, info)
    print("流水线与验收 -> pipeline_report.png")
    print()
    print("  关键参数说明：")
    print("    -framerate 24    输入帧率（先于 -i，表示按 24fps 读图）")
    print("    -c:v libx264     H.264 编码")
    print("    -pix_fmt yuv420p 兼容性最好的像素格式（QuickTime/网页必需）")
    print("    -crf 23          恒定质量，18~28 常用，越小质量越高体积越大")
    print("    -movflags +faststart  moov 头前移，支持边下边播")
    print("    -loop 0          GIF 无限循环（0 = 永远）")
    print()


if __name__ == "__main__":
    main()
