import os
import math
from PIL import Image

CLIENT_LUT_DIR = r"F:\test1\1\AI camera\code\client\AestheticLens\Resources\luts"
STATIC_LUT_DIR = r"F:\test1\1\AI camera\code\static\luts"
POC_PATH = r"F:\test1\1\AI camera\code\poc\generate_lut_textures.py"
os.makedirs(CLIENT_LUT_DIR, exist_ok=True)
os.makedirs(STATIC_LUT_DIR, exist_ok=True)

GRID_TILES = 8
TILE_SIZE = 64
IMAGE_SIZE = GRID_TILES * TILE_SIZE # 512


def clamp(val, min_v=0.0, max_v=1.0):
    return max(min_v, min(max_v, val))


def rgb_to_hsl(r, g, b):
    max_c = max(r, g, b)
    min_c = min(r, g, b)
    delta = max_c - min_c
    
    l = (max_c + min_c) / 2.0
    if delta == 0:
        h = 0.0
        s = 0.0
    else:
        s = delta / (1.0 - abs(2.0 * l - 1.0))
        if max_c == r:
            h = ((g - b) / delta) % 6.0
        elif max_c == g:
            h = (b - r) / delta + 2.0
        else:
            h = (r - g) / delta + 4.0
        h = h * 60.0
        if h < 0:
            h += 360.0
    return h, s, l


def hsl_to_rgb(h, s, l):
    c = (1.0 - abs(2.0 * l - 1.0)) * s
    x = c * (1.0 - abs((h / 60.0) % 2.0 - 1.0))
    m = l - c / 2.0
    
    if 0 <= h < 60:
        rp, gp, bp = c, x, 0
    elif 60 <= h < 120:
        rp, gp, bp = x, c, 0
    elif 120 <= h < 180:
        rp, gp, bp = 0, c, x
    elif 180 <= h < 240:
        rp, gp, bp = 0, x, c
    elif 240 <= h < 300:
        rp, gp, bp = x, 0, c
    else:
        rp, gp, bp = c, 0, x
    return clamp(rp + m), clamp(gp + m), clamp(bp + m)


def film_contrast(x, slope=1.15, toe=0.05, shoulder=0.95):
    """电影胶片非线性特征曲线 (平滑压高光、缓坡抬暗部)"""
    if x <= 0.0: return toe
    if x >= 1.0: return shoulder
    val = 1.0 / (1.0 + math.exp(-slope * 5.0 * (x - 0.5)))
    return toe + (shoulder - toe) * val


# 1. 基准自然原画
def transform_identity(r, g, b):
    return r, g, b


# 2. 【王家卫·暖金电影感】
def transform_film_warm(r, g, b):
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    
    # 胶片黑位抬升
    r = 0.05 + 0.94 * r
    g = 0.04 + 0.93 * g
    b = 0.06 + 0.90 * b
    
    # 高光大度压制
    if lum > 0.6:
        roll_off = (lum - 0.6) / 0.4
        r -= 0.08 * roll_off
        g -= 0.09 * roll_off
        b -= 0.12 * roll_off
        
    # 色温暖偏置与微洋红
    r = clamp(r * 1.09)
    g = clamp(g * 1.02)
    b = clamp(b * 0.91)
    
    # 暗部微青冷灰分离
    if lum < 0.45:
        shadow_factor = (0.45 - lum) / 0.45
        b += 0.05 * shadow_factor
        g += 0.02 * shadow_factor
        r -= 0.03 * shadow_factor
        
    # 柔和电影 S 曲线
    r = film_contrast(r, slope=1.12, toe=0.04, shoulder=0.96)
    g = film_contrast(g, slope=1.10, toe=0.03, shoulder=0.95)
    b = film_contrast(b, slope=1.08, toe=0.05, shoulder=0.94)
    return r, g, b


# 3. 【富士 NC·清透冷萃胶片】 (冷白皮与高级橄榄绿)
def transform_fuji_nc(r, g, b):
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    h, s, l = rgb_to_hsl(r, g, b)
    
    r = clamp(r ** 0.94)
    g = clamp(g ** 0.94)
    b = clamp(b ** 0.92)
    
    # 富士经典青绿白平衡微偏 (色温-14, 色调-6)
    r = clamp(r * 0.96)
    g = clamp(g * 1.03)
    b = clamp(b * 1.05)
    
    # HSL 肤色分离保护: 亚洲人肤色范围一般在 Hue 12° ~ 48°
    is_skin = (12.0 <= h <= 48.0) and (s > 0.10)
    if is_skin:
        r = clamp(r * 1.04)
        g = clamp(g * 1.02)
        b = clamp(b * 1.01)
    else:
        if lum < 0.5:
            olive_factor = (0.5 - lum) / 0.5
            g += 0.04 * olive_factor
            b += 0.03 * olive_factor
            r -= 0.04 * olive_factor
            
    if lum > 0.7:
        r -= 0.05 * ((lum - 0.7) / 0.3)
        g -= 0.04 * ((lum - 0.7) / 0.3)
        b -= 0.02 * ((lum - 0.7) / 0.3)
        
    return clamp(r), clamp(g), clamp(b)


# 4. 【好莱坞·赛博青橙夜景】 (Teal & Orange 极致冷暖)
def transform_cyber_teal_orange(r, g, b):
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    
    if lum > 0.35:
        factor = (lum - 0.35) / 0.65
        r = clamp(r + 0.18 * factor)
        g = clamp(g + 0.06 * factor)
        b = clamp(b - 0.20 * factor)
    
    if lum < 0.65:
        factor = (0.65 - lum) / 0.65
        r = clamp(r - 0.15 * factor)
        g = clamp(g + 0.09 * factor)
        b = clamp(b + 0.24 * factor)
        
    r = film_contrast(r, slope=1.28, toe=0.01, shoulder=0.98)
    g = film_contrast(g, slope=1.25, toe=0.01, shoulder=0.97)
    b = film_contrast(b, slope=1.30, toe=0.02, shoulder=0.96)
    return r, g, b


# 5. 【法式复古·莫兰迪奶咖】 (低反差奶油杏粉)
def transform_vintage_morandi(r, g, b):
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    
    r = 0.08 + 0.88 * r
    g = 0.07 + 0.88 * g
    b = 0.06 + 0.86 * b
    
    if lum > 0.5:
        roll_off = (lum - 0.5) / 0.5
        r -= 0.10 * roll_off
        g -= 0.10 * roll_off
        b -= 0.12 * roll_off
        
    r = clamp(r * 1.06)
    g = clamp(g * 1.01)
    b = clamp(b * 0.94)
    
    h, s, l = rgb_to_hsl(r, g, b)
    s = clamp(s * 0.82)
    r, g, b = hsl_to_rgb(h, s, l)
    
    r = film_contrast(r, slope=0.98, toe=0.06, shoulder=0.92)
    g = film_contrast(g, slope=0.98, toe=0.06, shoulder=0.92)
    b = film_contrast(b, slope=0.96, toe=0.05, shoulder=0.90)
    return r, g, b


# 6. 【经典纪实·徕卡高反差黑白】 (纯粹光影张力)
def transform_leica_mono(r, g, b):
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    mono = film_contrast(lum, slope=1.40, toe=0.0, shoulder=1.0)
    return mono, mono, mono


LUT_CONFIGS = [
    ("lut_identity.png", transform_identity, "自然原画 (Natural RAW)"),
    ("lut_film_warm_01.png", transform_film_warm, "王家卫·暖金电影感 (Warm Cinematic)"),
    ("lut_clean_bright_02.png", transform_fuji_nc, "富士NC·清透冷萃 (Fuji Clean Neg)"),
    ("lut_cyber_teal_orange_03.png", transform_cyber_teal_orange, "好莱坞·赛博青橙 (Teal & Orange)"),
    ("lut_mono_contrast_04.png", transform_vintage_morandi, "法式复古·莫兰迪奶咖 (Vintage Morandi)"),
    ("lut_mono_contrast_05.png", transform_leica_mono, "经典纪实·徕卡高反差黑白 (Leica Monochrome)")
]


def generate_single_lut(filename, transform_func, description):
    img = Image.new("RGB", (IMAGE_SIZE, IMAGE_SIZE))
    pixels = img.load()

    for tile_idx in range(64):
        tile_x = tile_idx % GRID_TILES
        tile_y = tile_idx // GRID_TILES

        base_x = tile_x * TILE_SIZE
        base_y = tile_y * TILE_SIZE

        b_norm = tile_idx / 63.0

        for y in range(TILE_SIZE):
            g_norm = y / 63.0
            for x in range(TILE_SIZE):
                r_norm = x / 63.0

                tr, tg, tb = transform_func(r_norm, g_norm, b_norm)

                pixel_r = int(clamp(tr) * 255.0 + 0.5)
                pixel_g = int(clamp(tg) * 255.0 + 0.5)
                pixel_b = int(clamp(tb) * 255.0 + 0.5)

                pixels[base_x + x, base_y + y] = (pixel_r, pixel_g, pixel_b)

    for target_dir in [CLIENT_LUT_DIR, STATIC_LUT_DIR]:
        out_path = os.path.join(target_dir, filename)
        img.save(out_path, "PNG")
        file_size_kb = os.path.getsize(out_path) / 1024.0
        print(f"[OK] Generated {filename} ({description}): {file_size_kb:.1f} KB -> {out_path}")


def main():
    print("Starting 512x512 3D LUT generation for Douyin viral cinematic color science...")
    for filename, func, desc in LUT_CONFIGS:
        generate_single_lut(filename, func, desc)
    print("[SUCCESS] All viral 3D LUT textures generated successfully!")


if __name__ == "__main__":
    main()
