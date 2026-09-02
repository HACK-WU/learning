r"""课 2 第二批实操：分层与赛璐珞、洋葱皮与时间参考

跑出五组帧序列，把"怎么不重画"和"怎么参考前后帧"两件事可视化：

    layer_bg/           背景层：24 帧内容完全相同（证明"只画 1 张，复用 24 次"）
    layer_char/         角色层：24 帧各不相同（角色在动，每帧都要画）
    layers_composite/   合成结果：背景层 + 角色层 = 最终画面
    layers_parallax/    视差演示：远层慢移 + 近层快移 → 纵深感（伪 3D 的原理）
    onion_skin/         洋葱皮：当前帧实心 + 前 2 帧绿 + 后 2 帧红（半透明叠加）

运行方式（PowerShell，先切到课程目录）：
    .\playground\.venv\Scripts\python.exe .\playground\lesson-02\layers_demo.py

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


# ---------- 通用工具 ----------

def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def new_canvas() -> Image.Image:
    """一张纯白画布（RGB）"""
    return Image.fromarray(np.full((H, W, 3), 255, dtype=np.uint8))


def new_layer() -> Image.Image:
    """一张全透明画布（RGBA），用于逐层合成与洋葱皮半透明叠加"""
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))


# ---------- 知识点 3：分层与赛璐珞 ----------

# 角色（黑色球）的抛物线轨迹：3 个关键点（起点 / 顶点小原画 / 终点）
CHAR_START = (40, 62)
CHAR_MID = (160, 44)
CHAR_END = (280, 62)


def char_pos(f: int) -> tuple[int, int]:
    """角色位置：A→B 段 + B→C 段的抛物线（复习第一批的 3 个关键点）"""
    mid = TOTAL // 2
    if f <= mid:
        t = f / mid
        return int(lerp(CHAR_START[0], CHAR_MID[0], t)), int(lerp(CHAR_START[1], CHAR_MID[1], t))
    t = (f - mid) / (TOTAL - 1 - mid)
    return int(lerp(CHAR_MID[0], CHAR_END[0], t)), int(lerp(CHAR_MID[1], CHAR_END[1], t))


def draw_bg(pen) -> None:
    """背景层：草地 + 远山 + 太阳。这一层全程不变，只需画 1 张。"""
    pen.rectangle([0, 88, W, H], fill=(170, 215, 170))                    # 草地
    pen.polygon([(30, 88), (90, 40), (150, 88)], fill=(150, 175, 205))    # 远山 1
    pen.polygon([(120, 88), (195, 32), (270, 88)], fill=(130, 160, 195))  # 远山 2
    pen.ellipse([255, 18, 285, 48], fill=(245, 215, 120))                 # 太阳


def draw_char(pen, x: int, y: int) -> None:
    """角色层：一个黑色球（代表角色在当前帧的姿势）"""
    pen.ellipse([x - 11, y - 11, x + 11, y + 11], fill=(40, 40, 40))


def render_layers() -> tuple[int, int]:
    """生成 背景层 / 角色层 / 合成结果 三组帧，返回 (分层前张数, 分层后张数)"""
    bg_dir = OUT_DIR / "layer_bg"
    char_dir = OUT_DIR / "layer_char"
    comp_dir = OUT_DIR / "layers_composite"
    for d in (bg_dir, char_dir, comp_dir):
        d.mkdir(parents=True, exist_ok=True)

    bg_sizes = set()
    for f in range(TOTAL):
        x, y = char_pos(f)

        # --- 背景层：注意标签里【不写帧号】，保证 24 帧完全一致 ---
        img_bg = new_canvas()
        draw_bg(ImageDraw.Draw(img_bg))
        ImageDraw.Draw(img_bg).text(
            (6, 4), "背景层（全程只画这 1 张，复用 24 次）", fill=(90, 90, 90), font=FONT
        )
        img_bg.save(bg_dir / f"frame_{f:03d}.png")
        bg_sizes.add((bg_dir / f"frame_{f:03d}.png").stat().st_size)

        # --- 角色层：每帧不同（标签带位置，会随帧变化）---
        img_char = new_canvas()
        draw_char(ImageDraw.Draw(img_char), x, y)
        ImageDraw.Draw(img_char).text(
            (6, 4), f"角色层 f{f:03d}  位置({x},{y})", fill=(90, 90, 90), font=FONT
        )
        img_char.save(char_dir / f"frame_{f:03d}.png")

        # --- 合成结果：背景层 + 角色层 ---
        img_comp = new_canvas()
        pen = ImageDraw.Draw(img_comp)
        draw_bg(pen)
        draw_char(pen, x, y)
        pen.text((6, 4), f"合成结果 f{f:03d}", fill=(90, 90, 90), font=FONT)
        img_comp.save(comp_dir / f"frame_{f:03d}.png")

    # 用"背景层 24 个文件大小是否只有 1 种"来证明"只画了 1 张"
    if len(bg_sizes) == 1:
        print(f"  [验证] 背景层 24 帧的文件大小完全相同（{bg_sizes.pop()} 字节）"
              f" → 证明「只画 1 张，复用 24 次」")

    flat = TOTAL * 2      # 不分层：每帧都要重画"背景 + 角色"两个对象
    layered = 1 + TOTAL   # 分层：背景 1 张 + 角色 24 张
    return flat, layered


def render_parallax() -> None:
    """视差演示：远层慢移、近层快移 → 纵深感（伪 3D 的原理）"""
    out_dir = OUT_DIR / "layers_parallax"
    out_dir.mkdir(parents=True, exist_ok=True)
    for f in range(TOTAL):
        t = f / (TOTAL - 1)
        img = new_canvas()
        pen = ImageDraw.Draw(img)

        pen.rectangle([0, 88, W, H], fill=(170, 215, 170))                 # 草地（最底）
        # 远层：山，移动最慢（24 帧只走 30px）
        pen.polygon([(30 - 30 * t, 88), (90 - 30 * t, 40), (150 - 30 * t, 88)], fill=(150, 175, 205))
        pen.polygon([(120 - 30 * t, 88), (195 - 30 * t, 32), (270 - 30 * t, 88)], fill=(130, 160, 195))
        # 中景层：树，移动较快（24 帧走 120px）
        tree_x = 60 + 120 * t
        pen.rectangle([tree_x - 4, 70, tree_x + 4, 88], fill=(110, 80, 50))
        pen.ellipse([tree_x - 14, 48, tree_x + 14, 76], fill=(80, 150, 80))
        # 近景层：角色，移动最快（24 帧走 260px）
        char_x = 20 + 260 * t
        pen.ellipse([char_x - 11, 66, char_x + 11, 88], fill=(40, 40, 40))

        pen.text((6, 4), f"视差 f{f:03d}  远慢近快 → 纵深感", fill=(90, 90, 90), font=FONT)
        img.save(out_dir / f"frame_{f:03d}.png")


# ---------- 知识点 4：洋葱皮与时间参考 ----------

ONION_BEFORE = 2   # 向前参考几帧（绿色）
ONION_AFTER = 2    # 向后参考几帧（红色）


def render_onion_skin() -> None:
    """洋葱皮：当前帧实心黑球，前 2 帧绿色半透明，后 2 帧红色半透明"""
    out_dir = OUT_DIR / "onion_skin"
    out_dir.mkdir(parents=True, exist_ok=True)

    for f in range(TOTAL):
        img = new_layer()

        # 背景（不透明，先画 RGB 白底再画背景，转 RGBA 后所有像素 alpha=255）
        bg = new_canvas()
        draw_bg(ImageDraw.Draw(bg))
        img = Image.alpha_composite(img, bg.convert("RGBA"))

        # 过去的帧：绿色半透明（越远越淡由绘制顺序自然产生）
        for k in range(ONION_BEFORE, 0, -1):
            ff = f - k
            if 0 <= ff < TOTAL:
                gx, gy = char_pos(ff)
                ghost = new_layer()
                ImageDraw.Draw(ghost).ellipse(
                    [gx - 11, gy - 11, gx + 11, gy + 11], fill=(60, 180, 90, 80)
                )
                img = Image.alpha_composite(img, ghost)

        # 未来的帧：红色半透明
        for k in range(ONION_AFTER, 0, -1):
            ff = f + k
            if 0 <= ff < TOTAL:
                gx, gy = char_pos(ff)
                ghost = new_layer()
                ImageDraw.Draw(ghost).ellipse(
                    [gx - 11, gy - 11, gx + 11, gy + 11], fill=(215, 70, 70, 80)
                )
                img = Image.alpha_composite(img, ghost)

        # 当前帧：实心（最上层）
        cx, cy = char_pos(f)
        cur = new_layer()
        ImageDraw.Draw(cur).ellipse([cx - 11, cy - 11, cx + 11, cy + 11], fill=(40, 40, 40, 255))
        img = Image.alpha_composite(img, cur)

        pen = ImageDraw.Draw(img)
        pen.text(
            (6, 4),
            f"洋葱皮 f{f:03d}  前{ONION_BEFORE}绿(过去) 后{ONION_AFTER}红(未来)",
            fill=(90, 90, 90), font=FONT,
        )
        img.convert("RGB").save(out_dir / f"frame_{f:03d}.png")


# ---------- main ----------

def main() -> None:
    print("=== 知识点 3：分层与赛璐珞 ===")
    flat, layered = render_layers()
    print(f"分层前（每帧都要重画整个画面 = 背景 + 角色）：{TOTAL} 帧 × 2 = {flat} 张画")
    print(f"分层后（背景静态只画 1 张，角色动态画 {TOTAL} 张）：1 + {TOTAL} = {layered} 张画")
    print(f"  -> 省了 {flat - layered} 张，减少 {(flat - layered) / flat * 100:.1f}%")
    print(f"  -> layer_bg/（24 帧相同） layer_char/（24 帧不同） layers_composite/（合成结果）")
    print()
    render_parallax()
    print(f"视差演示（远层慢移 30px / 中景 120px / 近景 260px）-> layers_parallax/")
    print(f"  -> 同样的位移差 = 纵深感，这就是「伪 3D」的原理")
    print()
    print("=== 知识点 4：洋葱皮与时间参考 ===")
    render_onion_skin()
    print(f"洋葱皮：当前帧实心黑 + 前 {ONION_BEFORE} 帧绿 + 后 {ONION_AFTER} 帧红 -> onion_skin/")
    print()
    for f in (0, TOTAL // 2, TOTAL - 1):
        x, y = char_pos(f)
        print(f"f{f:03d}  角色位置 ({x},{y})")


if __name__ == "__main__":
    main()
