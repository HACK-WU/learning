r"""课 1 实操：帧、帧率、时间轴

把"时间"和"帧号"的换算真正跑一遍，再生成三组帧序列，直观对比拍数的影响：
    frames_ones/    一拍一：每帧都换画（24 张/秒）
    frames_twos/    一拍二：一张画停 2 帧（12 张/秒）
    frames_threes/  一拍三：一张画停 3 帧（8 张/秒）

运行方式（PowerShell，先切到课程目录）：
    .\playground\.venv\Scripts\python.exe .\playground\lesson-01\frames_demo.py

依赖：numpy、pillow（已装在 playground/.venv）
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

# Windows 控制台默认用 GBK 输出，中文会变乱码；强制 stdout 用 UTF-8
# （这行与动画知识无关，纯粹是为了让你在 PowerShell 里看到正常的中文）
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

FPS = 24          # 每秒帧数（frame per second）
DURATION = 1.0    # 时长（秒）
W, H = 320, 120   # 画布尺寸：宽 320 像素，高 120 像素

OUT_DIR = Path(__file__).parent


# ---------- 1. 帧数与时间的基本换算 ----------
def frame_count(duration_s: float, fps: int) -> int:
    """总帧数 = 时长 × 帧率（四舍五入，至少 1 帧）"""
    return max(1, int(round(duration_s * fps)))


def frame_to_time(frame_index: int, fps: int) -> float:
    """帧号 → 时间（秒）。第 0 帧在 t=0，第 f 帧在 t = f / fps"""
    return frame_index / fps


def time_to_frame(t: float, fps: int) -> int:
    """时间 → 帧号（该时刻落在第几帧上，向下取整）"""
    return int(t * fps)


# ---------- 2. 拍数：一张画停留几帧 ----------
def drawing_index(frame_index: int, step: int) -> int:
    """第 frame_index 帧用的是第几张画。

    step=1 → 一拍一（每帧都换画）
    step=3 → 一拍三（同一张画连续停 3 帧）
    """
    return frame_index // step


def ceil_div(a: int, b: int) -> int:
    """向上取整的整数除法：一共需要几张画"""
    return -(-a // b)


# ---------- 3. 画一帧 ----------
def draw_frame(frame_index: int, total: int, step: int) -> Image.Image:
    """画一个从左往右移动的小球，返回 PIL 图像"""
    # 用 numpy 建一张纯白画布：H 行 × W 列 × 3 通道，uint8（0~255）
    canvas = np.full((H, W, 3), 255, dtype=np.uint8)
    img = Image.fromarray(canvas)
    pen = ImageDraw.Draw(img)

    # 【本课核心】位置按「画」的序号算，而不是按帧号算。
    # 于是一拍三时，连续 3 帧的小球位置完全相同 —— 这就是"拍数"的全部秘密。
    d = drawing_index(frame_index, step)
    drawings = max(1, ceil_div(total, step))   # 这一秒一共要画几张
    progress = d / max(1, drawings - 1)        # 归一化进度：0.0 ~ 1.0
    x = int(20 + (W - 40) * progress)          # 小球圆心的 x 坐标

    pen.ellipse([x - 10, H // 2 - 10, x + 10, H // 2 + 10], fill=(220, 60, 60))
    pen.text(
        (8, 8),
        f"f{frame_index:03d}  t={frame_to_time(frame_index, FPS):.3f}s  pic#{d}",
        fill=(0, 0, 0),
    )
    return img


def render_sequence(step: int, out_name: str) -> None:
    """按给定拍数渲染一整段帧序列并落盘"""
    total = frame_count(DURATION, FPS)
    out_dir = OUT_DIR / out_name
    out_dir.mkdir(parents=True, exist_ok=True)
    for f in range(total):
        draw_frame(f, total, step).save(out_dir / f"frame_{f:03d}.png")


def render_spacing_demo() -> None:
    """知识点 1 用：帧数完全相同，只改「每帧位移」，对比运动感"""
    total = frame_count(DURATION, FPS)
    for name, step_px in (("spacing_small", 12), ("spacing_big", 100)):
        out_dir = OUT_DIR / name
        out_dir.mkdir(parents=True, exist_ok=True)
        for f in range(total):
            canvas = np.full((H, W, 3), 255, dtype=np.uint8)
            img = Image.fromarray(canvas)
            pen = ImageDraw.Draw(img)
            # 小球匀速右移，超出画布宽度就绕回左侧，保证 24 帧都能看见
            x = 20 + ((step_px * f) % (W - 40))
            pen.ellipse([x - 10, H // 2 - 10, x + 10, H // 2 + 10], fill=(40, 90, 200))
            pen.text((8, 8), f"f{f:03d}  step={step_px}px", fill=(0, 0, 0))
            img.save(out_dir / f"frame_{f:03d}.png")


def main() -> None:
    total = frame_count(DURATION, FPS)

    print(f"帧率 {FPS} fps，时长 {DURATION} 秒")
    print(f"  -> 总帧数 = {total} 帧，帧号范围 0 ~ {total - 1}")
    print(f"  -> 最后一帧的时间 = {frame_to_time(total - 1, FPS):.3f}s（注意不等于 {DURATION:.3f}s）")
    print(f"  -> t=0.5s 落在第 {time_to_frame(0.5, FPS)} 帧")
    print()

    for step, name in ((1, "frames_ones"), (2, "frames_twos"), (3, "frames_threes")):
        render_sequence(step, name)
        pics = max(1, ceil_div(total, step))
        print(f"一拍{step}：{total} 帧只需要 {pics} 张画（{pics} 张/秒） -> {name}/")

    print()
    print("帧号 -> 用第几张画（一拍三）：")
    print("  " + "  ".join(f"f{f}:pic{drawing_index(f, 3)}" for f in range(9)))

    print()
    print("知识点 1 对比：帧数完全相同（都是 24 帧），只改每帧位移")
    render_spacing_demo()
    print("  spacing_small/  每帧移动 12px  -> 逐张看：小球平滑移动")
    print("  spacing_big/    每帧移动 100px -> 逐张看：位置跳变，运动感崩塌")


if __name__ == "__main__":
    main()
