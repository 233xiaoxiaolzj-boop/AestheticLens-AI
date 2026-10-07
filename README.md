# AestheticLens 灵瞳相机 · 工业级专业全栈电影相机

AestheticLens 是一款专为摄影发烧友与创作者打造的高性能专业电影相机 iOS 原生应用。融合现代高品质黑金专业摄影美学，以苹果 Metal GPU 驱动全链路 120fps 高刷上色取景与 60fps 电影视频直录直出，并深度对标 Doka 相机与专业摄影“做减法”理念，集成阿里云多模态大模型与端侧视觉双引擎。

---

## 🌟 核心功能与最新重构亮点

### 1. 变焦倍率物理硬件 1:1 对齐与原生级上半圆弧形变焦轮 (Upper Arc Dial)
- **解决 1x 错位痛点**：底层深度解析 iOS 虚拟多摄系统的硬件镜头切换点（`virtualDeviceSwitchOverVideoZoomFactors`），将 UI 上的 `0.5×`、`1.0×`、`2.0×`、`3.0×` 与物理 iPhone 原生相机的超广角、广角主摄和长焦镜头进行 1:1 绝对映射，彻底解决 1x 相当于 0.5x 超广角的问题。
- **快门正上方弧度拨盘**：变焦轮重构移至拍摄按键正上方，平时呈常驻紧凑焦段胶囊行（`.5`、`1×`、`2`、`3`），滑动或长按展开为优雅向上的**上半圆弧形刻度盘（Upper Arc Dial）**，带细腻微刻度与当前数字倍率，支持顺滑无级变焦与轻微触觉反馈。

### 2. AI 探景与局部黄金区域圈选 (阿里云 Qwen-VL + Apple Vision 100% 成功双保底)
- **多模态大模型视觉减法**：全景扫描画面，自动识别是“风光建筑（Landscape）”还是“人物肖像（Portrait）”，遵循“摄影做减法”原则，避开杂乱人群与无用前景，圈定最佳黄金局部区域（`CropBox`），并推荐最佳焦段（如 2.5x 或 3.0x 空间压缩）与胶片色调。
- **高可用零失败保障架构**：
  - 端侧精准图片压缩控制在 150KB 内，防止弱网上传超时；
  - 设置页支持自定义配置阿里云灵积 DashScope API Key，支持一键连通性测试与持久化；
  - 遇到弱网、无网络或大模型限流时，**毫秒级零感自动降级到端侧 Apple Vision 神经引擎**，人脸人像/显著度注意力分析保底，100% 保证用户点击必有响应，绝不卡死。

### 3. AI 构图防微抖低通滤波与双门槛迟滞磁吸 (Hysteresis Snap)
- **一阶低通滤波（EMA）**：针对人手生理 3~5Hz 微抖引入平滑滤波算法（$\alpha=0.28$），彻底消除手部微颤导致的准星抖动。
- **双门槛迟滞磁吸**：进入对齐容差 8.5%，脱离容差 14.0%，对准后自动锁定 **1.5 秒从容快门窗口（Sticky Lock Window）**，并伴随触觉微震与翠绿发光脉冲，不再因呼吸或微小晃动而丢失最佳角度。

### 4. 严谨 4:3 几何保真与全系统原生横屏拍摄自适应
- **拒绝画面上下拉伸**：拍照模式严格锁定 4:3 传感器几何视口，避免拉伸变形。
- **横屏自适应**：监听重力传感器物理方向，横屏握持时，所有 HUD 按钮、图标、胶卷标签、变焦文字、快门图标均平滑原地旋转 90°/270°，底层的照片和 60fps 视频录制底层方向自动同步。

### 5. 120fps Metal GPU 高刷取景与 60fps 电影滤镜视频录制直出
- **所见即所得**：取景层直通 `MetalView`，基于 512x512 3D LUT 片元着色器实时上色，打满 iPhone Pro 120Hz ProMotion 高刷。
- **60fps 电影视频硬编码**：`FilteredVideoRecorder` 硬编码直存相册，音频 48kHz AAC 同步混流，零打扰流程。

### 6. 底部四联专业导航栏
- **【相机】**：48MP 高清拍照，白圈快门；
- **【视频】**：60fps 电影级视频录制，红点录像；
- **【媒体】**：素材库相册快捷检视；
- **【设置】**：阿里云灵积 API Key 配置、高刷参数与连通性测试。

---

## 📂 项目全目录结构与文件功能透明说明书

依据全局开发规范，所有源代码严格归档于 `code/` 目录下，根目录保持极简：

```
AI camera/
├── AestheticLens.ipa                     # 最新自动打包生成的 iOS 原生测试安装包
├── README.md                             # 项目总体架构与功能说明书 (本文件)
├── .github/
│   └── workflows/
│       └── ios-build.yml                 # GitHub Actions 自动化 CI/CD 云端构建打包脚本
└── code/
    ├── client/                           # 客户端主工程 (原生 iOS SwiftUI + Metal)
    │   ├── AestheticLens.xcodeproj       # Xcode 工程主配置文件
    │   ├── AestheticLens/
    │   │   ├── Info.plist                # 应用全局权限、横屏方向支持、ProMotion 120Hz、麦克风声明
    │   │   ├── App/
    │   │   │   └── AestheticLensApp.swift# iOS 应用程序主入口，启动 CameraView
    │   │   ├── Models/
    │   │   │   ├── CompositionModels.swift# AI 构图推荐、网格线与审美评分数据模型
    │   │   │   ├── RetouchModels.swift   # 照片调色与滤镜预设参数模型
    │   │   │   └── VideoRetouchModels.swift# 视频调色参数与剪辑模型
    │   │   ├── Render/                   # GPU 核心渲染引擎层
    │   │   │   ├── MetalRenderer.swift   # Metal 单例渲染中枢：3D LUT 实时上色、120fps 取景渲染、60fps 录像离屏上色
    │   │   │   ├── MetalView.swift       # MTKView 与 SwiftUI 桥接组件，打满 120fps ProMotion 高刷
    │   │   │   └── Shaders.metal         # Metal 着色器：512x512 3D LUT 片元插值与直通着色器
    │   │   ├── Resources/
    │   │   │   └── luts/                 # 爆款电影感 3D LUT 纹理资源库
    │   │   │       ├── lut_film_warm_01.png       # 01-暖金电影 / 电影质感 LUT
    │   │   │       ├── lut_clean_bright_02.png    # 02-富士冷萃 LUT
    │   │   │       ├── lut_cyber_teal_orange_03.png# 03-赛博青橙 LUT
    │   │   │       ├── lut_mono_contrast_04.png   # 06-徕卡黑白 LUT
    │   │   │       └── lut_identity.png           # 00-自然原画直通 LUT
    │   │   ├── Services/                 # 底层系统与硬件服务层
    │   │   │   ├── CameraManager.swift    # 相机硬件会话调度、物理倍率 1:1 对齐、横屏方向锁定、60fps 视频录像
    │   │   │   ├── APIClient.swift        # 阿里云灵积 Qwen-VL-Plus + 端侧 Apple Vision 视觉双引擎，100% 成功保底
    │   │   │   ├── MotionManager.swift    # 陀螺仪与重力传感器监听服务，提供姿态水平仪倾角数据
    │   │   │   ├── RealtimeCompositionEngine.swift # 灵瞳 AI 构图引擎：抗微抖低通滤波、双门槛迟滞磁吸、目标 CropBox 追踪
    │   │   │   └── VideoPlayerService.swift# 视频播放与时间线控制服务
    │   │   └── Views/                    # 用户界面交互层
    │   │       ├── CameraView.swift       # 核心交互主界面：快门正上方上半圆弧变焦盘、✨AI探景、Filmstrip 胶卷滑轨、四联导航、横屏自适应
    │   │       ├── NavigationOverlayView.swift # 电影级黄金 AR 取景框、角标、场景识别胶囊与防抖对齐准星
    │   │       ├── LevelGaugeView.swift   # 姿态水平仪视觉指示组件 (0度金色吸附)
    │   │       ├── SettingsView.swift     # 系统专业参数设置抽屉面板，含阿里云 API Key 自定义与连通性测试
    │   │       ├── DebugSourceSheet.swift # 调试与传感器源状态面板
    │   │       ├── RetouchView.swift      # 照片精修调色视图
    │   │       └── VideoRetouchView.swift # 视频精修调色视图
    │   └── dist/
    │       └── AestheticLens.ipa         # 打包分发归档目录下的 IPA 安装包
    ├── server/                           # 后端智能视觉服务 (Python FastAPI / VLM)
    │   ├── main.py                       # 后端 API 入口，提供实时图像构图推理接口
    │   ├── requirements.txt              # 后端 Python 依赖库清单
    │   └── services/
    │       └── vlm_service.py            # 多模态视觉大模型服务调用封装
    └── poc/                              # 算法验证与离线数据生成脚本
        └── generate_lut_textures.py      # 512x512 3D LUT PNG 纹理离线数学生成器
```

---

## 🛠️ 构建与交付方式
- 本项目已深度整合 GitHub Actions 持续集成。代码推送到 `main` 分支后，云端 macOS-14 Runner 会自动启动 Xcode 16 编译器进行完整编译并生成无证书签名的 Release `.ipa` 安装包；
- 产物可直接通过 TrollStore、AltStore 或自签名工具快速安装到真实 iPhone 设备上进行实测。
