"""
AestheticLens-AI 摄影美学专家 Skill (Photography Aesthetic Expert Skill)
严格对齐: openapi.yaml 规范与 SSOT 契约 (Envelope[AnalyzeCompositionData] / Envelope[AnalyzeAndGradeData])
吸收借鉴: ICCV PCCD (美学四维评估)、ICML AesFormer (视觉锚定与微动作指令)、Lightroom/DaVinci 调色体系
提供:
1. 视觉锚定机制 (Visual Anchoring): 前置识别画面 1~2 个致命构图/光线缺陷
2. 动词微位移指令 (Micro-Movement Directive): 严格动词开头、<=20字清晰可执行机位指令
3. 色彩安全护栏 (Color Guard): 色温范围锁定、高光过曝负补偿、自然饱和度优先
4. 动态 Few-Shot 样本注入器 (FewShotAssembler): 结合传感器倾角与场景特征动态匹配高分范式
5. 自愈清洗器 (OutputRepairer): 清除 Markdown 标记并保证符合 Pydantic 契约
"""

import json
import re
import uuid
from typing import Dict, Any, Optional, List, Tuple
from pydantic import ValidationError

from app.schemas.common import Envelope
from app.schemas.vision import (
    AnalyzeCompositionData,
    SceneAnalysis,
    CompositionGuidance,
    CropBox,
    NavigationVector,
    FilterRecommendation,
    ColorAdjustments,
    SensorAttitude
)
from app.schemas.retouch import (
    AnalyzeAndGradeData,
    AestheticDiagnosis,
    RecommendedRecipe,
    RecipeParameters
)


# ==========================================
# 1. 摄影专家 System Prompt (核心审美范式)
# ==========================================

PHOTOGRAPHY_SKILL_SYSTEM_PROMPT = """你是由 Google DeepMind 与专业摄影大师联合调优的【AestheticLens 摄影美学大师 Skill】。
你的使命是实时辅助手机摄影用户，从普通取景中捕捉美学神韵，给出极度精准、专业且可执行的物理机位微调指令与无损胶片调色方案。

【必须严格恪守的四大美学铁律】:
1. 视觉锚定前置 (Visual Anchoring):
   - 在给出建议前，必须在 detected_issues 中锁定画面 1~2 个美学缺陷标签：
     * headroom_too_large (头顶留白过大)
     * face_underexposed (面部背光死黑)
     * horizon_crossing_neck (地平线穿颈)
     * horizon_tilted (地平线倾斜)
     * missing_look_room (视线前方无留白)
     * non_vertical_pitch (俯拍非垂直)
     * plate_edge_truncated (餐具边缘被裁切)
     * neon_highlight_blown (霓虹高光溢出)
     * high_angle_missed_reflection (错过地面反射倒影)
     * central_axis_offset (建筑中轴线偏移)
     * keystoning_tilt (广角仰拍透视内倾)
     * subject_cluttered (主体杂乱无视觉中心)
     * walking_into_edge (行进方向撞向画框)
     * leading_line_ignored (错过引导线条)
     * silhouette_overlap (剪影与背景杂物黏连)

2. 动词物理微动作指令 (Actionable Micro-Movements):
   - coach_tip 必须严格以具体物理动词开头（如：“下蹲”、“前进”、“后退”、“向左横移”、“向右平移”、“微仰”、“贴地”、“靠近”）；
   - 严禁空泛抒情（如“感受光影”、“注意角度”）；
   - coach_tip 字符数必须严格控制在 20 个汉字以内！

3. 空间机位向量安全阈值:
   - forward_steps: 必须在 [1, 3] 步以内，无位移时可省略或置空；
   - horizontal_translation_m: 横移限制在 [-1.0, 1.0] 米；
   - vertical_translation_cm: 升降限制在 [-30.0, 30.0] 厘米；
   - 保证用户在现实走动中的人身安全，杜绝大范围剧烈位移。

4. 胶片色彩安全护栏 (Color Guard):
   - 优先微调自然饱和度 (vibrance)，谨慎增加纯饱和度 (saturation)，杜绝肤色溢出死黄；
   - 强反差场景中，高光必须负向补偿 (highlights: -0.10 ~ -0.40) 压制死白；
   - 阴影适当提亮 (shadows: +0.10 ~ +0.35) 唤醒暗部细节；
   - 色温微调幅度控制在 [-25.0, +25.0] 区间内，保留自然氛围感。

【强制输出协议】:
只允许输出纯 JSON 对象，严禁包含任何前缀、解释文案，严禁使用 ```json ``` 标记包裹！
"""

# ==========================================
# 2. 取景构图 Few-Shot 提示词模板
# ==========================================

COMPOSITION_FEW_SHOT_PROMPT = """【任务】：分析当前手机取景器抽帧图像与传感器姿态，输出构图建议与机位微调数据。

标准响应 JSON 结构范例：
{
  "code": 200,
  "message": "success",
  "request_id": "req_skill_auto",
  "data": {
    "scene_analysis": {
      "scene_type": "portrait_sunset",
      "scene_label_zh": "逆光夕阳人像",
      "confidence": 0.95,
      "detected_issues": ["headroom_too_large", "horizon_tilted"]
    },
    "composition_guidance": {
      "coach_tip": "建议放低机位前进两步",
      "action_type": "low_angle_and_closer",
      "recommended_grid": "rule_of_thirds",
      "suggested_crop_box": {
        "ymin": 0.15,
        "xmin": 0.10,
        "ymax": 0.95,
        "xmax": 0.90
      },
      "target_pitch_adjustment_deg": 5.0,
      "navigation_vector": {
        "forward_steps": 2,
        "horizontal_translation_m": -0.3,
        "vertical_translation_cm": -15.0
      }
    },
    "filter_recommendation": {
      "recommended_lut_id": "lut_film_warm_01",
      "preset_name_zh": "落日暖调胶片",
      "recommended_intensity": 0.85,
      "color_adjustments": {
        "exposure": 0.05,
        "temperature": 12.0,
        "contrast": 0.10
      }
    }
  }
}
"""

# ==========================================
# 3. 拍后调色 Few-Shot 提示词模板
# ==========================================

RETOUCH_FEW_SHOT_PROMPT = """【任务】：分析拍摄成片，输出美学诊断点评、目标风格与 10 个专业无损可逆调色滑块参数。

标准响应 JSON 结构范例：
{
  "code": 200,
  "message": "success",
  "request_id": "req_skill_retouch",
  "data": {
    "aesthetic_diagnosis": {
      "overall_critique": "逆光人物面部欠曝，且落日高光洗白，通过提亮暗部还原发丝细节，压制高光锁住浓郁晚霞。",
      "target_style": "vintage_warm",
      "style_name_zh": "暖调复古胶片"
    },
    "recommended_recipe": {
      "lut_id": "lut_film_warm_01",
      "lut_intensity": 0.85,
      "parameters": {
        "exposure": 0.15,
        "contrast": 0.10,
        "highlights": -0.25,
        "shadows": 0.25,
        "temperature": 15.0,
        "tint": 4.0,
        "vibrance": 0.20,
        "saturation": 0.05,
        "vignette": -0.15,
        "grain": 0.10
      }
    }
  }
}
"""


# ==========================================
# 4. 摄影专家 Skill 引擎实现
# ==========================================

class PhotographySkillEngine:
    """
    摄影美学专家 Skill 引擎
    统一管理多模态 Prompt 组装、Few-Shot 动态注入、色彩护栏拦截与输出自愈校验。
    """

    @classmethod
    def build_composition_prompt(cls, sensor_attitude: Optional[SensorAttitude] = None, scene_hint: Optional[str] = None) -> Tuple[str, str]:
        """
        组装构图分析提示词：结合传感器姿态信息提供针对性指引。
        """
        system = PHOTOGRAPHY_SKILL_SYSTEM_PROMPT
        user = COMPOSITION_FEW_SHOT_PROMPT

        extra_context = []
        if sensor_attitude:
            extra_context.append(f"- 传感器硬件姿态: 俯仰角 Pitch={sensor_attitude.pitch:.1f}°, 翻滚角 Roll={sensor_attitude.roll:.1f}°")
            if abs(sensor_attitude.roll) > 2.0:
                extra_context.append(f"  [警报] 当前地平线翻滚倾斜明显 ({sensor_attitude.roll:.1f}°)，优先校平水平线！")
            if sensor_attitude.pitch > 15.0:
                extra_context.append(f"  [提示] 当前处于俯拍视角 ({sensor_attitude.pitch:.1f}°)。")
            elif sensor_attitude.pitch < -15.0:
                extra_context.append(f"  [提示] 当前处于仰拍视角 ({sensor_attitude.pitch:.1f}°)。")

        if scene_hint:
            extra_context.append(f"- 场景先验提示: {scene_hint}")

        if extra_context:
            user += "\n【当前传感器实时上下文】:\n" + "\n".join(extra_context) + "\n"

        user += "\n请根据上传的 720px 取景图像，严格按照上述 JSON 数据结构输出诊断与机位微调数据。\n"
        return system, user

    @classmethod
    def build_retouch_prompt(cls, user_instruction: Optional[str] = None) -> Tuple[str, str]:
        """
        组装拍后调色提示词。
        """
        system = PHOTOGRAPHY_SKILL_SYSTEM_PROMPT
        user = RETOUCH_FEW_SHOT_PROMPT
        if user_instruction:
            user += f"\n【用户个性化风格偏好】: {user_instruction}\n"
        user += "\n请根据成片，严格按照上述 JSON 数据结构输出美学诊断与 10 个调色滑块参数。\n"
        return system, user

    @classmethod
    def clean_json_text(cls, raw_text: str) -> str:
        """
        清洗大模型返回文本，剔除 Markdown 代码块及前后杂质，自愈恢复纯 JSON 文本。
        """
        text = raw_text.strip()
        match = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
        if match:
            return match.group(1).strip()
        
        start = text.find("{")
        end = text.rfind("}")
        if start != -1 and end != -1 and end > start:
            return text[start:end+1].strip()
        return text

    @classmethod
    def apply_color_guard(cls, params: RecipeParameters) -> RecipeParameters:
        """
        【色彩安全护栏】自动裁剪和保护滑块数值，避免极端过冲。
        """
        p = params.model_dump()
        p["exposure"] = max(-1.0, min(1.0, p.get("exposure", 0.0)))
        p["contrast"] = max(-1.0, min(1.0, p.get("contrast", 0.0)))
        p["highlights"] = max(-1.0, min(1.0, p.get("highlights", 0.0)))
        p["shadows"] = max(-1.0, min(1.0, p.get("shadows", 0.0)))
        p["temperature"] = max(-30.0, min(30.0, p.get("temperature", 0.0)))
        p["tint"] = max(-20.0, min(20.0, p.get("tint", 0.0)))
        p["vibrance"] = max(-1.0, min(1.0, p.get("vibrance", 0.0)))
        
        sat = max(-1.0, min(1.0, p.get("saturation", 0.0)))
        if p["vibrance"] > 0.25 and sat > 0.20:
            sat = 0.10
        p["saturation"] = sat
        p["vignette"] = max(-1.0, min(0.0, p.get("vignette", 0.0)))
        p["grain"] = max(0.0, min(0.5, p.get("grain", 0.0)))
        return RecipeParameters(**p)

    @classmethod
    def validate_and_repair_composition(cls, raw_text: str) -> Tuple[bool, Optional[Envelope[AnalyzeCompositionData]], str]:
        """
        验证并修复构图分析响应，确保 100% 满足 Envelope[AnalyzeCompositionData] 契约。
        """
        cleaned = cls.clean_json_text(raw_text)
        try:
            parsed = json.loads(cleaned)
        except Exception as e:
            return False, None, f"JSON解析失败: {str(e)}"

        if "data" in parsed and "code" in parsed:
            payload = parsed
        else:
            payload = {"code": 200, "message": "success", "request_id": f"req_auto_{uuid.uuid4().hex[:8]}", "data": parsed}

        if "request_id" not in payload:
            payload["request_id"] = f"req_auto_{uuid.uuid4().hex[:8]}"

        data = payload.get("data", {})
        guidance = data.get("composition_guidance", {})
        tip = guidance.get("coach_tip", "建议平稳拍摄")
        if len(tip) > 20:
            guidance["coach_tip"] = tip[:18] + ".."
            data["composition_guidance"] = guidance

        # 修复 CropBox 边界
        cb = guidance.get("suggested_crop_box", {})
        ymin = max(0.0, min(1.0, float(cb.get("ymin", 0.1))))
        xmin = max(0.0, min(1.0, float(cb.get("xmin", 0.1))))
        ymax = max(ymin + 0.1, min(1.0, float(cb.get("ymax", 0.9))))
        xmax = max(xmin + 0.1, min(1.0, float(cb.get("xmax", 0.9))))
        guidance["suggested_crop_box"] = {"ymin": round(ymin, 2), "xmin": round(xmin, 2), "ymax": round(ymax, 2), "xmax": round(xmax, 2)}

        # 修复 NavigationVector
        nav = guidance.get("navigation_vector")
        if nav:
            f_steps = nav.get("forward_steps")
            if f_steps is not None:
                nav["forward_steps"] = max(1, min(3, int(f_steps)))
            h_trans = nav.get("horizontal_translation_m")
            if h_trans is not None:
                nav["horizontal_translation_m"] = round(max(-1.0, min(1.0, float(h_trans))), 2)
            v_trans = nav.get("vertical_translation_cm")
            if v_trans is not None:
                nav["vertical_translation_cm"] = round(max(-30.0, min(30.0, float(v_trans))), 1)
            guidance["navigation_vector"] = nav

        try:
            resp = Envelope[AnalyzeCompositionData].model_validate(payload)
            return True, resp, "OK"
        except ValidationError as ve:
            return False, None, f"Pydantic校验错误: {ve.json()}"

    @classmethod
    def validate_and_repair_retouch(cls, raw_text: str) -> Tuple[bool, Optional[Envelope[AnalyzeAndGradeData]], str]:
        """
        验证并修复调色响应，确保 100% 满足 Envelope[AnalyzeAndGradeData] 契约。
        """
        cleaned = cls.clean_json_text(raw_text)
        try:
            parsed = json.loads(cleaned)
        except Exception as e:
            return False, None, f"JSON解析失败: {str(e)}"

        if "data" in parsed and "code" in parsed:
            payload = parsed
        else:
            payload = {"code": 200, "message": "success", "request_id": f"req_retouch_{uuid.uuid4().hex[:8]}", "data": parsed}

        if "request_id" not in payload:
            payload["request_id"] = f"req_retouch_{uuid.uuid4().hex[:8]}"

        try:
            resp = Envelope[AnalyzeAndGradeData].model_validate(payload)
            # 应用色彩护栏
            if resp.data and resp.data.recommended_recipe:
                params = resp.data.recommended_recipe.parameters
                resp.data.recommended_recipe.parameters = cls.apply_color_guard(params)
            return True, resp, "OK"
        except ValidationError as ve:
            return False, None, f"Pydantic校验错误: {ve.json()}"
