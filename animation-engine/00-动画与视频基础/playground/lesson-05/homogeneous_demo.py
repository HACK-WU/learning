r"""课 5 第二批实操：齐次坐标、绕任意点与层级变换

把"平移怎么进矩阵"和"父子层级怎么连乘"跑出来，生成四组产物：

    homogeneous_compare.png   2×2 装不下平移 vs 3×3 齐次坐标统一三种变换
    point_vs_vector_homo.png  齐次坐标下 点(w=1) 与 向量(w=0) 在平移下的区别
    rotate_around_point/      24 帧，上行错误(绕原点) vs 下行正确(绕点 P)
    hierarchy_demo/           24 帧，肩→肘→腕→指尖 的父子层级矩阵连乘

运行方式（PowerShell，先切到课程目录）：
    .\playground\.venv\Scripts\python.exe .\playground\lesson-05\homogeneous_demo.py

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


def to_screen(x: float, y: float, cx: float, cy: float) -> tuple[int, int]:
    """数学坐标 (x, y) → 屏幕像素（课 4：屏幕 y 向下，要翻转）"""
    return int(round(cx + x)), int(round(cy - y))


# ---------- 齐次坐标：3×3 矩阵 ----------

def mat3_translate(tx: float, ty: float) -> np.ndarray:
    """平移矩阵（2×2 装不下的那个，升到 3×3 就有了）"""
    return np.array([[1.0, 0.0, tx],
                     [0.0, 1.0, ty],
                     [0.0, 0.0, 1.0]])


def mat3_scale(sx: float, sy: float) -> np.ndarray:
    """缩放矩阵"""
    return np.array([[sx,  0.0, 0.0],
                     [0.0,  sy, 0.0],
                     [0.0, 0.0, 1.0]])


def mat3_rotate(theta: float) -> np.ndarray:
    """旋转矩阵（数学系逆时针为正；屏幕 y 向下 → 视觉上是顺时针）"""
    c, s = math.cos(theta), math.sin(theta)
    return np.array([[c, -s, 0.0],
                     [s,  c, 0.0],
                     [0.0, 0.0, 1.0]])


def homo_point(x: float, y: float) -> np.ndarray:
    """点：第 3 分量 w=1 → 会被平移影响"""
    return np.array([x, y, 1.0])


def homo_vector(x: float, y: float) -> np.ndarray:
    """向量：第 3 分量 w=0 → 不被平移影响（平移不变性，课 4 的代数规则在这里有了几何解释）"""
    return np.array([x, y, 0.0])


def rotate_around(px: float, py: float, theta: float) -> np.ndarray:
    """绕任意点 P 旋转 θ：M = T(P) · R(θ) · T(-P)  （从右往左执行）"""
    return mat3_translate(px, py) @ mat3_rotate(theta) @ mat3_translate(-px, -py)


# ---------- 知识点 3：齐次坐标 ----------

def render_homogeneous_compare() -> None:
    """2×2 装不下平移 vs 3×3 齐次坐标统一三种变换"""
    cw, ch = 620, 400
    img = new_canvas(cw, ch)
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "齐次坐标：给 2D 点加一维，让平移也能写进矩阵", fill=(0, 0, 0), font=FONT)
    pen.text((16, 26), "2D 平移 = 3D 空间中沿 z=1 平面的「切变」——平移在更高一维里其实是线性的",
             fill=(80, 80, 80), font=FONT_SM)

    # ---- 左：2×2 的困境 ----
    pen.text((20, 58), "❌ 2×2 矩阵：装不下平移", fill=(200, 60, 60), font=FONT)
    pen.text((20, 76), "线性部分 v' = M·v 可以，", fill=(90, 90, 90), font=FONT_SM)
    pen.text((20, 90), "但平移 v' = v + t 里的 +t", fill=(90, 90, 90), font=FONT_SM)
    pen.text((20, 104), "永远游离在矩阵乘法之外。", fill=(90, 90, 90), font=FONT_SM)
    pen.text((20, 126), "→ 连续变换只能写成", fill=(90, 90, 90), font=FONT_SM)
    pen.text((20, 140), "  M·v + t₁ + t₂ + …", fill=(90, 90, 90), font=FONT_SM)
    pen.text((20, 154), "  每步都要单独加一次平移", fill=(200, 60, 60), font=FONT_SM)

    # ---- 右：3×3 的解决 ----
    pen.text((330, 58), "✅ 3×3 齐次坐标：三种变换统一", fill=(60, 160, 90), font=FONT)
    forms = [
        ("平移", "⎡ 1  0  tx ⎤\n⎢ 0  1  ty ⎥\n⎣ 0  0   1 ⎦", 330),
        ("缩放", "⎡ sx  0   0 ⎤\n⎢ 0  sy   0 ⎥\n⎣ 0   0   1 ⎦", 440),
        ("旋转", "⎡ cos -sin  0 ⎤\n⎢ sin  cos  0 ⎥\n⎣  0    0   1 ⎦", 550),
    ]
    for name, form, fx in forms:
        pen.text((fx, 78), f"{name}：", fill=(60, 60, 60), font=FONT)
        for i, line in enumerate(form.split("\n")):
            pen.text((fx, 92 + i * 13), line, fill=(40, 40, 40), font=FONT_SM)

    # 仿射的通用形式
    pen.text((330, 150), "仿射通用形式（左上 2×2 = 线性部分，右上 2×1 = 平移）：",
             fill=(60, 60, 60), font=FONT)
    pen.text((330, 168), "M = ⎡ a  b  tx ⎤\n     ⎢ c  d  ty ⎥\n     ⎣ 0  0   1 ⎦",
             fill=(40, 40, 40), font=FONT_SM)

    # ---- 中间：点 vs 向量 ----
    pen.text((20, 190), "关键：点 (x, y, 1) vs 向量 (x, y, 0)", fill=(0, 0, 0), font=FONT)
    pen.text((20, 208), "第 3 个分量 w 决定了「能不能被平移影响」：", fill=(80, 80, 80), font=FONT_SM)

    # 演示：同一个平移矩阵作用在点和向量上
    T = mat3_translate(40.0, 20.0)
    p_in, p_out = homo_point(10, 10), T @ homo_point(10, 10)
    v_in, v_out = homo_vector(10, 10), T @ homo_vector(10, 10)

    pen.text((20, 232), f"点   (10, 10, 1) --T(40,20)--> ({p_out[0]:.0f}, {p_out[1]:.0f}, {p_out[2]:.0f})"
                        f"   ← 被平移了 ✓", fill=(60, 100, 200), font=FONT_SM)
    pen.text((20, 248), f"向量 (10, 10, 0) --T(40,20)--> ({v_out[0]:.0f}, {v_out[1]:.0f}, {v_out[2]:.0f})"
                        f"      ← 纹丝不动 ✓", fill=(60, 160, 90), font=FONT_SM)
    pen.text((20, 268), "这就是课 4「向量有平移不变性」的几何来源 —— w=0 让平移矩阵的第 3 列乘以 0",
             fill=(90, 90, 90), font=FONT_SM)

    # ---- 底部：绕任意点三步 ----
    pen.text((20, 300), "绕任意点 P 旋转 θ = 三步连乘（从右往左执行）：", fill=(0, 0, 0), font=FONT)
    pen.text((20, 318), "M = T(P) · R(θ) · T(-P)", fill=(60, 60, 60), font=FONT)
    pen.text((20, 336), "    ① 把 P 平移到原点    ② 绕原点旋转 θ    ③ 平移回去",
             fill=(90, 90, 90), font=FONT_SM)
    pen.text((20, 356), "⚠ 顺序不能反：T(-P)·R(θ)·T(P) 会得到完全不同的结果（第一批已证明顺序不可交换）",
             fill=(200, 60, 60), font=FONT_SM)

    pen.text((16, 382), "约定：列向量，P' = M · P（3×3 矩阵 左乘 3×1 列向量）",
             fill=(0, 0, 0), font=FONT_SM)

    img.save(OUT_DIR / "homogeneous_compare.png")


def render_point_vs_vector_homo() -> None:
    """可视化：同一个平移矩阵，点动了、向量没动"""
    cw, ch = 560, 300
    img = new_canvas(cw, ch)
    pen = ImageDraw.Draw(img)

    pen.text((16, 10), "齐次坐标：w=1 的点会被平移，w=0 的向量不会", fill=(0, 0, 0), font=FONT)
    pen.text((16, 26), "同一个平移矩阵 T(60, -20) 作用在两者上", fill=(80, 80, 80), font=FONT_SM)

    T = mat3_translate(60.0, -20.0)
    cx, cy = 60, 200          # 数学原点

    # 坐标轴
    pen.line([(cx, cy), (cx, 40)], fill=(215, 215, 215), width=1)
    pen.line([(cx, cy), (520, cy)], fill=(215, 215, 215), width=1)
    pen.text((cx + 4, 44), "y", fill=(180, 180, 180), font=FONT_SM)
    pen.text((516, cy + 4), "x", fill=(180, 180, 180), font=FONT_SM)
    pen.ellipse([cx - 3, cy - 3, cx + 3, cy + 3], fill=(120, 120, 120))
    pen.text((cx - 26, cy + 6), "原点", fill=(120, 120, 120), font=FONT_SM)

    def arrow(x0, y0, x1, y1, color, width=2, label=None):
        pen.line([(x0, y0), (x1, y1)], fill=color, width=width)
        ang = math.atan2(y1 - y0, x1 - x0)
        for da in (-2.6, 2.6):
            pen.line([(x1, y1),
                      (x1 + 9 * math.cos(ang + da), y1 + 9 * math.sin(ang + da))],
                     fill=color, width=width)
        if label:
            pen.text((x1 + 6, y1 - 4), label, fill=color, font=FONT_SM)

    # ---- 点 (30, 40, 1)：被平移 ----
    p0 = (30.0, 40.0)
    p1 = T @ homo_point(*p0)
    pen.ellipse([to_screen(p0[0], p0[1], cx, cy)[0] - 5,
                 to_screen(p0[0], p0[1], cx, cy)[1] - 5,
                 to_screen(p0[0], p0[1], cx, cy)[0] + 5,
                 to_screen(p0[0], p0[1], cx, cy)[1] + 5], fill=(150, 150, 150))
    pen.text((to_screen(p0[0], p0[1], cx, cy)[0] - 16,
              to_screen(p0[0], p0[1], cx, cy)[1] + 8), "点 w=1", fill=(150, 150, 150), font=FONT_SM)
    pen.ellipse([to_screen(p1[0], p1[1], cx, cy)[0] - 5,
                 to_screen(p1[0], p1[1], cx, cy)[1] - 5,
                 to_screen(p1[0], p1[1], cx, cy)[0] + 5,
                 to_screen(p1[0], p1[1], cx, cy)[1] + 5], fill=(60, 100, 200))
    pen.text((to_screen(p1[0], p1[1], cx, cy)[0] + 8,
              to_screen(p1[0], p1[1], cx, cy)[1] - 4),
             f"平移后 ({p1[0]:.0f},{p1[1]:.0f})", fill=(60, 100, 200), font=FONT_SM)
    arrow(*to_screen(p0[0], p0[1], cx, cy), *to_screen(p1[0], p1[1], cx, cy),
          (60, 100, 200), width=1)

    # ---- 向量 (30, 40, 0)：不动。把它画在另一个起点，展示"平移不变性" ----
    v_origin = (200.0, 20.0)     # 向量的绘制起点（几何上无意义，只为可视化）
    v0 = (30.0, 40.0)
    v1 = T @ homo_vector(*v0)
    arrow(*to_screen(v_origin[0], v_origin[1], cx, cy),
          *to_screen(v_origin[0] + v0[0], v_origin[1] + v0[1], cx, cy),
          (150, 150, 150), width=1, label="向量 w=0")
    # 平移后：完全重合（画粗一点盖在上面，说明"没动"）
    arrow(*to_screen(v_origin[0], v_origin[1], cx, cy),
          *to_screen(v_origin[0] + v1[0], v_origin[1] + v1[1], cx, cy),
          (60, 160, 90), width=3, label=f"平移后仍 ({v1[0]:.0f},{v1[1]:.0f})")

    # ---- 结论 ----
    pen.text((16, 250), f"点   (30,40,1) --T(60,-20)--> ({p1[0]:.0f}, {p1[1]:.0f}, {p1[2]:.0f})"
                        f"    位置变了（第三列 × w=1 生效）", fill=(60, 100, 200), font=FONT_SM)
    pen.text((16, 266), f"向量 (30,40,0) --T(60,-20)--> ({v1[0]:.0f}, {v1[1]:.0f}, {v1[2]:.0f})"
                        f"     完全没动（第三列 × w=0 = 0）", fill=(60, 160, 90), font=FONT_SM)
    pen.text((16, 286), "→ 齐次坐标用一个数字 w 就区分了点和向量，课 4「点+点无意义」在这里有了代数解释",
             fill=(0, 0, 0), font=FONT_SM)

    img.save(OUT_DIR / "point_vs_vector_homo.png")


# ---------- 知识点 4：绕任意点旋转 ----------

TRI = [(0.0, 0.0), (34.0, 0.0), (0.0, 22.0)]
PIVOT = (75.0, 22.0)      # 绕这个点转（不是原点）


def render_rotate_around_point() -> None:
    """上行错误(绕原点) vs 下行正确(绕点 P)"""
    out_dir = OUT_DIR / "rotate_around_point"
    out_dir.mkdir(parents=True, exist_ok=True)

    for f in range(TOTAL):
        img = new_canvas(FW, FH)
        pen = ImageDraw.Draw(img)
        theta = 2 * math.pi * f / TOTAL

        rows = (
            (36, "上 ❌ 只用 R(θ)：绕原点转 → 形状被甩出去", (200, 60, 60), False),
            (98, "下 ✅ T(P)·R(θ)·T(-P)：绕点 P 自转", (60, 160, 90), True),
        )

        for cy, title, color, use_pivot in rows:
            cx = 60
            # 原形状（浅灰）
            pen.polygon([to_screen(p[0], p[1], cx, cy) for p in TRI], fill=(235, 235, 235))

            if use_pivot:
                M = rotate_around(PIVOT[0], PIVOT[1], theta)
            else:
                M = mat3_rotate(theta)

            pts = []
            for p in TRI:
                v = M @ homo_point(*p)
                pts.append(to_screen(v[0], v[1], cx, cy))
            pen.polygon(pts, fill=color)

            # 标出旋转中心
            if use_pivot:
                pc = to_screen(PIVOT[0], PIVOT[1], cx, cy)
                pen.ellipse([pc[0] - 3, pc[1] - 3, pc[0] + 3, pc[1] + 3], fill=(30, 30, 30))
                pen.text((pc[0] + 5, pc[1] - 4), "P", fill=(30, 30, 30), font=FONT_SM)
            else:
                oc = to_screen(0, 0, cx, cy)
                pen.ellipse([oc[0] - 3, oc[1] - 3, oc[0] + 3, oc[1] + 3], fill=(30, 30, 30))
                pen.text((oc[0] + 5, oc[1] - 4), "原点", fill=(30, 30, 30), font=FONT_SM)

        deg = math.degrees(theta)
        pen.text((6, 3), f"f{f:03d}  θ={deg:5.1f}°  P=({PIVOT[0]:.0f},{PIVOT[1]:.0f})",
                 fill=(0, 0, 0), font=FONT_SM)
        pen.text((6, 66), "上行：形状绕原点转 → 越转离得越远（错误示范）",
                 fill=(200, 60, 60), font=FONT_SM)
        pen.text((6, 76), "下行：形状绕 P 自转 → 中心始终钉在 P（正确做法）",
                 fill=(60, 160, 90), font=FONT_SM)
        pen.text((6, 112), "M = T(P) · R(θ) · T(-P)   ← 从右往左：先移到原点，转，再移回",
                 fill=(90, 90, 90), font=FONT_SM)

        img.save(out_dir / f"frame_{f:03d}.png")


# ---------- 知识点 4：层级变换（骨骼雏形） ----------

# 参数已按画布 320×120 校准：手臂摆到极限角度时仍全程可见
SHOULDER = (40.0, 52.0)
LEN_UPPER, LEN_FORE, LEN_HAND = 30.0, 24.0, 14.0


def render_hierarchy_demo() -> None:
    """父子层级：肩 → 肘 → 腕 → 指尖，父变换带动子变换"""
    out_dir = OUT_DIR / "hierarchy_demo"
    out_dir.mkdir(parents=True, exist_ok=True)

    for f in range(TOTAL):
        img = new_canvas(FW, FH)
        pen = ImageDraw.Draw(img)
        t = f / (TOTAL - 1)

        # 三段关节角（子关节角是相对父关节的）；幅度已收敛，保证不飞出画布
        th1 = math.radians(-10 + 25 * math.sin(2 * math.pi * t))
        th2 = math.radians(20 * math.sin(2 * math.pi * t + 0.9))
        th3 = math.radians(12 * math.sin(2 * math.pi * t + 1.8))

        # 层级链：子世界变换 = 父世界变换 × 子局部变换
        M_shoulder = mat3_translate(*SHOULDER)              # 根：肩的世界位置
        M_upper = M_shoulder @ mat3_rotate(th1)             # 上臂
        M_fore = M_upper @ mat3_translate(LEN_UPPER, 0) @ mat3_rotate(th2)   # 前臂
        M_hand = M_fore @ mat3_translate(LEN_FORE, 0) @ mat3_rotate(th3)     # 手

        # 各关节点位置
        shoulder = M_shoulder @ homo_point(0, 0)
        elbow = M_upper @ homo_point(LEN_UPPER, 0)
        wrist = M_fore @ homo_point(LEN_FORE, 0)
        tip = M_hand @ homo_point(LEN_HAND, 0)

        def sp(v):
            return to_screen(v[0], v[1], 0, FH - 6)

        # 画骨骼（父 → 子 依次变细）
        pen.line([sp(shoulder), sp(elbow)], fill=(60, 100, 200), width=6)
        pen.line([sp(elbow), sp(wrist)], fill=(90, 140, 220), width=4)
        pen.line([sp(wrist), sp(tip)], fill=(130, 175, 235), width=3)

        # 关节点
        for v, c in ((shoulder, (40, 60, 140)), (elbow, (50, 90, 180)),
                     (wrist, (70, 120, 200)), (tip, (120, 160, 220))):
            p = sp(v)
            pen.ellipse([p[0] - 3, p[1] - 3, p[0] + 3, p[1] + 3], fill=c)

        deg1, deg2, deg3 = math.degrees(th1), math.degrees(th2), math.degrees(th3)
        pen.text((6, 3), f"f{f:03d}  上臂 {deg1:6.1f}°  前臂 {deg2:6.1f}°  手 {deg3:6.1f}°",
                 fill=(0, 0, 0), font=FONT_SM)
        pen.text((6, 15), f"M_前臂 = M_上臂 · T({LEN_UPPER:.0f},0) · R(θ₂)   ← 父变换 × 子局部变换",
                 fill=(90, 90, 90), font=FONT_SM)
        pen.text((6, 104), "父动 → 子跟着动（肩一转，整条手臂都跟着转）= 骨骼动画的雏形",
                 fill=(90, 90, 90), font=FONT_SM)

        img.save(out_dir / f"frame_{f:03d}.png")


# ---------- main ----------

def main() -> None:
    print("=== 知识点 3：齐次坐标 ===")
    render_homogeneous_compare()
    print("2×2 vs 3×3 -> homogeneous_compare.png")
    T = mat3_translate(40.0, 20.0)
    p_out = T @ homo_point(10, 10)
    v_out = T @ homo_vector(10, 10)
    print(f"  点   (10,10,1) --T(40,20)--> ({p_out[0]:.0f}, {p_out[1]:.0f}, {p_out[2]:.0f})"
          f"   被平移了 ✓")
    print(f"  向量 (10,10,0) --T(40,20)--> ({v_out[0]:.0f}, {v_out[1]:.0f}, {v_out[2]:.0f})"
          f"      纹丝不动 ✓  ← w=0 让平移第 3 列乘 0")
    print()
    render_point_vs_vector_homo()
    print("点 vs 向量（齐次）-> point_vs_vector_homo.png")
    print()

    print("=== 知识点 4：绕任意点 + 层级变换 ===")
    render_rotate_around_point()
    print(f"绕任意点 -> rotate_around_point/ （{TOTAL} 帧，上行绕原点 vs 下行绕 P）")
    th = math.radians(90)
    M_wrong = mat3_rotate(th)
    M_right = rotate_around(PIVOT[0], PIVOT[1], th)
    pw = M_wrong @ homo_point(*TRI[1])
    pr = M_right @ homo_point(*TRI[1])
    print(f"  θ=90° 时顶点 (34,0)：")
    print(f"    只用 R(θ)      → ({pw[0]:6.1f}, {pw[1]:6.1f})   ← 被甩出去了")
    print(f"    T(P)·R·T(-P)  → ({pr[0]:6.1f}, {pr[1]:6.1f})   ← 绕 P 自转，中心不动")
    print()

    render_hierarchy_demo()
    print(f"层级变换 -> hierarchy_demo/ （{TOTAL} 帧，肩→肘→腕→指尖）")
    print()
    print("  层级链（θ 全为 0 时，验证父子关系）：")
    M_s = mat3_translate(*SHOULDER)
    M_u = M_s @ mat3_rotate(0)
    M_f = M_u @ mat3_translate(LEN_UPPER, 0) @ mat3_rotate(0)
    M_h = M_f @ mat3_translate(LEN_FORE, 0) @ mat3_rotate(0)
    for name, M, lp in (("肘", M_u, (LEN_UPPER, 0)), ("腕", M_f, (LEN_FORE, 0)),
                        ("指尖", M_h, (LEN_HAND, 0))):
        v = M @ homo_point(*lp)
        print(f"    {name:<3}局部({lp[0]:.0f},0) → 世界 ({v[0]:6.1f}, {v[1]:5.1f})")
    print()
    print("  -> 子的世界坐标 = 父的世界变换 × 子局部变换（矩阵连乘，顺序敏感）")


if __name__ == "__main__":
    main()
