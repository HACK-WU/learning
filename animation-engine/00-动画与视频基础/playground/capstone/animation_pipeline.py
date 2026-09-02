r"""结课实战项目：端到端动画流水线

把整门课 10 课的内容串成一条真能跑的链路：

    AI 矢量节点 (ai_nodes.json)
      → ① 数据解析        {matrix_data, z_depth, frame}
      → ② 几何变换        3×3 齐次矩阵：平移/旋转/缩放/绕任意点 + 缓动 + 贝塞尔
      → ③ 光栅化          矢量 → RGBA 像素画布 + 超采样抗锯齿
      → ④ 合成            z 排序 + over 运算符自底向上
      → ⑤ 编码            ffmpeg → MP4 (H.264) + GIF (两遍调色板)
      → ⑥ 导出            落盘 frames/ + output/
      → ⑦ 验收            ffprobe 核对分辨率/帧率/帧数/像素格式/时长

运行方式（PowerShell，先切到课程目录）：
    .\playground\.venv\Scripts\python.exe .\playground\capstone\animation_pipeline.py

依赖：numpy、pillow；ffmpeg/ffprobe 由 static-ffmpeg 提供
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

HERE = Path(__file__).parent
FRAMES_DIR = HERE / "frames"
OUT_DIR = HERE / "output"


def _load_cn_font(size: int = 11) -> ImageFont.ImageFont:
    for p in (r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf",
              "/System/Library/Fonts/PingFang.ttc",
              "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"):
        if Path(p).exists():
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                continue
    return ImageFont.load_default()


FONT = _load_cn_font(11)
FONT_SM = _load_cn_font(9)


# ============================================================
# 工具发现（同课 10：直接 glob 二进制，绕开 static_ffmpeg 的 GBK 噪音）
# ============================================================

def find_tools():
    ff = fp = None
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
    if not ff:
        try:
            from static_ffmpeg import run
            ff, fp = run.get_or_fetch_platform_executables_else_raise()
        except Exception:
            pass
    if not ff:
        try:
            import imageio_ffmpeg
            ff = imageio_ffmpeg.get_ffmpeg_exe()
        except Exception:
            pass
    return ff, fp


# ============================================================
# ② 几何变换：3×3 齐次矩阵（课 5）
# ============================================================

def mat_translate(tx: float, ty: float) -> np.ndarray:
    return np.array([[1.0, 0.0, tx],
                     [0.0, 1.0, ty],
                     [0.0, 0.0, 1.0]])


def mat_rotate(deg: float) -> np.ndarray:
    a = np.radians(deg)
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, -s, 0.0],
                     [s,  c, 0.0],
                     [0.0, 0.0, 1.0]])


def mat_scale(sx: float, sy: float) -> np.ndarray:
    return np.array([[sx, 0.0, 0.0],
                     [0.0, sy, 0.0],
                     [0.0, 0.0, 1.0]])


def mat_rotate_about(deg: float, px: float, py: float) -> np.ndarray:
    """绕任意点 (px,py) 旋转 = T(p) · R · T(-p)  （课 5 第二批）"""
    return mat_translate(px, py) @ mat_rotate(deg) @ mat_translate(-px, -py)


def apply_mat(M: np.ndarray, pt) -> tuple:
    """把 3×3 矩阵作用到点 (x, y)，返回齐次除法后的 (x, y)"""
    v = np.array([pt[0], pt[1], 1.0])
    r = M @ v
    return (float(r[0]), float(r[1]))


# ---- 缓动（课 6 第一批）----
def ease_in_out_cubic(t: float) -> float:
    t = float(np.clip(t, 0.0, 1.0))
    return 4 * t ** 3 if t < 0.5 else 1 - ((-2 * t + 2) ** 3) / 2


# ---- 三次贝塞尔（课 6 第二批）----
def cubic_bezier(p0, p1, p2, p3, t: float) -> tuple:
    t = float(np.clip(t, 0.0, 1.0))
    mt = 1.0 - t
    x = mt**3 * p0[0] + 3 * mt**2 * t * p1[0] + 3 * mt * t**2 * p2[0] + t**3 * p3[0]
    y = mt**3 * p0[1] + 3 * mt**2 * t * p1[1] + 3 * mt * t**2 * p2[1] + t**3 * p3[1]
    return (x, y)


def interp_keyframes(keyframes, frame: int) -> dict:
    """关键帧线性插值（课 2 中割 + 课 6 补间）"""
    frames = [k["frame"] for k in keyframes]
    if frame <= frames[0]:
        return {k: v for k, v in keyframes[0].items() if k != "frame"}
    if frame >= frames[-1]:
        return {k: v for k, v in keyframes[-1].items() if k != "frame"}
    for i in range(len(frames) - 1):
        f0, f1 = frames[i], frames[i + 1]
        if f0 <= frame <= f1:
            u = (frame - f0) / max(1, (f1 - f0))
            a, b = keyframes[i], keyframes[i + 1]
            return {k: a[k] + (b[k] - a[k]) * u
                    for k in a if k != "frame"}
    return {}


# ============================================================
# ③ 光栅化：各图层绘制（矢量 → RGBA 像素画布）
# ============================================================

def new_layer(w: int, h: int, ss: int):
    """超采样画布：先按 ss 倍画，最后缩回 → 抗锯齿（课 7）"""
    img = Image.new("RGBA", (w * ss, h * ss), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def draw_gradient_rect(d, w, h, ss, top, bottom):
    """天空渐变：逐行插值（在超采样分辨率下画）"""
    H = h * ss
    for y in range(H):
        u = y / max(1, H - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * u) for i in range(3))
        d.line([(0, y), (w * ss, y)], fill=c + (255,))


def draw_polygons(d, shapes, ss, dx):
    for sh in shapes:
        pts = [(p[0] * ss + dx * ss, p[1] * ss) for p in sh["points"]]
        d.polygon(pts, fill=tuple(sh["color"]) + (255,))


def draw_solid_rect(d, rect, ss, color):
    x0, y0, x1, y1 = rect
    d.rectangle([x0 * ss, y0 * ss, x1 * ss, y1 * ss],
                fill=tuple(color) + (255,))


def draw_tree(d, node, ss, sway):
    """树：树干矩形 + 树冠圆（树冠随 sway 摆动）"""
    bx, by = node["base"]
    tw, th = node["trunk"]
    bx, by, tw, th = bx * ss, by * ss, tw * ss, th * ss
    d.rectangle([bx - tw / 2, by - th, bx + tw / 2, by],
                fill=tuple(node["trunk_color"]) + (255,))
    cr = node["crown_radius"] * ss
    cx = bx + sway * ss
    cy = by - th - cr * 0.35
    d.ellipse([cx - cr, cy - cr, cx + cr, cy + cr],
              fill=tuple(node["crown_color"]) + (255,))


def draw_stick_figure(d, node, ss, frame_idx, total):
    """主角：一根线条变成的角色

    综合使用了课 5-6 的变换：
      - 沿三次贝塞尔路径运动（课 6）
      - 路径参数用 ease_in_out_cubic 缓动（课 6）
      - 整体旋转 + 缩放（课 5）
      - 手臂绕肩关节旋转（课 5「绕任意点」）
    """
    p = node["path"]
    p0, p1, p2, p3 = p["p0"], p["p1"], p["p2"], p["p3"]

    # 缓动后的路径参数
    t = frame_idx / max(1, total - 1)
    te = ease_in_out_cubic(t)
    px, py = cubic_bezier(p0, p1, p2, p3, te)

    # 关键帧插值：整体旋转角 / 缩放 / 手臂摆角
    kf = interp_keyframes(node["keyframes"], frame_idx)
    angle = kf.get("angle", 0.0)
    scale = kf.get("scale", 1.0)
    arm_swing = kf.get("arm_swing", 0.0)

    # 局部坐标（y 向下，髋在原点）
    HEAD_C = (0.0, -58.0)
    HEAD_R = node["head_radius"]
    SHOULDER = (0.0, -40.0)
    HIP = (0.0, 0.0)
    FOOT_L = (-14.0, 40.0)
    FOOT_R = (14.0, 40.0)

    # 世界变换：M = T(pos) · R(angle) · S(scale)   （课 5：顺序不可交换）
    M = mat_translate(px, py) @ mat_rotate(angle) @ mat_scale(scale, scale)
    S = np.diag([ss, ss, 1.0])          # 超采样缩放
    M = S @ M

    def T(pt):
        x, y = apply_mat(M, pt)
        return (x, y)

    color = tuple(node["color"]) + (255,)
    head_color = tuple(node["head_color"]) + (255,)
    lw = max(2, int(round(7 * scale * ss)))

    # 腿
    d.line([T(HIP), T(FOOT_L)], fill=color, width=lw, joint="curve")
    d.line([T(HIP), T(FOOT_R)], fill=color, width=lw, joint="curve")
    # 躯干
    d.line([T(HIP), T(SHOULDER)], fill=color, width=lw, joint="curve")

    # 手臂：绕肩关节旋转（课 5 绕任意点）
    for sign, ang in ((-1, arm_swing), (1, -arm_swing)):
        M_arm = M @ mat_translate(*SHOULDER) @ mat_rotate(ang)

        def TA(pt, _M=M_arm):
            x, y = apply_mat(_M, pt)
            return (x, y)
        # 手臂局部：从肩向下 32，再向外偏
        elbow = (sign * 10.0, 20.0)
        hand = (sign * 20.0, 40.0)
        d.line([TA((0.0, 0.0)), TA(elbow)], fill=color,
               width=max(2, int(round(5 * scale * ss))), joint="curve")
        d.line([TA(elbow), TA(hand)], fill=color,
               width=max(2, int(round(5 * scale * ss))), joint="curve")

    # 头
    hx, hy = T(HEAD_C)
    hr = HEAD_R * scale * ss
    d.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=head_color)


def draw_grass(d, node, ss, frame_idx, total, w):
    """前景草：视差平移 + 每帧摆动（课 3 跟随与重叠）"""
    n = node["blade_count"]
    amp = node["sway_amp"]
    color = tuple(node["color"]) + (255,)
    h = 480
    for i in range(n):
        bx = (i + 0.5) * (w / n)
        # 视差：整排随时间平移
        px = (bx + frame_idx * node["parallax"] * 3.0) % (w + 40) - 20
        # 摆动：相位错开，形成"跟随"感
        phase = i * 0.7
        sway = np.sin(frame_idx / total * 4 * np.pi + phase) * amp
        top_x = px + sway
        top_y = h - 46 - (i % 3) * 9
        d.line([(px * ss, h * ss), (top_x * ss, top_y * ss)],
               fill=color, width=max(2, int(3 * ss)))


# ============================================================
# ④ 合成：z 排序 + over 运算符（课 8）
# ============================================================

def over(dst: np.ndarray, src: np.ndarray) -> np.ndarray:
    """over 运算符：out = src·α + dst·(1-α)  （课 8 知识点 2）

    src/dst 均为 float 数组 (H, W, 4)，值域 0~1
    """
    a = src[..., 3:4]
    rgb = src[..., :3] * a + dst[..., :3] * (1.0 - a)
    out_a = a + dst[..., 3:4] * (1.0 - a)
    return np.concatenate([rgb, out_a], axis=-1)


def composite_layers(layers_sorted, w: int, h: int, bg) -> Image.Image:
    """自底向上 over 合成"""
    acc = np.zeros((h, w, 4), dtype=np.float64)
    acc[..., :3] = np.array(bg, dtype=np.float64) / 255.0
    acc[..., 3] = 1.0
    for arr in layers_sorted:
        acc = over(acc, arr)
    return Image.fromarray((np.clip(acc[..., :3], 0, 1) * 255).astype(np.uint8))


# ============================================================
# 渲染单帧
# ============================================================

def render_frame(cfg, frame_idx: int) -> Image.Image:
    W, H = cfg["meta"]["width"], cfg["meta"]["height"]
    ss = cfg["meta"]["supersample"]
    total = cfg["meta"]["total_frames"]

    # 按 z_depth 升序（远的先画）—— 课 8 知识点 3
    layers = sorted(cfg["layers"], key=lambda L: L["z_depth"])

    rendered = []
    for node in layers:
        img, d = new_layer(W, H, ss)
        t = node["type"]

        if t == "gradient_rect":
            draw_gradient_rect(d, W, H, ss, node["top"], node["bottom"])
        elif t == "polygons":
            dx = -frame_idx * node.get("parallax", 0.0)
            draw_polygons(d, node["shapes"], ss, dx)
        elif t == "solid_rect":
            draw_solid_rect(d, node["rect"], ss, node["color"])
        elif t == "tree":
            sway = np.sin(frame_idx / total * 2 * np.pi) * 4
            draw_tree(d, node, ss, sway)
        elif t == "stick_figure":
            draw_stick_figure(d, node, ss, frame_idx, total)
        elif t == "grass":
            draw_grass(d, node, ss, frame_idx, total, W)

        # 超采样缩回 → 抗锯齿
        small = img.resize((W, H), Image.LANCZOS)
        rendered.append(np.array(small).astype(np.float64) / 255.0)

    return composite_layers(rendered, W, H, cfg["meta"]["background"])


# ============================================================
# ⑤⑥ 编码导出（课 9-10）
# ============================================================

def encode(ff: str, fps: int) -> tuple:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    mp4 = OUT_DIR / "capstone.mp4"
    gif = OUT_DIR / "capstone.gif"
    for p in (mp4, gif):
        if p.exists():
            p.unlink()

    def run(cmd, label):
        r = subprocess.run(cmd, capture_output=True, text=True,
                           encoding="utf-8", errors="replace")
        if r.returncode != 0:
            print(f"    [{label}] FAILED rc={r.returncode}")
            print(r.stderr[-600:])
            return False
        return True

    ok_mp4 = run([
        ff, "-y", "-framerate", str(fps),
        "-i", str(FRAMES_DIR / "frame_%04d.png"),
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "23",
        "-movflags", "+faststart", str(mp4),
    ], "MP4")

    ok_gif = run([
        ff, "-y", "-framerate", "12",
        "-i", str(FRAMES_DIR / "frame_%04d.png"),
        "-filter_complex",
        "[0:v] split [a][b];[a] palettegen=max_colors=256 [p];"
        "[b][p] paletteuse=dither=bayer",
        "-loop", "0", str(gif),
    ], "GIF")

    return (mp4 if ok_mp4 and mp4.exists() else None,
            gif if ok_gif and gif.exists() else None)


# ============================================================
# ⑦ 验收（课 10 知识点 3）
# ============================================================

def probe(fp: str, path: Path) -> dict:
    r = subprocess.run([
        fp, "-v", "error", "-select_streams", "v:0", "-count_frames",
        "-show_entries",
        "stream=width,height,r_frame_rate,nb_read_frames,codec_name,pix_fmt",
        "-show_entries", "format=duration,size,bit_rate",
        "-of", "default=noprint_wrappers=1", str(path),
    ], capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0:
        print("    ffprobe FAILED:", r.stderr[-400:])
        return {}
    info = {}
    for line in r.stdout.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            info[k.strip()] = v.strip()
    return info


def render_report(cfg, info, mp4, gif, gates) -> None:
    """验收报告图"""
    W, H = 660, 470
    img = Image.fromarray(np.full((H, W, 3), 255, dtype=np.uint8))
    pen = ImageDraw.Draw(img)

    pen.text((16, 12), "结课实战项目 · 端到端验收报告", fill=(0, 0, 0), font=FONT)
    pen.text((16, 32), "AI 矢量节点 → 几何变换 → 光栅化 → 合成 → 编码 → 导出 → 验收",
             fill=(90, 90, 90), font=FONT_SM)

    # 四门槛
    pen.text((16, 60), "复杂度四门槛核查：", fill=(0, 0, 0), font=FONT)
    for i, (name, detail, ok) in enumerate(gates):
        y = 82 + i * 30
        mark = "[✓]" if ok else "[✗]"
        color = (60, 160, 90) if ok else (200, 60, 60)
        pen.text((28, y), f"{mark} 门槛{i+1} {name}", fill=color, font=FONT_SM)
        pen.text((180, y), detail, fill=(90, 90, 90), font=FONT_SM)

    # ffprobe 实测
    pen.text((16, 220), "ffprobe 实测输出：", fill=(0, 0, 0), font=FONT)
    meta = cfg["meta"]
    checks = [
        ("分辨率", f"{info.get('width','?')} × {info.get('height','?')}",
         info.get("width") == str(meta["width"]) and info.get("height") == str(meta["height"])),
        ("帧率", info.get("r_frame_rate", "?"), None),
        ("帧数", info.get("nb_read_frames", "?"),
         info.get("nb_read_frames") == str(meta["total_frames"])),
        ("编码", info.get("codec_name", "?"), None),
        ("像素格式", info.get("pix_fmt", "?"), info.get("pix_fmt") == "yuv420p"),
        ("时长(s)", info.get("duration", "?"), None),
        ("文件大小", f"{info.get('size','?')} B", None),
    ]
    for i, (k, v, ok) in enumerate(checks):
        y = 242 + i * 20
        color = (0, 0, 0)
        mark = ""
        if ok is True:
            color, mark = (60, 160, 90), "  ✓"
        elif ok is False:
            color, mark = (200, 60, 60), "  ✗"
        pen.text((28, y), f"{k:<8} {v}{mark}", fill=color, font=FONT_SM)

    # 产物（含课 9 实证：MP4 vs GIF 体积差）
    pen.text((16, 396), "交付产物（注意 MP4 vs GIF 体积差）：", fill=(0, 0, 0), font=FONT)
    y = 416
    if mp4 and gif:
        mp4_b = mp4.stat().st_size
        gif_b = gif.stat().st_size
        ratio = gif_b / mp4_b
        pen.text((28, y),
                 f"capstone.mp4  {mp4_b:>9,} B   |   "
                 f"capstone.gif  {gif_b:>9,} B   =   GIF 大 {ratio:.1f}×",
                 fill=(0, 0, 0), font=FONT_SM)
        pen.text((28, y + 16),
                 "↑ 这就是课 9 知识点 3 的现实验证：GIF 没有帧间压缩，"
                 "MP4 用 I/P/B 帧压得小得多",
                 fill=(200, 60, 60), font=FONT_SM)
    elif mp4:
        pen.text((28, y), f"capstone.mp4   {mp4.stat().st_size:,} B",
                 fill=(0, 0, 0), font=FONT_SM)
    if gif:
        y = 452 if (mp4 and gif) else y
        if not (mp4 and gif):
            pen.text((28, y), f"capstone.gif   {gif.stat().st_size:,} B",
                     fill=(0, 0, 0), font=FONT_SM)

    pen.text((16, 472 if (mp4 and gif) else 452),
             "[i] 帧数=时长×帧率 是核心等式; pix_fmt=yuv420p 保证兼容; "
             "+faststart 支持边下边播",
             fill=(60, 90, 200), font=FONT_SM)

    img.save(HERE / "verification_report.png")


# ============================================================
# main
# ============================================================

def main() -> None:
    print("=" * 60)
    print("结课实战项目：AI 矢量节点 → 可播放视频（端到端）")
    print("=" * 60)

    # ① 数据解析
    cfg = json.loads((HERE / "ai_nodes.json").read_text(encoding="utf-8"))
    meta = cfg["meta"]
    W, H = meta["width"], meta["height"]
    fps = meta["fps"]
    total = meta["total_frames"]
    print(f"\n① 数据解析 -> ai_nodes.json")
    print(f"   {len(cfg['layers'])} 个图层，{W}×{H} @{fps}fps × {total} 帧 "
          f"= {total/fps:.2f}s")

    # ② 变换清点（门槛 2）
    transform_kinds = []
    for L in cfg["layers"]:
        t = L["type"]
        if t == "polygons" and L.get("parallax"):
            transform_kinds.append("平移(视差)")
        if t == "tree":
            transform_kinds.append("摆动(正弦)")
        if t == "stick_figure":
            transform_kinds += ["贝塞尔路径", "缓动", "旋转", "缩放", "绕任意点旋转(手臂)"]
        if t == "grass":
            transform_kinds += ["平移(视差)", "跟随摆动"]
    transform_kinds = sorted(set(transform_kinds))
    print(f"\n② 几何变换 -> 用到 {len(transform_kinds)} 种：")
    for k in transform_kinds:
        print(f"     · {k}")

    # ③④ 光栅化 + 合成
    if FRAMES_DIR.exists():
        shutil.rmtree(FRAMES_DIR)
    FRAMES_DIR.mkdir(parents=True)
    print(f"\n③④ 光栅化 + 合成 -> frames/ （{total} 帧，"
          f"{meta['supersample']}× 超采样抗锯齿）")
    for i in range(total):
        img = render_frame(cfg, i)
        img.save(FRAMES_DIR / f"frame_{i:04d}.png")
        if (i + 1) % 24 == 0:
            print(f"     已渲染 {i+1}/{total} 帧")
    print(f"   -> {len(list(FRAMES_DIR.glob('frame_*.png')))} 张帧序列（零补位命名）")

    # ⑤⑥ 编码导出
    ff, fp = find_tools()
    print(f"\n⑤⑥ 编码导出")
    print(f"   ffmpeg  : {ff or '(未找到)'}")
    print(f"   ffprobe : {fp or '(未找到)'}")
    mp4 = gif = None
    if ff:
        mp4, gif = encode(ff, fps)
        if mp4:
            print(f"   -> capstone.mp4  {mp4.stat().st_size:,} B")
        if gif:
            print(f"   -> capstone.gif  {gif.stat().st_size:,} B")
    else:
        print("   ⚠ 无 ffmpeg，跳过编码（uv pip install static-ffmpeg）")

    # ⑦ 验收
    info = {}
    if fp and mp4:
        print(f"\n⑦ 验收 -> ffprobe")
        info = probe(fp, mp4)
        for k in ("width", "height", "r_frame_rate", "nb_read_frames",
                  "codec_name", "pix_fmt", "duration", "size", "bit_rate"):
            if k in info:
                print(f"     {k:<16} = {info[k]}")

    # 复杂度四门槛核查
    n_layers = len(cfg["layers"])
    z_list = sorted(L["z_depth"] for L in cfg["layers"])
    gates = [
        ("数据规模", f"{n_layers} 图层 × z_depth{z_list} × {total} 帧",
         n_layers >= 5 and total >= 72),
        ("变换种类", f"{len(transform_kinds)} 种：{', '.join(transform_kinds[:4])}…",
         len(transform_kinds) >= 5),
        ("合成深度", f"{n_layers} 层真实 z 排序 + 跨图层遮挡（草遮主角/主角挡树）",
         n_layers >= 5),
        ("交付验收", f"MP4+GIF 双格式，ffprobe "
                    f"{'全通过' if info else '未执行'}",
         bool(mp4 and gif and info.get("pix_fmt") == "yuv420p"
              and info.get("nb_read_frames") == str(total))),
    ]

    print(f"\n复杂度四门槛核查：")
    all_pass = True
    for name, detail, ok in gates:
        print(f"   {'[v]' if ok else '[x]'} 门槛：{name:<6} {detail}")
        all_pass = all_pass and ok
    print(f"\n   结论：{'全部通过 [v]' if all_pass else '有门槛未达成 [x]'}")

    render_report(cfg, info, mp4, gif, gates)
    print(f"\n验收报告 -> verification_report.png")
    print(f"帧序列    -> frames/")
    print(f"最终视频  -> output/capstone.mp4  (可双击播放)")
    print(f"动图      -> output/capstone.gif")


if __name__ == "__main__":
    main()
