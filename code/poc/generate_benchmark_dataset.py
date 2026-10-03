"""
AestheticLens-AI 20张基准评测数据集生成脚本 (Benchmark Dataset Generator)
遵循规范: ICCV PCCD、ICML AesFormer 与 Lightroom 调色体系
字段完全对齐: OpenAPI 3.1 规范与 SSOT 契约 (ymin, xmin, ymax, xmax 等)
"""

import json
import os
from PIL import Image, ImageDraw

DATASET_ROOT = os.path.dirname(os.path.abspath(__file__))
IMAGES_DIR = os.path.join(DATASET_ROOT, "dataset", "images")
GT_DIR = os.path.join(DATASET_ROOT, "dataset", "ground_truth")

os.makedirs(IMAGES_DIR, exist_ok=True)
os.makedirs(GT_DIR, exist_ok=True)

BENCHMARK_SPEC = [
    # 01 逆光夕阳人像 (4张)
    {
        "id": "sample_01",
        "name": "portrait_sunset_headroom",
        "scene_type": "portrait_sunset",
        "scene_label_zh": "逆光夕阳人像",
        "title": "逆光夕阳人像 - 头顶留白过大",
        "defects": ["headroom_too_large", "horizon_tilted"],
        "coach_tip": "放低机位仰拍前进两步",
        "action_type": "low_angle_and_closer",
        "crop_box": {"ymin": 0.20, "xmin": 0.15, "ymax": 0.90, "xmax": 0.85},
        "nav": {"forward_steps": 2, "horizontal_translation_m": 0.0, "vertical_translation_cm": -20.0},
        "lut_id": "lut_warm_film_03",
        "preset_name_zh": "落日余晖胶片",
        "recipe": {"exposure": 0.15, "contrast": 0.10, "highlights": -0.20, "shadows": 0.25, "temperature": 15.0, "tint": 4.0, "vibrance": 0.20, "saturation": 0.05, "vignette": -0.15, "grain": 0.10},
        "critique": "头顶空间空旷导致人物气势不足，逆光背景需压高光提暗部以保留晚霞与发丝细节。",
        "bg_colors": [(255, 140, 50), (255, 70, 30), (50, 20, 20)],
        "draw_type": "headroom"
    },
    {
        "id": "sample_02",
        "name": "portrait_sunset_underexposed",
        "scene_type": "portrait_sunset",
        "scene_label_zh": "逆光夕阳人像",
        "title": "逆光夕阳人像 - 面部背光死黑",
        "defects": ["face_underexposed", "high_contrast_blown"],
        "coach_tip": "向左横移一步借侧逆光",
        "action_type": "step_left_side_light",
        "crop_box": {"ymin": 0.10, "xmin": 0.10, "ymax": 0.90, "xmax": 0.90},
        "nav": {"forward_steps": 1, "horizontal_translation_m": -0.4, "vertical_translation_cm": 0.0},
        "lut_id": "lut_warm_film_03",
        "preset_name_zh": "落日余晖胶片",
        "recipe": {"exposure": 0.25, "contrast": -0.05, "highlights": -0.30, "shadows": 0.40, "temperature": 12.0, "tint": 2.0, "vibrance": 0.25, "saturation": 0.0, "vignette": -0.10, "grain": 0.08},
        "critique": "强烈夕阳导致面部暗沉缺乏眼神光，大幅提亮暗部还原肤质通透感。",
        "bg_colors": [(255, 180, 80), (240, 90, 40), (20, 10, 10)],
        "draw_type": "underexposed"
    },
    {
        "id": "sample_03",
        "name": "portrait_sunset_horizon_neck",
        "scene_type": "portrait_sunset",
        "scene_label_zh": "逆光夕阳人像",
        "title": "逆光夕阳人像 - 地平线穿颈",
        "defects": ["horizon_crossing_neck", "unbalanced_background_line"],
        "coach_tip": "下蹲机位仰拍避开穿颈",
        "action_type": "squat_avoid_horizon_neck",
        "crop_box": {"ymin": 0.15, "xmin": 0.12, "ymax": 0.90, "xmax": 0.88},
        "nav": {"forward_steps": 1, "horizontal_translation_m": 0.0, "vertical_translation_cm": -25.0},
        "lut_id": "lut_warm_film_03",
        "preset_name_zh": "落日余晖胶片",
        "recipe": {"exposure": 0.10, "contrast": 0.08, "highlights": -0.15, "shadows": 0.20, "temperature": 10.0, "tint": 3.0, "vibrance": 0.18, "saturation": 0.05, "vignette": -0.12, "grain": 0.05},
        "critique": "海平面或地平线直接切断颈部在视觉上极度突兀，降低机位让头顶完全进入天空。",
        "bg_colors": [(250, 120, 40), (230, 80, 50), (40, 60, 90)],
        "draw_type": "horizon_neck"
    },
    {
        "id": "sample_04",
        "name": "portrait_sunset_lookroom_missing",
        "scene_type": "portrait_sunset",
        "scene_label_zh": "逆光夕阳人像",
        "title": "逆光夕阳人像 - 侧视视线前方无留白",
        "defects": ["missing_look_room", "subject_edge_cramped"],
        "coach_tip": "向右平移预留视线留白",
        "action_type": "shift_right_for_lookroom",
        "crop_box": {"ymin": 0.08, "xmin": 0.20, "ymax": 0.90, "xmax": 0.95},
        "nav": {"forward_steps": 1, "horizontal_translation_m": 0.5, "vertical_translation_cm": 0.0},
        "lut_id": "lut_warm_film_03",
        "preset_name_zh": "落日余晖胶片",
        "recipe": {"exposure": 0.12, "contrast": 0.12, "highlights": -0.18, "shadows": 0.18, "temperature": 14.0, "tint": 5.0, "vibrance": 0.22, "saturation": 0.08, "vignette": -0.15, "grain": 0.06},
        "critique": "人物右侧望向画外却贴近边框，产生强烈逼仄感；重构构图后视线前方拥有广阔晚霞空间。",
        "bg_colors": [(255, 150, 60), (220, 60, 30), (30, 15, 20)],
        "draw_type": "lookroom"
    },

    # 02 精致美食俯拍 (3张)
    {
        "id": "sample_05",
        "name": "food_flatlay_tilt_45deg",
        "scene_type": "food_flatlay",
        "scene_label_zh": "精致美食俯拍",
        "title": "精致美食俯拍 - 俯拍角度倾斜非90度",
        "defects": ["non_vertical_pitch", "imperfect_flatlay"],
        "coach_tip": "垂直正俯拍对准餐盘中心",
        "action_type": "vertical_topdown_center",
        "crop_box": {"ymin": 0.10, "xmin": 0.10, "ymax": 0.90, "xmax": 0.90},
        "nav": {"forward_steps": 1, "horizontal_translation_m": 0.0, "vertical_translation_cm": 15.0},
        "lut_id": "lut_clean_bright_02",
        "preset_name_zh": "纯净通透物产",
        "recipe": {"exposure": 0.20, "contrast": 0.10, "highlights": -0.10, "shadows": 0.15, "temperature": 12.0, "tint": 6.0, "vibrance": 0.30, "saturation": 0.10, "vignette": -0.05, "grain": 0.0},
        "critique": "平铺俯拍倾角未达90度导致几何形变，扶正水平仪后餐具阵列极具仪式美感与食欲。",
        "bg_colors": [(240, 235, 225), (220, 210, 195), (200, 190, 170)],
        "draw_type": "food_tilt"
    },
    {
        "id": "sample_06",
        "name": "food_flatlay_plate_cropped",
        "scene_type": "food_flatlay",
        "scene_label_zh": "精致美食俯拍",
        "title": "精致美食俯拍 - 主盘边缘被突兀切断",
        "defects": ["plate_edge_truncated", "tight_framing"],
        "coach_tip": "后退半步容纳完整盘口",
        "action_type": "step_back_full_plate",
        "crop_box": {"ymin": 0.05, "xmin": 0.05, "ymax": 0.95, "xmax": 0.95},
        "nav": {"forward_steps": 1, "horizontal_translation_m": 0.0, "vertical_translation_cm": 10.0},
        "lut_id": "lut_clean_bright_02",
        "preset_name_zh": "纯净通透物产",
        "recipe": {"exposure": 0.15, "contrast": 0.15, "highlights": -0.12, "shadows": 0.10, "temperature": 8.0, "tint": 4.0, "vibrance": 0.25, "saturation": 0.12, "vignette": -0.08, "grain": 0.0},
        "critique": "主餐盘圆弧被画面左侧直接卡断破坏完整性，后退拉开取景空间保证圆润留白。",
        "bg_colors": [(235, 230, 215), (215, 205, 185), (195, 185, 165)],
        "draw_type": "food_cropped"
    },
    {
        "id": "sample_07",
        "name": "food_flatlay_cold_glare",
        "scene_type": "food_flatlay",
        "scene_label_zh": "精致美食俯拍",
        "title": "精致美食俯拍 - 顶光反光刺眼且色温冷暗",
        "defects": ["overhead_glare", "cold_color_cast"],
        "coach_tip": "倾斜微调避开餐桌反光点",
        "action_type": "tilt_avoid_glare",
        "crop_box": {"ymin": 0.15, "xmin": 0.15, "ymax": 0.85, "xmax": 0.85},
        "nav": {"forward_steps": 1, "horizontal_translation_m": -0.2, "vertical_translation_cm": 0.0},
        "lut_id": "lut_clean_bright_02",
        "preset_name_zh": "纯净通透物产",
        "recipe": {"exposure": 0.18, "contrast": 0.08, "highlights": -0.25, "shadows": 0.15, "temperature": 18.0, "tint": 8.0, "vibrance": 0.35, "saturation": 0.10, "vignette": -0.05, "grain": 0.0},
        "critique": "冷白日光灯导致汤汁产生白色死高光反光，升温色调配合压高光呈现新鲜多汁质感。",
        "bg_colors": [(210, 215, 220), (190, 195, 205), (170, 175, 185)],
        "draw_type": "food_glare"
    },

    # 03 赛博霓虹夜景 (3张)
    {
        "id": "sample_08",
        "name": "night_cyberpunk_neon_blown",
        "scene_type": "night_cyberpunk",
        "scene_label_zh": "赛博霓虹夜景",
        "title": "赛博霓虹夜景 - 霓虹招牌高光严重过曝",
        "defects": ["neon_highlight_blown", "blown_specular"],
        "coach_tip": "后退一步压暗曝光保招牌",
        "action_type": "step_back_underexpose_neon",
        "crop_box": {"ymin": 0.18, "xmin": 0.12, "ymax": 0.90, "xmax": 0.88},
        "nav": {"forward_steps": 1, "horizontal_translation_m": 0.0, "vertical_translation_cm": 0.0},
        "lut_id": "lut_cyber_teal_orange_03",
        "preset_name_zh": "赛博青橙夜色",
        "recipe": {"exposure": -0.20, "contrast": 0.22, "highlights": -0.40, "shadows": 0.18, "temperature": -15.0, "tint": -10.0, "vibrance": 0.28, "saturation": 0.15, "vignette": -0.20, "grain": 0.12},
        "critique": "繁华街头霓虹字体溢出死白失去笔画细节，压制高光强化青橙对撞色彩张力。",
        "bg_colors": [(20, 10, 30), (10, 5, 20), (5, 2, 10)],
        "draw_type": "night_neon"
    },
    {
        "id": "sample_09",
        "name": "night_cyberpunk_puddle_missed",
        "scene_type": "night_cyberpunk",
        "scene_label_zh": "赛博霓虹夜景",
        "title": "赛博霓虹夜景 - 站姿过高错过雨后水洼倒影",
        "defects": ["high_angle_missed_reflection", "flat_ground"],
        "coach_tip": "贴地超低机位捕捉水滩倒影",
        "action_type": "ground_level_reflection",
        "crop_box": {"ymin": 0.20, "xmin": 0.08, "ymax": 0.95, "xmax": 0.92},
        "nav": {"forward_steps": 1, "horizontal_translation_m": 0.0, "vertical_translation_cm": -30.0},
        "lut_id": "lut_cyber_teal_orange_03",
        "preset_name_zh": "赛博青橙夜色",
        "recipe": {"exposure": 0.05, "contrast": 0.25, "highlights": -0.25, "shadows": 0.15, "temperature": -12.0, "tint": -8.0, "vibrance": 0.32, "saturation": 0.18, "vignette": -0.25, "grain": 0.15},
        "critique": "普通站姿视线平淡，将相机贴近湿漉地面能产生上下对称的梦幻流光倒影。",
        "bg_colors": [(15, 25, 45), (10, 15, 30), (5, 8, 15)],
        "draw_type": "night_puddle"
    },
    {
        "id": "sample_10",
        "name": "night_cyberpunk_noisy_dark",
        "scene_type": "night_cyberpunk",
        "scene_label_zh": "赛博霓虹夜景",
        "title": "赛博霓虹夜景 - 暗部死黑噪点杂乱无视觉中心",
        "defects": ["messy_dark_noise", "lack_of_focal_point"],
        "coach_tip": "靠近明亮灯箱构图突出主体",
        "action_type": "approach_lightbox_focus",
        "crop_box": {"ymin": 0.12, "xmin": 0.18, "ymax": 0.88, "xmax": 0.86},
        "nav": {"forward_steps": 2, "horizontal_translation_m": 0.3, "vertical_translation_cm": 0.0},
        "lut_id": "lut_cyber_teal_orange_03",
        "preset_name_zh": "赛博青橙夜色",
        "recipe": {"exposure": 0.10, "contrast": 0.18, "highlights": -0.30, "shadows": 0.05, "temperature": -10.0, "tint": -5.0, "vibrance": 0.20, "saturation": 0.10, "vignette": -0.30, "grain": 0.05},
        "critique": "空旷黑暗区域过大引起噪点喧宾夺主，前移逼近光影主体建立明确视觉锚点。",
        "bg_colors": [(30, 20, 15), (15, 10, 8), (5, 5, 5)],
        "draw_type": "night_noise"
    },

    # 04 对称建筑空间 (4张)
    {
        "id": "sample_11",
        "name": "arch_symmetry_axis_offset",
        "scene_type": "arch_symmetry",
        "scene_label_zh": "对称建筑空间",
        "title": "对称建筑空间 - 中轴线左右偏移失衡",
        "defects": ["central_axis_offset", "broken_symmetry"],
        "coach_tip": "向右平移半步对齐对称轴",
        "action_type": "step_right_align_axis",
        "crop_box": {"ymin": 0.05, "xmin": 0.08, "ymax": 0.95, "xmax": 0.92},
        "nav": {"forward_steps": 1, "horizontal_translation_m": 0.3, "vertical_translation_cm": 0.0},
        "lut_id": "lut_mono_contrast_04",
        "preset_name_zh": "经典黑白光影",
        "recipe": {"exposure": 0.05, "contrast": 0.20, "highlights": -0.15, "shadows": 0.10, "temperature": -5.0, "tint": 0.0, "vibrance": -0.10, "saturation": -0.30, "vignette": -0.10, "grain": 0.05},
        "critique": "几何建筑对强迫症级对称要求极高，微弱的偏心破坏庄严肃穆感，平移校准中线。",
        "bg_colors": [(220, 225, 230), (180, 185, 190), (140, 145, 150)],
        "draw_type": "arch_offset"
    },
    {
        "id": "sample_12",
        "name": "arch_symmetry_keystone_tilt",
        "scene_type": "arch_symmetry",
        "scene_label_zh": "对称建筑空间",
        "title": "对称建筑空间 - 广角仰拍梯形透视内倾严重",
        "defects": ["keystoning_tilt", "converging_verticals"],
        "coach_tip": "平视机位后退两步消除透视",
        "action_type": "level_step_back_no_keystone",
        "crop_box": {"ymin": 0.10, "xmin": 0.10, "ymax": 0.95, "xmax": 0.90},
        "nav": {"forward_steps": 2, "horizontal_translation_m": 0.0, "vertical_translation_cm": 0.0},
        "lut_id": "lut_mono_contrast_04",
        "preset_name_zh": "经典黑白光影",
        "recipe": {"exposure": 0.0, "contrast": 0.18, "highlights": -0.10, "shadows": 0.12, "temperature": 0.0, "tint": 0.0, "vibrance": 0.0, "saturation": -0.50, "vignette": -0.05, "grain": 0.08},
        "critique": "近距离仰拍造成立柱向内聚拢倾倒，拉大拍摄距离保持水平仪0度可实现横平竖直。",
        "bg_colors": [(200, 205, 215), (170, 175, 185), (130, 135, 145)],
        "draw_type": "arch_keystone"
    },
    {
        "id": "sample_13",
        "name": "arch_symmetry_half_empty",
        "scene_type": "arch_symmetry",
        "scene_label_zh": "对称建筑空间",
        "title": "对称建筑空间 - 地平线居中导致平淡无主次",
        "defects": ["horizon_dead_center", "lack_of_visual_weight"],
        "coach_tip": "微仰机位纳入宏伟穹顶结构",
        "action_type": "pitch_up_capture_dome",
        "crop_box": {"ymin": 0.15, "xmin": 0.08, "ymax": 0.93, "xmax": 0.92},
        "nav": {"forward_steps": 1, "horizontal_translation_m": 0.0, "vertical_translation_cm": 15.0},
        "lut_id": "lut_mono_contrast_04",
        "preset_name_zh": "经典黑白光影",
        "recipe": {"exposure": 0.08, "contrast": 0.22, "highlights": -0.18, "shadows": 0.15, "temperature": -4.0, "tint": 1.0, "vibrance": 0.10, "saturation": -0.10, "vignette": -0.12, "grain": 0.06},
        "critique": "五五开构图削弱了空间张力，通过向上仰视展示天花板穹顶的雕花与纵深线条。",
        "bg_colors": [(210, 210, 220), (180, 175, 185), (120, 115, 125)],
        "draw_type": "arch_half"
    },
    {
        "id": "sample_14",
        "name": "arch_symmetry_pedestrian_intrusion",
        "scene_type": "arch_symmetry",
        "scene_label_zh": "对称建筑空间",
        "title": "对称建筑空间 - 边缘闯入无关路人破坏纯粹感",
        "defects": ["background_clutter", "pedestrian_intrusion"],
        "coach_tip": "前进一步裁切避开右侧路人",
        "action_type": "step_forward_crop_pedestrian",
        "crop_box": {"ymin": 0.08, "xmin": 0.05, "ymax": 0.92, "xmax": 0.83},
        "nav": {"forward_steps": 1, "horizontal_translation_m": -0.2, "vertical_translation_cm": 0.0},
        "lut_id": "lut_mono_contrast_04",
        "preset_name_zh": "经典黑白光影",
        "recipe": {"exposure": 0.02, "contrast": 0.24, "highlights": -0.12, "shadows": 0.14, "temperature": 0.0, "tint": 0.0, "vibrance": -0.20, "saturation": -0.80, "vignette": -0.15, "grain": 0.10},
        "critique": "边缘路人破坏了静态对称的纯粹禅意，前移机位微偏裁切还原建筑殿堂的安宁。",
        "bg_colors": [(225, 230, 235), (190, 195, 200), (150, 155, 160)],
        "draw_type": "arch_pedestrian"
    },

    # 05 街拍纪实抓拍 (3张)
    {
        "id": "sample_15",
        "name": "street_candid_subject_lost",
        "scene_type": "street_candid",
        "scene_label_zh": "街拍纪实抓拍",
        "title": "街拍纪实抓拍 - 主体行人淹没在杂乱人潮中",
        "defects": ["subject_cluttered", "lack_of_isolation"],
        "coach_tip": "前进两步接近主体虚化背景",
        "action_type": "closer_isolate_subject",
        "crop_box": {"ymin": 0.15, "xmin": 0.20, "ymax": 0.90, "xmax": 0.85},
        "nav": {"forward_steps": 2, "horizontal_translation_m": 0.1, "vertical_translation_cm": 0.0},
        "lut_id": "lut_warm_film_03",
        "preset_name_zh": "落日余晖胶片",
        "recipe": {"exposure": 0.10, "contrast": 0.18, "highlights": -0.15, "shadows": 0.12, "temperature": 8.0, "tint": 2.0, "vibrance": 0.15, "saturation": 0.05, "vignette": -0.18, "grain": 0.14},
        "critique": "街头人群多且背景杂芜导致主角不明显，逼近目标人物特写，压暗周边突出纪实感。",
        "bg_colors": [(180, 170, 160), (140, 130, 120), (90, 80, 75)],
        "draw_type": "street_lost"
    },
    {
        "id": "sample_16",
        "name": "street_candid_walking_out_of_frame",
        "scene_type": "street_candid",
        "scene_label_zh": "街拍纪实抓拍",
        "title": "街拍纪实抓拍 - 行人走出画框方向过于局促",
        "defects": ["walking_into_edge", "imbalanced_motion_space"],
        "coach_tip": "向左移机预留行人迈步空间",
        "action_type": "shift_left_space_for_walking",
        "crop_box": {"ymin": 0.10, "xmin": 0.15, "ymax": 0.90, "xmax": 0.90},
        "nav": {"forward_steps": 1, "horizontal_translation_m": -0.5, "vertical_translation_cm": 0.0},
        "lut_id": "lut_warm_film_03",
        "preset_name_zh": "落日余晖胶片",
        "recipe": {"exposure": 0.08, "contrast": 0.15, "highlights": -0.10, "shadows": 0.10, "temperature": 6.0, "tint": 0.0, "vibrance": 0.12, "saturation": 0.02, "vignette": -0.10, "grain": 0.10},
        "critique": "抓拍动态人物必须向其行进方向预留视觉空间，否则画面充满阻滞感与压抑感。",
        "bg_colors": [(170, 165, 160), (130, 125, 120), (80, 75, 70)],
        "draw_type": "street_edge"
    },
    {
        "id": "sample_17",
        "name": "street_candid_leading_line_missed",
        "scene_type": "street_candid",
        "scene_label_zh": "街拍纪实抓拍",
        "title": "街拍纪实抓拍 - 斑马线透视引导线被机位切断",
        "defects": ["leading_line_ignored", "flat_perspective"],
        "coach_tip": "下蹲利用斑马线引导视线",
        "action_type": "squat_use_crosswalk_lead",
        "crop_box": {"ymin": 0.18, "xmin": 0.10, "ymax": 0.93, "xmax": 0.90},
        "nav": {"forward_steps": 1, "horizontal_translation_m": 0.0, "vertical_translation_cm": -25.0},
        "lut_id": "lut_warm_film_03",
        "preset_name_zh": "落日余晖胶片",
        "recipe": {"exposure": 0.12, "contrast": 0.22, "highlights": -0.18, "shadows": 0.15, "temperature": 10.0, "tint": 4.0, "vibrance": 0.20, "saturation": 0.05, "vignette": -0.15, "grain": 0.12},
        "critique": "俯视拍摄斑马线失去透视冲击力，压低机位使黑白条纹直指画面深处人物主体。",
        "bg_colors": [(190, 185, 180), (145, 140, 135), (95, 90, 85)],
        "draw_type": "street_lines"
    },

    # 06 黄昏逆光剪影 (3张)
    {
        "id": "sample_18",
        "name": "silhouette_cluttered_skyline",
        "scene_type": "backlight_silhouette",
        "scene_label_zh": "黄昏逆光剪影",
        "title": "黄昏逆光剪影 - 剪影与复杂树枝杂物黏连",
        "defects": ["silhouette_overlap", "cluttered_skyline"],
        "coach_tip": "下蹲仰拍将剪影置于纯净天际",
        "action_type": "squat_silhouette_sky_clean",
        "crop_box": {"ymin": 0.12, "xmin": 0.12, "ymax": 0.90, "xmax": 0.88},
        "nav": {"forward_steps": 1, "horizontal_translation_m": 0.0, "vertical_translation_cm": -30.0},
        "lut_id": "lut_warm_film_03",
        "preset_name_zh": "落日余晖胶片",
        "recipe": {"exposure": -0.15, "contrast": 0.35, "highlights": -0.25, "shadows": -0.20, "temperature": 22.0, "tint": 10.0, "vibrance": 0.40, "saturation": 0.15, "vignette": -0.30, "grain": 0.05},
        "critique": "剪影的灵魂在于轮廓纯粹度，下蹲让人物优美姿态完全衬托在火烧云晚霞画布上。",
        "bg_colors": [(255, 90, 30), (200, 40, 60), (40, 10, 30)],
        "draw_type": "silhouette_overlap"
    },
    {
        "id": "sample_19",
        "name": "silhouette_excessive_black",
        "scene_type": "backlight_silhouette",
        "scene_label_zh": "黄昏逆光剪影",
        "title": "黄昏逆光剪影 - 地面死黑面积超过65%",
        "defects": ["excessive_shadow_dead_zone", "unbalanced_mass"],
        "coach_tip": "微仰机位增加晚霞天空占比",
        "action_type": "pitch_up_sky_two_thirds",
        "crop_box": {"ymin": 0.25, "xmin": 0.05, "ymax": 0.95, "xmax": 0.95},
        "nav": {"forward_steps": 1, "horizontal_translation_m": 0.0, "vertical_translation_cm": 20.0},
        "lut_id": "lut_warm_film_03",
        "preset_name_zh": "落日余晖胶片",
        "recipe": {"exposure": 0.05, "contrast": 0.30, "highlights": -0.30, "shadows": -0.15, "temperature": 20.0, "tint": 8.0, "vibrance": 0.35, "saturation": 0.12, "vignette": -0.25, "grain": 0.06},
        "critique": "大面积无信息的死黑地面压抑沉重，仰头将三分之二画幅交给绚丽晚霞。",
        "bg_colors": [(255, 110, 40), (220, 50, 50), (30, 15, 25)],
        "draw_type": "silhouette_black"
    },
    {
        "id": "sample_20",
        "name": "silhouette_washed_sunset",
        "scene_type": "backlight_silhouette",
        "scene_label_zh": "黄昏逆光剪影",
        "title": "黄昏逆光剪影 - 天空晚霞被强光洗白过曝",
        "defects": ["sunset_washed_out", "blown_sky"],
        "coach_tip": "降低曝光找回绚丽晚霞细节",
        "action_type": "underexpose_sunset_rich_color",
        "crop_box": {"ymin": 0.10, "xmin": 0.10, "ymax": 0.90, "xmax": 0.90},
        "nav": {"forward_steps": 1, "horizontal_translation_m": 0.0, "vertical_translation_cm": 0.0},
        "lut_id": "lut_warm_film_03",
        "preset_name_zh": "落日余晖胶片",
        "recipe": {"exposure": -0.28, "contrast": 0.28, "highlights": -0.45, "shadows": -0.10, "temperature": 25.0, "tint": 12.0, "vibrance": 0.45, "saturation": 0.20, "vignette": -0.20, "grain": 0.04},
        "critique": "测光偏高导致天空死白失去色彩梯度，大幅压低曝光锁定剪影，唤醒浓烈暖橙紫调。",
        "bg_colors": [(255, 230, 180), (255, 160, 90), (180, 50, 40)],
        "draw_type": "silhouette_washed"
    }
]

def generate_sample_image(spec, width=720, height=960):
    img = Image.new("RGB", (width, height))
    draw = ImageDraw.Draw(img)

    c1, c2, c3 = spec["bg_colors"]
    for y in range(height):
        factor = y / height
        if factor < 0.5:
            lf = factor / 0.5
            r = int(c1[0] * (1 - lf) + c2[0] * lf)
            g = int(c1[1] * (1 - lf) + c2[1] * lf)
            b = int(c1[2] * (1 - lf) + c2[2] * lf)
        else:
            lf = (factor - 0.5) / 0.5
            r = int(c2[0] * (1 - lf) + c3[0] * lf)
            g = int(c2[1] * (1 - lf) + c3[1] * lf)
            b = int(c2[2] * (1 - lf) + c3[2] * lf)
        draw.line([(0, y), (width, y)], fill=(r, g, b))

    dtype = spec["draw_type"]
    if "headroom" in dtype:
        draw.ellipse([width*0.4, height*0.65, width*0.6, height*0.78], fill=(30, 20, 20))
        draw.polygon([(width*0.35, height), (width*0.65, height), (width*0.5, height*0.78)], fill=(20, 15, 15))
    elif "underexposed" in dtype:
        draw.ellipse([width*0.35, height*0.30, width*0.65, height*0.50], fill=(5, 5, 5))
        draw.polygon([(width*0.25, height), (width*0.75, height), (width*0.5, height*0.50)], fill=(8, 8, 8))
        draw.ellipse([width*0.5 - 150, height*0.30 - 100, width*0.5 + 150, height*0.30 + 100], outline=(255, 240, 200), width=8)
    elif "horizon_neck" in dtype:
        neck_y = int(height * 0.45)
        draw.line([(0, neck_y), (width, neck_y)], fill=(30, 60, 90), width=6)
        draw.ellipse([width*0.4, height*0.32, width*0.6, height*0.45], fill=(35, 25, 20))
        draw.polygon([(width*0.3, height), (width*0.7, height), (width*0.5, height*0.45)], fill=(25, 20, 15))
    elif "lookroom" in dtype:
        draw.ellipse([width*0.75, height*0.35, width*0.95, height*0.48], fill=(30, 25, 20))
        draw.polygon([(width*0.7, height), (width*1.0, height), (width*0.85, height*0.48)], fill=(20, 15, 15))
    elif "food" in dtype:
        if "tilt" in dtype:
            draw.ellipse([width*0.2, height*0.3, width*0.8, height*0.6], fill=(240, 240, 240), outline=(200, 190, 170), width=8)
            draw.ellipse([width*0.3, height*0.36, width*0.7, height*0.54], fill=(210, 120, 50))
        elif "cropped" in dtype:
            draw.ellipse([-width*0.2, height*0.25, width*0.65, height*0.75], fill=(245, 245, 245), outline=(180, 170, 150), width=10)
            draw.ellipse([-width*0.05, height*0.35, width*0.5, height*0.65], fill=(220, 80, 30))
        elif "glare" in dtype:
            draw.ellipse([width*0.2, height*0.25, width*0.8, height*0.70], fill=(240, 240, 245), outline=(190, 195, 200), width=8)
            draw.ellipse([width*0.35, height*0.35, width*0.65, height*0.60], fill=(200, 100, 50))
            draw.ellipse([width*0.45, height*0.40, width*0.55, height*0.48], fill=(255, 255, 255))
    elif "night" in dtype:
        if "neon" in dtype:
            draw.rectangle([width*0.3, height*0.2, width*0.7, height*0.4], fill=(255, 255, 255), outline=(255, 0, 120), width=15)
        elif "puddle" in dtype:
            draw.line([(0, height*0.6), (width, height*0.6)], fill=(40, 60, 100), width=3)
            draw.ellipse([width*0.1, height*0.7, width*0.9, height*0.9], fill=(20, 35, 60), outline=(0, 220, 255), width=4)
        elif "noise" in dtype:
            draw.rectangle([width*0.1, height*0.1, width*0.4, height*0.4], fill=(255, 120, 0))
    elif "arch" in dtype:
        center_x = width * 0.42 if "offset" in dtype else width * 0.50
        draw.rectangle([center_x - 180, height*0.2, center_x - 120, height], fill=(160, 165, 170))
        draw.rectangle([center_x + 120, height*0.2, center_x + 180, height], fill=(160, 165, 170))
        draw.polygon([(center_x - 220, height*0.2), (center_x + 220, height*0.2), (center_x, height*0.05)], fill=(120, 125, 130))
        if "pedestrian" in dtype:
            draw.ellipse([width*0.82, height*0.75, width*0.92, height*0.83], fill=(40, 40, 40))
            draw.polygon([(width*0.80, height), (width*0.94, height), (width*0.87, height*0.83)], fill=(20, 20, 20))
    elif "street" in dtype:
        draw.line([(0, height*0.7), (width, height*0.7)], fill=(80, 80, 80), width=4)
        if "lines" in dtype:
            for step in range(5):
                draw.line([(width*0.1 + step*80, height*0.95), (width*0.3 + step*40, height*0.72)], fill=(240, 240, 240), width=16)
        if "edge" in dtype:
            draw.ellipse([width*0.05, height*0.5, width*0.18, height*0.6], fill=(30, 30, 30))
            draw.polygon([(0, height*0.85), (width*0.22, height*0.85), (width*0.11, height*0.6)], fill=(20, 20, 20))
        else:
            draw.ellipse([width*0.45, height*0.5, width*0.58, height*0.6], fill=(30, 30, 30))
            draw.polygon([(width*0.38, height*0.85), (width*0.65, height*0.85), (width*0.51, height*0.6)], fill=(20, 20, 20))
    elif "silhouette" in dtype:
        if "black" in dtype:
            draw.rectangle([0, height*0.35, width, height], fill=(0, 0, 0))
            draw.ellipse([width*0.45, height*0.26, width*0.55, height*0.35], fill=(0, 0, 0))
        else:
            draw.rectangle([0, height*0.70, width, height], fill=(5, 5, 5))
            draw.ellipse([width*0.42, height*0.52, width*0.58, height*0.65], fill=(0, 0, 0))
            draw.polygon([(width*0.35, height*0.70), (width*0.65, height*0.70), (width*0.5, height*0.65)], fill=(0, 0, 0))
            if "overlap" in dtype:
                draw.line([(width*0.45, height*0.55), (width*0.3, height*0.4)], fill=(0, 0, 0), width=6)
                draw.line([(width*0.55, height*0.58), (width*0.7, height*0.42)], fill=(0, 0, 0), width=5)

    draw.text((20, 20), f"AestheticLens Benchmark: {spec['id']}", fill=(255, 255, 255))
    draw.text((20, 45), f"Scene: {spec['scene_type']}", fill=(200, 200, 200))
    return img

def main():
    manifest = []
    print("Generating 20 benchmark samples and ground truths...")

    for spec in BENCHMARK_SPEC:
        sid = spec["id"]
        img_name = f"{sid}_{spec['name']}.jpg"
        img_path = os.path.join(IMAGES_DIR, img_name)
        gt_name = f"{sid}_{spec['name']}.json"
        gt_path = os.path.join(GT_DIR, gt_name)

        img = generate_sample_image(spec)
        img.save(img_path, "JPEG", quality=85)
        file_size_kb = os.path.getsize(img_path) / 1024.0

        # 符合 Envelope[AnalyzeCompositionData] 的标准数据结构
        gt_data = {
            "code": 200,
            "message": "success",
            "request_id": f"req_bench_{sid}",
            "data": {
                "scene_analysis": {
                    "scene_type": spec["scene_type"],
                    "scene_label_zh": spec["scene_label_zh"],
                    "confidence": 0.95,
                    "detected_issues": spec["defects"]
                },
                "composition_guidance": {
                    "coach_tip": spec["coach_tip"],
                    "action_type": spec["action_type"],
                    "recommended_grid": "rule_of_thirds",
                    "suggested_crop_box": spec["crop_box"],
                    "target_pitch_adjustment_deg": 0.0,
                    "navigation_vector": spec["nav"]
                },
                "filter_recommendation": {
                    "recommended_lut_id": spec["lut_id"],
                    "preset_name_zh": spec["preset_name_zh"],
                    "recommended_intensity": 0.85,
                    "color_adjustments": {
                        "exposure": spec["recipe"]["exposure"],
                        "temperature": spec["recipe"]["temperature"],
                        "contrast": spec["recipe"]["contrast"]
                    }
                }
            },
            "retouch_ground_truth": {
                "aesthetic_diagnosis": {
                    "overall_critique": spec["critique"],
                    "target_style": "vintage_warm",
                    "style_name_zh": spec["preset_name_zh"]
                },
                "recommended_recipe": {
                    "lut_id": spec["lut_id"],
                    "lut_intensity": 0.85,
                    "parameters": spec["recipe"]
                }
            },
            "meta": {
                "sample_id": sid,
                "title": spec["title"],
                "file_size_kb": round(file_size_kb, 2),
                "resolution": {"width": 720, "height": 960}
            }
        }

        with open(gt_path, "w", encoding="utf-8") as f:
            json.dump(gt_data, f, ensure_ascii=False, indent=2)

        manifest.append({
            "sample_id": sid,
            "scene_type": spec["scene_type"],
            "title": spec["title"],
            "image_file": f"dataset/images/{img_name}",
            "gt_file": f"dataset/ground_truth/{gt_name}",
            "defects_count": len(spec["defects"]),
            "file_size_kb": round(file_size_kb, 2)
        })

    manifest_path = os.path.join(DATASET_ROOT, "dataset", "benchmark_manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump({
            "version": "1.0.0",
            "total_samples": len(manifest),
            "scenes": ["portrait_sunset", "food_flatlay", "night_cyberpunk", "arch_symmetry", "street_candid", "backlight_silhouette"],
            "standards": ["ICCV PCCD", "ICML AesFormer", "Lightroom Color Science"],
            "samples": manifest
        }, f, ensure_ascii=False, indent=2)

    print(f"[OK] Successfully generated {len(manifest)} benchmark samples and manifest: {manifest_path}")

if __name__ == "__main__":
    main()
