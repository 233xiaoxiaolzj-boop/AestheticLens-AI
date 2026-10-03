"""
AestheticLens-AI 512x512 3D LUT 真实胶片纹理贴图生成器 (LUT Texture Generator)
遵循规范: 《系统技术设计文档 v2.0.0》§3.2 Metal MSL 3D LUT 着色规范
排布结构: 512x512 像素 2D 贴图，由 8x8 共 64 个 64x64 切片组成 (Tile 0..63 代表 Blue，x 代表 Red，y 代表 Green)
输出资产:
1. lut_identity.png (基准恒等 LUT)
2. lut_film_warm_01.png (落日余晖暖调胶片 / 经典复古胶片)
3. lut_clean_bright_02.png (纯净通透物产 / 美食静物日杂)
4. lut_cyber_teal_orange_03.png (赛博青橙夜景 / 电影级 Teal & Orange)
5. lut_mono_contrast_04.png (经典黑白光影 / 徕卡高反差黑白)
"""

import os
import math
from PIL import Image

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "client", "AestheticLens", "Resources", "luts")
os.makedirs(OUTPUT_DIR, exist_ok=True)

GRID_TILES = 8
TILE_SIZE = 64
IMAGE_SIZE = GRID_TILES * TILE_SIZE # 512


def clamp(val, min_v=0.0, max_v=1.0):
    return max(min_v, min(max_v, val))


def s_curve(x, contrast=1.2):
    """S 型对比度曲线"""
    shifted = x - 0.5
    val = 0.5 + shifted * contrast
    return clamp(val)


def transform_identity(r, g, b):
    return r, g, b


def transform_film_warm(r, g, b):
    """落日余晖暖调胶片: 高光微暖金黄、暗部柔和偏青、肤色保护、胶片褪色灰阶"""
    # 胶片黑位抬升 (Faded shadow)
    r = 0.04 + 0.96 * r
    g = 0.04 + 0.94 * g
    b = 0.06 + 0.90 * b

    # 暖色渲染: 红色微提，高光黄色增强
    r = clamp(r * 1.08)
    g = clamp(g * 1.02)
    b = clamp(b * 0.92)

    # 轻微 S 曲线增加质感
    r = s_curve(r, 1.15)
    g = s_curve(g, 1.10)
    b = s_curve(b, 1.05)
    return r, g, b


def transform_clean_bright(r, g, b):
    """纯净通透物产/美食: 高通透感、白色不偏色、纯净鲜艳"""
    # 线性提亮微调
    r = clamp(r ** 0.92)
    g = clamp(g ** 0.92)
    b = clamp(b ** 0.94)

    # 饱和度适度增强 (自然饱和)
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    r = clamp(lum + (r - lum) * 1.25)
    g = clamp(lum + (g - lum) * 1.22)
    b = clamp(lum + (b - lum) * 1.15)

    r = s_curve(r, 1.12)
    g = s_curve(g, 1.12)
    b = s_curve(b, 1.10)
    return r, g, b


def transform_cyber_teal_orange(r, g, b):
    """赛博青橙夜景: 电影级 Teal & Orange 强烈冷暖反差分离"""
    lum = 0.299 * r + 0.587 * g + 0.114 * b

    # 亮部偏橙红 (Orange Highlights)
    if lum > 0.4:
        factor = (lum - 0.4) / 0.6
        r = clamp(r + 0.15 * factor)
        g = clamp(g + 0.05 * factor)
        b = clamp(b - 0.15 * factor)
    
    # 暗部偏青蓝 (Teal Shadows)
    if lum < 0.6:
        factor = (0.6 - lum) / 0.6
        r = clamp(r - 0.10 * factor)
        g = clamp(g + 0.08 * factor)
        b = clamp(b + 0.20 * factor)

    # 强烈高反差
    r = s_curve(r, 1.35)
    g = s_curve(g, 1.30)
    b = s_curve(b, 1.35)
    return r, g, b


def transform_mono_contrast(r, g, b):
    """经典黑白光影: 徕卡高反差街头纪实黑白"""
    # 感知亮度 YUV 亮度公式
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    # 强 S 曲线
    mono = s_curve(lum, 1.45)
    return mono, mono, mono


LUT_CONFIGS = [
    ("lut_identity.png", transform_identity, "恒等基准 3D LUT"),
    ("lut_film_warm_01.png", transform_film_warm, "落日余晖暖调胶片 (Classic Chrome)"),
    ("lut_clean_bright_02.png", transform_clean_bright, "纯净通透物产 (Clean Food)"),
    ("lut_cyber_teal_orange_03.png", transform_cyber_teal_orange, "赛博青橙夜景 (Teal & Orange)"),
    ("lut_mono_contrast_04.png", transform_mono_contrast, "经典黑白光影 (Mono High Contrast)")
]


def generate_single_lut(filename, transform_func, description):
    img = Image.new("RGB", (IMAGE_SIZE, IMAGE_SIZE))
    pixels = img.load()

    # 遍历 64 个切片 (Tile 0..63)
    for tile_idx in range(64):
        tile_x = tile_idx % GRID_TILES
        tile_y = tile_idx // GRID_TILES

        base_x = tile_x * TILE_SIZE
        base_y = tile_y * TILE_SIZE

        # B 分量由 tile_idx 确定 (0.0 .. 1.0)
        b_norm = tile_idx / 63.0

        for y in range(TILE_SIZE):
            # G 分量由切片内 y 确定
            g_norm = y / 63.0
            for x in range(TILE_SIZE):
                # R 分量由切片内 x 确定
                r_norm = x / 63.0

                # 应用调色变换
                tr, tg, tb = transform_func(r_norm, g_norm, b_norm)

                pixel_r = int(clamp(tr) * 255.0 + 0.5)
                pixel_g = int(clamp(tg) * 255.0 + 0.5)
                pixel_b = int(clamp(tb) * 255.0 + 0.5)

                pixels[base_x + x, base_y + y] = (pixel_r, pixel_g, pixel_b)

    out_path = os.path.join(OUTPUT_DIR, filename)
    img.save(out_path, "PNG")
    file_size_kb = os.path.getsize(out_path) / 1024.0
    print(f"[OK] Generated {filename} ({description}): {file_size_kb:.1f} KB -> {out_path}")


def main():
    print(f"Starting 512x512 3D LUT texture generation for Metal rendering pipeline...")
    for filename, func, desc in LUT_CONFIGS:
        generate_single_lut(filename, func, desc)
    print(f"[SUCCESS] All 5 LUT textures generated successfully in: {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
