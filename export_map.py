#!/usr/bin/env python3
"""
export_map.py
将游戏世界地图渲染为 PNG 文件（与游戏内地图完全一致）
  map_export.png      — 深度等高线 + 岛屿标记
  map_export_zones.png — 在上版本基础上叠加海域分区色块+名称标注
输出目录: fish-repo/
"""

import math
import re
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import os

# ============================================================
# 世界范围（与 DEPTH_MAP_BOUNDS 一致）
# ============================================================
WORLD = dict(minX=-9000, maxX=9000, minY=-8000, maxY=7000)
WORLD_W = WORLD["maxX"] - WORLD["minX"]   # 18000
WORLD_H = WORLD["maxY"] - WORLD["minY"]   # 15000

# 输出分辨率：保持比例，宽度 2400px
OUT_W = 2400
OUT_H = round(OUT_W * WORLD_H / WORLD_W)   # 2000

# ============================================================
# 噪声参数（与 main.lua 完全一致）
# ============================================================
CONTOUR_NOISE_SCALE = 0.0008
BUMP_RADIUS_MULT    = 3.0
BUMP_STRENGTH       = 0.38

# 岛屿数据（从 island_registry.lua 提取，仅需 x, y, w, h）
ISLANDS = [
    dict(x= 1340, y=-6320, w= 128, h= 112),
    dict(x=-4020, y=-5260, w= 608, h= 448),
    dict(x= 4940, y=-4720, w= 528, h= 400),
    dict(x= 1520, y=-3380, w= 288, h= 192),
    dict(x= -740, y=-2680, w= 624, h= 384),
    dict(x=-3380, y=-1660, w= 368, h= 288),
    dict(x= 3760, y=-1520, w= 400, h= 336),
    dict(x= 6400, y=-1220, w= 224, h= 192),
    dict(x=-6340, y= -940, w= 400, h= 272),
    dict(x= -850, y=  -60, w= 552, h= 472),
    dict(x= 3720, y= 1420, w= 448, h= 320),
    dict(x=-2060, y= 1760, w= 256, h= 272),
    dict(x=-6340, y= 1860, w= 320, h= 272),
    dict(x= 7100, y= 1880, w= 592, h= 320),
    dict(x= -560, y= 2520, w= 285, h= 261),
    dict(x= 4620, y= 3820, w= 512, h= 304),
    dict(x=-7340, y= 5080, w= 256, h= 256),
]

# 海沟控制点
TRENCH_POINTS = [
    dict(x=-6000, y=5200, rx=1800, ry=600,  strength=0.52),
    dict(x=-3800, y=5600, rx=2000, ry=700,  strength=0.58),
    dict(x=-1200, y=5900, rx=2000, ry=650,  strength=0.56),
    dict(x= 1400, y=5700, rx=1900, ry=600,  strength=0.55),
    dict(x= 3600, y=5300, rx=1800, ry=550,  strength=0.53),
    dict(x= 5800, y=4800, rx=1700, ry=500,  strength=0.50),
]

# 等高线梯度色带（与 CONTOUR_GRADIENT 一致）
CONTOUR_GRADIENT = [
    dict(lo=0.00, hi=0.12, r=  5, g= 12, b= 45),
    dict(lo=0.12, hi=0.30, r= 15, g= 40, b= 90),
    dict(lo=0.30, hi=0.42, r= 25, g= 60, b=120),
    dict(lo=0.42, hi=0.54, r= 38, g= 85, b=150),
    dict(lo=0.54, hi=0.66, r= 50, g=110, b=175),
    dict(lo=0.66, hi=1.01, r= 65, g=140, b=200),
]

# 等高线阈值（绘制线条）
CONTOUR_THRESHOLDS = [0.12, 0.30, 0.42, 0.54, 0.66]

# 深度分区名称（标注用）
DEPTH_BANDS = [
    dict(lo=0.00, hi=0.12, name="超深区"),
    dict(lo=0.12, hi=0.30, name="深海区"),
    dict(lo=0.30, hi=0.42, name="次深区"),
    dict(lo=0.42, hi=0.54, name="中层区"),
    dict(lo=0.54, hi=0.66, name="浅层区"),
    dict(lo=0.66, hi=1.01, name="近岸区"),
]

# ============================================================
# 噪声函数（移植自 Lua，逐位等价）
# ============================================================
def _noise_hash2(ix, iy):
    # Lua 使用 64 位整数；Python 用相同算法 + 截断到 31 位
    n = (ix * 374761393 + iy * 668265263) & 0xFFFFFFFFFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFFFFFFFFFF
    return (n & 0x7fffffff) / 0x7fffffff

def _smoothstep(t):
    return t * t * (3.0 - 2.0 * t)

def _vnoise(x, y):
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    sx, sy = _smoothstep(fx), _smoothstep(fy)
    v00 = _noise_hash2(ix,     iy)
    v10 = _noise_hash2(ix + 1, iy)
    v01 = _noise_hash2(ix,     iy + 1)
    v11 = _noise_hash2(ix + 1, iy + 1)
    a = v00 + (v10 - v00) * sx
    b = v01 + (v11 - v01) * sx
    return a + (b - a) * sy

# 预计算岛屿高斯隆起参数
def build_island_bumps():
    bumps = []
    for isl in ISLANDS:
        sz = max(isl["w"], isl["h"])
        radius = sz * BUMP_RADIUS_MULT
        bumps.append(dict(
            x=isl["x"], y=isl["y"],
            r2inv=1.0 / (radius * radius),
            strength=BUMP_STRENGTH,
        ))
    return bumps

ISLAND_BUMPS = build_island_bumps()

def contour_fbm(wx, wy):
    x, y = wx * CONTOUR_NOISE_SCALE, wy * CONTOUR_NOISE_SCALE
    h = (_vnoise(x, y) * 0.5
       + _vnoise(x * 2.03, y * 2.03) * 0.3
       + _vnoise(x * 4.07, y * 4.07) * 0.2)

    for b in ISLAND_BUMPS:
        dx = wx - b["x"]
        dy = wy - b["y"]
        h += b["strength"] * math.exp(-(dx * dx + dy * dy) * b["r2inv"])

    for t in TRENCH_POINTS:
        dx = (wx - t["x"]) / t["rx"]
        dy = (wy - t["y"]) / t["ry"]
        h -= t["strength"] * math.exp(-(dx * dx + dy * dy))

    return max(0.0, min(h, 1.0))

# ============================================================
# 颜色映射
# ============================================================
def height_to_color(h):
    bands = CONTOUR_GRADIENT
    if h <= bands[0]["lo"]:
        b = bands[0]
        return (b["r"], b["g"], b["b"])
    for i in range(len(bands) - 1):
        b1, b2 = bands[i], bands[i + 1]
        if b1["lo"] <= h < b2["hi"]:
            mid = b1["hi"]
            if h < mid:
                t = (h - b1["lo"]) / (mid - b1["lo"]) * 0.5
            else:
                t = 0.5 + (h - mid) / (b2["hi"] - mid) * 0.5
            r = round(b1["r"] + (b2["r"] - b1["r"]) * t)
            g = round(b1["g"] + (b2["g"] - b1["g"]) * t)
            b = round(b1["b"] + (b2["b"] - b1["b"]) * t)
            return (r, g, b)
    bl = bands[-1]
    return (bl["r"], bl["g"], bl["b"])

# ============================================================
# 世界坐标 ↔ 图像坐标转换
# ============================================================
def w2img(wx, wy):
    px = (wx - WORLD["minX"]) / WORLD_W * OUT_W
    py = (wy - WORLD["minY"]) / WORLD_H * OUT_H
    return px, py

# ============================================================
# 主渲染流程
# ============================================================
def main():
    print(f"渲染世界地图 {OUT_W}x{OUT_H} ...")

    # ── 1. 采样噪声网格 ──────────────────────────────────────
    GRID_N = 300   # 采样分辨率
    print(f"  采样 {GRID_N}x{GRID_N} 噪声网格...")
    grid = np.zeros((GRID_N + 1, GRID_N + 1), dtype=np.float32)
    step_x = WORLD_W / GRID_N
    step_y = WORLD_H / GRID_N
    for gy in range(GRID_N + 1):
        if gy % 50 == 0:
            print(f"    {gy}/{GRID_N+1}")
        wy = WORLD["minY"] + gy * step_y
        for gx in range(GRID_N + 1):
            wx = WORLD["minX"] + gx * step_x
            grid[gy, gx] = contour_fbm(wx, wy)

    # ── 2. 生成背景颜色图 ────────────────────────────────────
    print("  生成颜色背景...")
    # 在低分辨率下颜色采样，再上采样
    color_arr = np.zeros((GRID_N, GRID_N, 3), dtype=np.uint8)
    for gy in range(GRID_N):
        for gx in range(GRID_N):
            h = float(grid[gy, gx])
            r, g, b = height_to_color(h)
            color_arr[gy, gx] = [r, g, b]

    # 使用 PIL 放大到输出分辨率
    color_img = Image.fromarray(color_arr, "RGB")
    color_img = color_img.resize((OUT_W, OUT_H), Image.BICUBIC)
    img = color_img.copy()
    draw = ImageDraw.Draw(img)

    # ── 3. Marching Squares 等高线 ───────────────────────────
    print("  绘制等高线...")
    def grid_w2img(gx, gy):
        wx = WORLD["minX"] + gx * step_x
        wy = WORLD["minY"] + gy * step_y
        return w2img(wx, wy)

    for iso in CONTOUR_THRESHOLDS:
        for gy in range(GRID_N):
            for gx in range(GRID_N):
                v00 = float(grid[gy,   gx])
                v10 = float(grid[gy,   gx+1])
                v01 = float(grid[gy+1, gx])
                v11 = float(grid[gy+1, gx+1])

                # 像素坐标（格子四角）
                px0, py0 = grid_w2img(gx,   gy)
                px1, py1 = grid_w2img(gx+1, gy)
                px2, py2 = grid_w2img(gx,   gy+1)
                px3, py3 = grid_w2img(gx+1, gy+1)

                # 找到穿越等值线的边
                def lerp_pt(ax, ay, bx, by, va, vb):
                    if abs(va - vb) < 1e-9: t = 0.5
                    else: t = (iso - va) / (vb - va)
                    t = max(0.0, min(1.0, t))
                    return ax + t * (bx - ax), ay + t * (by - ay)

                # 上/下/左/右边交点
                segs = []
                c00 = v00 >= iso
                c10 = v10 >= iso
                c01 = v01 >= iso
                c11 = v11 >= iso

                # 四边是否穿越
                top    = c00 != c10  # 上边（gy行）
                right  = c10 != c11  # 右边
                bottom = c01 != c11  # 下边（gy+1行）
                left   = c00 != c01  # 左边

                pts = {}
                if top:    pts["T"] = lerp_pt(px0,py0,px1,py1,v00,v10)
                if right:  pts["R"] = lerp_pt(px1,py0,px3,py3,v10,v11)
                if bottom: pts["B"] = lerp_pt(px2,py2,px3,py3,v01,v11)
                if left:   pts["L"] = lerp_pt(px0,py0,px2,py2,v00,v01)

                keys = list(pts.keys())
                if len(keys) == 2:
                    segs.append((pts[keys[0]], pts[keys[1]]))
                elif len(keys) == 4:
                    # 鞍点：用中心值决定连接方式
                    mid = (v00 + v10 + v01 + v11) * 0.25
                    if (mid >= iso) == c00:
                        segs.append((pts["T"], pts["L"]))
                        segs.append((pts["B"], pts["R"]))
                    else:
                        segs.append((pts["T"], pts["R"]))
                        segs.append((pts["B"], pts["L"]))

                for (ax, ay), (bx, by) in segs:
                    draw.line([(ax, ay), (bx, by)],
                              fill=(180, 210, 240, 200), width=1)

    # ── 4. 岛屿轮廓 + 标注 ──────────────────────────────────
    print("  绘制岛屿...")
    # 绘制岛屿中心点和尺寸标注（实际游戏中绘制的是PNG精灵，这里用圆形代替）
    for i, isl in enumerate(ISLANDS):
        cx, cy = w2img(isl["x"], isl["y"])
        rw = isl["w"] / WORLD_W * OUT_W * 0.5
        rh = isl["h"] / WORLD_H * OUT_H * 0.5
        # 绿色椭圆（岛屿范围）
        draw.ellipse(
            [cx - rw, cy - rh, cx + rw, cy + rh],
            outline=(100, 180, 80, 220),
            width=2
        )
        # 中心点
        draw.ellipse([cx-4, cy-4, cx+4, cy+4],
                     fill=(200, 220, 120))
        # 岛屿编号
        label = f"#{i+1:02d}"
        draw.text((cx + rw + 4, cy - 8), label,
                  fill=(220, 230, 150))

    # ── 5. 坐标网格 ──────────────────────────────────────────
    print("  绘制坐标网格...")
    GRID_STEP = 2000
    # 竖线
    for wx in range(
        math.ceil(WORLD["minX"] / GRID_STEP) * GRID_STEP,
        WORLD["maxX"] + 1, GRID_STEP
    ):
        px, _ = w2img(wx, 0)
        draw.line([(px, 0), (px, OUT_H)],
                  fill=(255, 255, 255, 25), width=1)
        draw.text((px + 3, 4), f"{wx}", fill=(200, 220, 255, 180))
    # 横线
    for wy in range(
        math.ceil(WORLD["minY"] / GRID_STEP) * GRID_STEP,
        WORLD["maxY"] + 1, GRID_STEP
    ):
        _, py = w2img(0, wy)
        draw.line([(0, py), (OUT_W, py)],
                  fill=(255, 255, 255, 25), width=1)
        draw.text((4, py + 3), f"{wy}", fill=(200, 220, 255, 180))

    # ── 6. 深度标注 ──────────────────────────────────────────
    # 在特征区域打上深度带名称
    depth_labels = [
        dict(wx= 5500, wy= 6000, band="超深区"),
        dict(wx=-5000, wy= 4000, band="深海区"),
        dict(wx= 7000, wy= -200, band="次深区"),
        dict(wx=-7500, wy=-3000, band="中层区"),
        dict(wx= 3000, wy=-5500, band="浅层区"),
        dict(wx=  500, wy=-6500, band="近岸区"),
    ]
    for lb in depth_labels:
        px, py = w2img(lb["wx"], lb["wy"])
        if 0 <= px <= OUT_W and 0 <= py <= OUT_H:
            draw.text((px, py), lb["band"],
                      fill=(255, 255, 255, 160))

    # ── 7. 海域区域标注（参考用） ────────────────────────────
    zone_labels = [
        dict(wx= 0,    wy= 5500,  name="南部"),
        dict(wx=-6000, wy= 3000,  name="西侧"),
        dict(wx= 6000, wy= 3000,  name="东侧"),
        dict(wx= 0,    wy=-6000,  name="北部"),
        dict(wx= 0,    wy= 0,     name="中央"),
    ]
    for lb in zone_labels:
        px, py = w2img(lb["wx"], lb["wy"])
        if 0 <= px <= OUT_W and 0 <= py <= OUT_H:
            draw.text((px, py), lb["name"],
                      fill=(255, 240, 180, 140))

    # ── 8. 图例 ──────────────────────────────────────────────
    legend_x, legend_y = OUT_W - 160, 20
    for bd in CONTOUR_GRADIENT:
        col = (bd["r"], bd["g"], bd["b"])
        # 需要找名字
        name = next(
            (d["name"] for d in DEPTH_BANDS
             if abs(d["lo"] - bd["lo"]) < 0.01), ""
        )
        draw.rectangle(
            [legend_x, legend_y, legend_x + 18, legend_y + 14],
            fill=col
        )
        draw.text((legend_x + 22, legend_y), name,
                  fill=(230, 240, 255))
        legend_y += 18

    # ── 9. 保存基础版 ────────────────────────────────────────
    out_dir = "/workspace/fish-repo"
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "map_export.png")
    img.save(out_path, "PNG")
    print(f"\n导出完成: {out_path}  ({OUT_W}x{OUT_H})")

    # ── 10. 区域分区叠加版 ───────────────────────────────────
    out_zones = export_zones(img.copy(), out_dir)
    print(f"导出完成: {out_zones}  ({OUT_W}x{OUT_H})")
    return out_path


# ============================================================
# 区域分区叠加
# ============================================================

# ZONE_TABLE R值 → (名称, 叠加色 RGBA)
# 颜色参考游戏内海水颜色，加半透明
ZONE_COLORS = {
      0: ("外海",   (  29,  88, 149, 80)),
     30: ("外海",   (  29,  88, 149, 80)),
     50: ("热带海", (  40, 150, 172, 90)),
     70: ("热带海", (  40, 141, 172, 90)),
     90: ("沙漠海", (  45,  95, 117, 90)),
    110: ("沙漠海", (  45,  90, 117, 90)),
    130: ("寒带海", (  73, 122, 175, 90)),
    150: ("寒带海", (  77, 114, 179, 90)),
    170: ("寒带海", (  89, 125, 187, 90)),
    190: ("浅海",   (  57, 125, 164, 80)),
    210: ("外海",   (  29,  88, 149, 80)),
}

# 区域代表色（用于图例，合并同名区域取最深色）
ZONE_LEGEND = [
    ("浅海",   ( 57, 125, 164, 80)),
    ("热带海", ( 40, 150, 172, 90)),
    ("沙漠海", ( 45,  95, 117, 90)),
    ("寒带海", ( 73, 122, 175, 90)),
    ("外海",   ( 29,  88, 149, 80)),
]

def load_zone_data():
    """解析 zone_partition_data.lua，返回 numpy 数组 (1200,1200) uint8"""
    path = "/workspace/scripts/zone_partition_data.lua"
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    m = re.search(r'M\.data\s*=\s*"(.*)"', content, re.DOTALL)
    if not m:
        raise RuntimeError("zone_partition_data.lua 解析失败")
    raw = m.group(1)
    data = raw.encode('raw_unicode_escape').decode('unicode_escape').encode('latin-1')
    return np.frombuffer(data, dtype=np.uint8).reshape(1200, 1200)


def export_zones(base_img, out_dir):
    """在 base_img 上叠加海域分区色块，输出 map_export_zones.png"""
    print("\n加载区域分区数据...")
    zone_grid = load_zone_data()   # shape (1200,1200)

    # zone 图参数（与 Lua MapSampler.Register 一致）
    Z_W, Z_H = 1200, 1200
    Z_SCALE   = 20          # 每像素 = 20 世界单位
    Z_CENTER  = (0, 0)      # 图片中心对应世界 (0,0)
    z_orig_x  = Z_CENTER[0] - (Z_W / 2) * Z_SCALE   # -12000
    z_orig_y  = Z_CENTER[1] - (Z_H / 2) * Z_SCALE   # -12000

    print("  绘制分区色块...")
    # 构建 RGBA 叠加层（与输出图同尺寸）
    overlay = Image.new("RGBA", (OUT_W, OUT_H), (0, 0, 0, 0))
    ov_arr  = np.array(overlay, dtype=np.uint8)  # (H, W, 4)

    # 对每个像素反推世界坐标 → 查 zone_grid
    # 用向量化操作加速
    ys = np.arange(OUT_H, dtype=np.float32)
    xs = np.arange(OUT_W, dtype=np.float32)
    # 世界坐标
    wx_row = WORLD["minX"] + xs / OUT_W * WORLD_W   # (OUT_W,)
    wy_col = WORLD["minY"] + ys / OUT_H * WORLD_H   # (OUT_H,)

    # zone 像素坐标（向量化）
    zpx_row = ((wx_row - z_orig_x) / Z_SCALE).astype(np.int32)  # (OUT_W,)
    zpy_col = ((wy_col - z_orig_y) / Z_SCALE).astype(np.int32)  # (OUT_H,)

    zpx_row = np.clip(zpx_row, 0, Z_W - 1)
    zpy_col = np.clip(zpy_col, 0, Z_H - 1)

    # 逐行批量写入
    for iy in range(OUT_H):
        if iy % 400 == 0:
            print(f"    {iy}/{OUT_H}")
        zpy = zpy_col[iy]
        zone_row = zone_grid[zpy, zpx_row]   # (OUT_W,) zone R值
        for r_val, (_, color) in ZONE_COLORS.items():
            mask = (zone_row == r_val)
            ov_arr[iy, mask, 0] = color[0]
            ov_arr[iy, mask, 1] = color[1]
            ov_arr[iy, mask, 2] = color[2]
            ov_arr[iy, mask, 3] = color[3]

    overlay = Image.fromarray(ov_arr, "RGBA")

    # 合成到底图
    result = base_img.convert("RGBA")
    result = Image.alpha_composite(result, overlay)

    # 绘制分区边界线（相邻像素 R 值不同则画线）
    print("  绘制分区边界...")
    draw = ImageDraw.Draw(result)
    BORDER_STEP = 4   # 每隔几像素检查一次，加速
    for iy in range(0, OUT_H - BORDER_STEP, BORDER_STEP):
        zpy_cur  = zpy_col[iy]
        zpy_next = zpy_col[min(iy + BORDER_STEP, OUT_H - 1)]
        for ix in range(0, OUT_W - BORDER_STEP, BORDER_STEP):
            zpx_cur  = zpx_row[ix]
            zpx_next = zpx_row[min(ix + BORDER_STEP, OUT_W - 1)]
            v_c = int(zone_grid[zpy_cur,  zpx_cur])
            v_r = int(zone_grid[zpy_cur,  zpx_next])
            v_d = int(zone_grid[zpy_next, zpx_cur])
            if v_c != v_r or v_c != v_d:
                draw.point((ix, iy), fill=(255, 255, 255, 120))

    # 区域名称标注（找每个区域重心）
    print("  计算区域重心标注...")
    zone_centers = {}
    for r_val, (name, _) in ZONE_COLORS.items():
        # 找所有属于该 R 值的输出像素坐标（采样加速）
        sample_step = 8
        ys_s = np.arange(0, OUT_H, sample_step)
        xs_s = np.arange(0, OUT_W, sample_step)
        zpy_s = zpy_col[ys_s]
        zpx_s = zpx_row[xs_s]
        sub = zone_grid[np.ix_(zpy_s, zpx_s)]  # (len_y, len_x)
        mask = (sub == r_val)
        if mask.any():
            rows, cols = np.where(mask)
            cy = int(ys_s[rows].mean())
            cx = int(xs_s[cols].mean())
            # 同名区域可能多块，只取第一个重心
            if name not in zone_centers:
                zone_centers[name] = []
            zone_centers[name].append((cx, cy))

    draw2 = ImageDraw.Draw(result)
    for name, pts in zone_centers.items():
        for (cx, cy) in pts:
            # 阴影
            draw2.text((cx + 1, cy + 1), name, fill=(0, 0, 0, 180))
            draw2.text((cx,     cy),     name, fill=(255, 255, 255, 230))

    # 图例（右上角，覆盖旧图例位置下方）
    lx, ly = OUT_W - 160, 140
    for name, color in ZONE_LEGEND:
        draw2.rectangle([lx, ly, lx + 18, ly + 14],
                        fill=(color[0], color[1], color[2]))
        draw2.text((lx + 22, ly), name, fill=(230, 240, 255))
        ly += 18

    out_path = os.path.join(out_dir, "map_export_zones.png")
    result.convert("RGB").save(out_path, "PNG")
    return out_path


if __name__ == "__main__":
    main()
