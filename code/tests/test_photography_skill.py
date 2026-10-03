"""
摄影美学专家 Skill 单元测试 (Photography Skill Unit Tests)
测试涵盖:
- 传感器姿态上下文注入
- Markdown 杂质清洗与自愈
- coach_tip 字数截断与保护
- 色彩安全护栏 (Color Guard)
- OpenAPI 契约反序列化校验
"""

import pytest
from app.prompt.photography_skill import PhotographySkillEngine
from app.schemas.vision import SensorAttitude
from app.schemas.retouch import RecipeParameters


def test_build_composition_prompt_with_attitude():
    # 测试倾角注入
    att = SensorAttitude(pitch=25.0, roll=5.2)
    sys_prompt, user_prompt = PhotographySkillEngine.build_composition_prompt(
        sensor_attitude=att,
        scene_hint="夕阳人像"
    )
    assert "俯仰角 Pitch=25.0°" in user_prompt
    assert "地平线翻滚倾斜明显" in user_prompt
    assert "夕阳人像" in user_prompt
    assert "严格恪守的四大美学铁律" in sys_prompt


def test_clean_json_markdown_blocks():
    # 测试清洗器
    raw_with_block = """
    ```json
    {
      "code": 200,
      "message": "success",
      "data": {}
    }
    ```
    """
    cleaned = PhotographySkillEngine.clean_json_text(raw_with_block)
    assert cleaned.startswith("{")
    assert cleaned.endswith("}")
    assert "```" not in cleaned


def test_color_guard_clamping():
    # 测试色彩安全护栏
    params = RecipeParameters(
        exposure=2.5,          # 超出上限 1.0
        contrast=-3.0,         # 超出下限 -1.0
        temperature=80.0,      # 超出上限 30.0
        vibrance=0.8,          # 高自然饱和度
        saturation=0.5,        # 应当被安全压制
        grain=0.9              # 超出噪点上限 0.5
    )
    guarded = PhotographySkillEngine.apply_color_guard(params)
    assert guarded.exposure == 1.0
    assert guarded.contrast == -1.0
    assert guarded.temperature == 30.0
    assert guarded.grain == 0.5
    assert guarded.saturation == 0.10  # 触发自然饱和度互斥保护


def test_composition_validation_and_repair():
    raw_json = """
    {
      "scene_analysis": {
        "scene_type": "arch_symmetry",
        "scene_label_zh": "对称建筑",
        "confidence": 0.9,
        "detected_issues": ["central_axis_offset"]
      },
      "composition_guidance": {
        "coach_tip": "这是一个超级超级长的指导语文案肯定超过了二十个汉字的长度需要被截断",
        "action_type": "shift_right",
        "recommended_grid": "center_symmetry",
        "suggested_crop_box": {
          "ymin": -0.2,
          "xmin": 0.1,
          "ymax": 1.5,
          "xmax": 0.9
        },
        "navigation_vector": {
          "forward_steps": 5,
          "horizontal_translation_m": 2.5,
          "vertical_translation_cm": -50.0
        }
      },
      "filter_recommendation": {
        "recommended_lut_id": "lut_mono_contrast_04",
        "preset_name_zh": "经典黑白光影",
        "recommended_intensity": 0.85
      }
    }
    """
    valid, resp, msg = PhotographySkillEngine.validate_and_repair_composition(raw_json)
    assert valid is True
    assert resp is not None
    # 验证 coach_tip 是否被修剪至 <= 20
    assert len(resp.data.composition_guidance.coach_tip) <= 20
    # 验证 CropBox 是否被裁剪至 [0, 1]
    cb = resp.data.composition_guidance.suggested_crop_box
    assert cb.ymin >= 0.0
    assert cb.ymax <= 1.0
    # 验证 Navigation 物理阈值
    nav = resp.data.composition_guidance.navigation_vector
    assert nav.forward_steps <= 3
    assert abs(nav.horizontal_translation_m) <= 1.0
    assert abs(nav.vertical_translation_cm) <= 30.0
