r"""课 2 实操：关键帧、中割与律表

把"只画关键帧、中间补出来"和"律表驱动渲染"两件事跑一遍，生成三组帧：

    inbetween_linear/      2 张关键帧（左端 A、右端 C），中间 22 帧线性插值
    inbetween_breakdown/   3 张关键帧（左端 A、顶点小原画 B、右端 C），中间 22 帧分段线性插值
    xsheet_frames/         按"律表"驱动的多图层场景：顶部 4 行是当前帧的律表，底部是按律表渲染的画面

运行方式（PowerShell，先切到课程目录）：
    .\playground\.venv\Scripts\python.exe .\playground\lesson-02\xsheet_demo.py

依赖：numpy、pillow（已装在 playground/.venv）
"""

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
B_SPLIT = TOTAL // 2  # 12：A→B 段 / B→C 段 的切换点
OUT_DIR = Path(__file__).parent


# ---------- 字体加载（中文显示必需） ----------

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


# ---------- 知识点 1：关键帧与中割 ----------

# 三个关键帧：A 左下、B 顶点、C 右下
KEY_A = (30, 70)
KEY_B = (160, 20)
KEY_C = (290, 70)


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def pos_linear(f: int) -> tuple[int, int]:
    """只有 A/C 两张关键帧：从 A 匀速走到 C"""
    t = f / (TOTAL - 1)
    return int(lerp(KEY_A[0], KEY_C[0], t)), int(lerp(KEY_A[1], KEY_C[1], t))


def pos_breakdown(f: int) -> tuple[int, int]:
    """3 张关键帧，中点切换段：A→B 段、B→C 段"""
    if f <= B_SPLIT:
        t = f / B_SPLIT
        return int(lerp(KEY_A[0], KEY_B[0], t)), int(lerp(KEY_A[1], KEY_B[1], t))
    t = (f - B_SPLIT) / (TOTAL - 1 - B_SPLIT)
    return int(lerp(KEY_B[0], KEY_C[0], t)), int(lerp(KEY_B[1], KEY_C[1], t))


# ---------- 画图工具 ----------

def draw_trail(img, positions, step: int = 2, color=(220, 220, 220), r: int = 2) -> None:
    pen = ImageDraw.Draw(img)
    for i in range(0, len(positions), step):
        x, y = positions[i]
        pen.ellipse([x - r, y - r, x + r, y + r], fill=color)


def draw_ball(pen, x: int, y: int, color=(40, 90, 200), r: int = 8) -> None:
    pen.ellipse([x - r, y - r, x + r, y + r], fill=color)


def draw_key_marker(pen, x: int, y: int, letter: str, color) -> None:
    """关键帧标记：空心彩色圆 + 字母标签"""
    pen.ellipse([x - 5, y - 5, x + 5, y + 5], outline=color, width=1)
    pen.text((x - 3, y - 14), letter, fill=color, font=FONT)


# ---------- 渲染 inbetween_linear（2 张关键帧） ----------

def render_linear() -> None:
    out_dir = OUT_DIR / "inbetween_linear"
    out_dir.mkdir(parents=True, exist_ok=True)
    for f in range(TOTAL):
        canvas = np.full((H, W, 3), 255, dtype=np.uint8)
        img = Image.fromarray(canvas)
        pen = ImageDraw.Draw(img)
        x, y = pos_linear(f)
        past = [pos_linear(i) for i in range(f)]
        draw_trail(img, past, step=2)
        draw_ball(pen, x, y)
        pen.text((6, 6), f"f{f:03d}  ({x},{y})", fill=(0, 0, 0), font=FONT)
        img.save(out_dir / f"frame_{f:03d}.png")


# ---------- 渲染 inbetween_breakdown（3 张关键帧） ----------

def render_breakdown() -> None:
    out_dir = OUT_DIR / "inbetween_breakdown"
    out_dir.mkdir(parents=True, exist_ok=True)
    for f in range(TOTAL):
        canvas = np.full((H, W, 3), 255, dtype=np.uint8)
        img = Image.fromarray(canvas)
        pen = ImageDraw.Draw(img)
        x, y = pos_breakdown(f)
        past = [pos_breakdown(i) for i in range(f)]
        draw_trail(img, past, step=2)
        # 三个关键帧标记（空心圆 + 字母），当前位置覆盖一颗实心蓝球
        for (px, py), letter, color in (
            (KEY_A, "A", (200, 60, 60)),
            (KEY_B, "B", (60, 160, 80)),
            (KEY_C, "C", (200, 60, 60)),
        ):
            draw_key_marker(pen, px, py, letter, color)
        draw_ball(pen, x, y)
        pen.text((6, 6), f"f{f:03d}  ({x},{y})", fill=(0, 0, 0), font=FONT)
        img.save(out_dir / f"frame_{f:03d}.png")


# ---------- 知识点 2：律表 ----------

# 4 个图层在 24 帧上的"画号 / 指示"
# 律表的数据结构 = 嵌套 dict：{layer: {frame: value, ...}, ...}
XSHEET: dict[str, dict[int, str]] = {
    "角色": {
        0: "1", 1: "1", 2: "1", 3: "1", 4: "1", 5: "1",
        6: "2", 7: "2", 8: "2", 9: "2", 10: "2", 11: "2",
        12: "3", 13: "3", 14: "3", 15: "3", 16: "3", 17: "3",
        18: "2", 19: "2", 20: "2", 21: "2", 22: "2", 23: "2",
    },
    "道具": {f: "1" for f in range(TOTAL)},
    "背景": {f: "1" for f in range(TOTAL)},
    "摄影": {f: "静止" for f in range(TOTAL)},
}

LAYERS_ORDER = ["角色", "道具", "背景", "摄影"]

# 角色层画号 → 球的 y 位置（y 越小越靠上，场景区 y=44..120 留出律表 44px）
CHAR_Y_BY_DRAWING = {"1": 66, "2": 58, "3": 50, "-": 66}


def get_xsheet_row(f: int) -> dict:
    """取出第 f 帧的"整行"律表数据"""
    return {layer: XSHEET[layer].get(f, "-") for layer in LAYERS_ORDER}


def render_xsheet() -> None:
    out_dir = OUT_DIR / "xsheet_frames"
    out_dir.mkdir(parents=True, exist_ok=True)
    for f in range(TOTAL):
        canvas = np.full((H, W, 3), 255, dtype=np.uint8)
        img = Image.fromarray(canvas)
        pen = ImageDraw.Draw(img)
        row = get_xsheet_row(f)

        # 顶部 44px：律表 4 行（每行 10px），与场景之间有分隔线
        for i, layer in enumerate(LAYERS_ORDER):
            pen.text((6, 3 + i * 10), f"{layer}:{row[layer]}", fill=(0, 0, 0), font=FONT)
        # 律表与场景的分隔线
        pen.line([(0, 44), (W, 44)], fill=(180, 180, 180), width=1)

        # 底部场景（按律表数据逐层渲染；场景区 y=44..120）
        # 背景层：绿色地坪
        pen.rectangle([0, 104, W, H], fill=(180, 220, 180))
        # 道具层：蓝色方块（仅一种画号，画号恒为 1，位置固定）
        pen.rectangle([110, 74, 150, 104], fill=(60, 110, 200))
        # 角色层：黑色球，按画号决定 y 位置（在道具上方，y 越小越靠上）
        char_y = CHAR_Y_BY_DRAWING[row["角色"]]
        pen.ellipse([122, char_y - 8, 138, char_y + 8], fill=(30, 30, 30))
        # 帧号水印（右上角）
        pen.text((W - 40, 3), f"f{f:03d}", fill=(150, 0, 0), font=FONT)

        img.save(out_dir / f"frame_{f:03d}.png")


# ---------- main ----------

def main() -> None:
    print("=== 知识点 1：关键帧与中割 ===")
    print(f"关键帧 A={KEY_A}   C={KEY_C}                            -> inbetween_linear/    (2 个关键点：首末 2 张原画)")
    print(f"关键帧 A={KEY_A}   B={KEY_B}   C={KEY_C}                -> inbetween_breakdown/ (3 个关键点：2 张原画 + 1 张小原画 B)")
    render_linear()
    render_breakdown()
    print(f"共生成 {TOTAL} 帧 × 2 个序列")
    print()
    print("=== 知识点 2：律表驱动渲染 ===")
    print(f"律表 4 列: {' / '.join(LAYERS_ORDER)}")
    render_xsheet()
    print(f"律表驱动渲染了 {TOTAL} 帧 -> xsheet_frames/")
    print()
    for f in (0, B_SPLIT, TOTAL - 1):
        row = get_xsheet_row(f)
        s = "  ".join(f"{k}:{v}" for k, v in row.items())
        print(f"f{f:03d}  {s}")


if __name__ == "__main__":
    main()
