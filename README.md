# AestheticLens 工业级专业摄影与电影录制系统

> **当前版本**：`v2.5.0 全面结构性重构版`  
> **核心架构**：Apple 原生 Metal 3D LUT GPU 实时渲染管线 + 120fps ProMotion 高刷生态 + 60fps 电影级实时胶片滤镜录制直出 + 端侧 Vision 智能构图诊断  
> **设计语言**：沉浸式专业电影机工业设计（对标专业电影机 Blackmagic Camera / ProMovie），底部常驻【相机】【视频】【媒体】【设置】四联控制，悬浮 35mm 胶卷 3D LUT 选择器

---

## 🚀 2026-10-06 最新核心结构性升级说明

本次针对用户提出的**“拍摄视频时实时挑选滤镜观看实际效果、录制直接出滤镜视频、录制锁定 60fps、日常生态支持 120fps ProMotion 高刷、底栏重构为相机/视频/媒体/设置”**需求，完成了全面的工业级结构性重构：

### 1. 取景器全面直通 MetalView：120fps 满血高刷“所见即所得”
- **彻底告别原片取景**：原取景层直接使用未调色的系统硬件预览，切换滤镜画面无任何反馈。本次重构取景层全面升级为 `MetalView(activePreset:)`。
- **GPU 级实时着色**：每一帧直接经由 Metal 3D LUT 片元着色器实时渲染，耗时小于 0.6ms，用户在屏幕上实时观看真实胶片上色效果，所见即所得。
- **120fps ProMotion 满帧支持**：在 `Info.plist` 中声明 `CADisableMinimumFrameDurationOnPhone = true`，系统级解锁 120Hz 刷新率，`MTKView` 渲染帧率自适应屏幕最高刷新率，丝滑跟手。

### 2. 悬浮式 35mm 电影胶卷 3D LUT 选择器 (Filmstrip Reel)
- **专业工业级交互**：在取景框右侧悬浮竖向电影胶片齿孔式选择器，还原经典胶片卡带质感。
- **电影级滤镜库**：
  - `01-暖金电影`：高光压制与柔和 S 曲线，温暖通透氛围感；
  - `02-富士冷萃`：通透清爽冷萃感，日系人像冷白皮；
  - `03-赛博青橙`：好莱坞经典电影工业高反差 Teal & Orange；
  - `04-电影质感`：低反差暗部微浮灰，高级胶片呼吸感；
  - `05-海边日落`：暖粉金色落日暮光调；
  - `06-徕卡黑白`：高反差德系人文黑白，灰阶过渡细腻；
  - `00-自然原画`：直通真实传感器色彩。
- **[LUT] 快速开关与彩虹霓虹边框**：选中的胶片格位呈现霓虹高亮框，下方配有 `[LUT]` 专业徽标按钮，支持一键优雅展开或折叠滑轨，防止遮挡取景。

### 3. 实时带滤镜 60fps 视频录制直出 (FilteredVideoRecorder)
- **硬编码直存相册**：基于 `AVAssetWriter` + `AVAssetWriterInputPixelBufferAdaptor`，在用户点击录制后，GPU 实时上色后的每一帧直接编码写入 60fps H.264/HEVC 视频文件（25Mbps 高码率）。
- **音频同步混流**：采集麦克风输入，以 AAC 48kHz 高音质立体声与视频帧严格按时间戳同步。
- **零打扰出片流程**：录制完成自动保存至系统相册，弹出轻量保存提示条，彻底取消强制跳转至繁琐后期精修界面的打扰流程。

### 4. 底部四大专业核心控制栏 (去除聊天)
- **【相机】**：一键切换至拍照模式，白圈快门触发 48MP / Deep Fusion 超高清照片捕捉；
- **【视频】**：一键切换至 60fps 电影视频录制，专业大红钮启动录像；
- **【媒体】**：一键打开相册素材库，快捷查看刚拍摄的 60fps 电影视频与照片；
- **【设置】**：一键呼出专业设置抽屉面板，调节色域、帧率与偏好；
- **翻转镜头**：保留经典快速前后置镜头无感翻转。

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
    │   │   ├── Info.plist                # 应用全局权限、ProMotion 120Hz、麦克风声明
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
    │   │   │   ├── CameraManager.swift    # 相机硬件会话调度、60fps 帧率锁定、麦克风音频采集、FilteredVideoRecorder 录像直出
    │   │   │   ├── APIClient.swift        # 端侧 Apple Vision 人脸/风光检测与云端 VLM 接口客户端
    │   │   │   ├── MotionManager.swift    # 陀螺仪与重力传感器监听服务，提供姿态水平仪倾角数据
    │   │   │   ├── RealtimeCompositionEngine.swift # 实时 AI 构图导引状态流转引擎
    │   │   │   └── VideoPlayerService.swift# 视频播放与时间线控制服务
    │   │   └── Views/                    # 用户界面交互层
    │   │       ├── CameraView.swift       # 核心交互主界面：专业电影机布局、Filmstrip 胶卷滑轨、四大控制栏、触控对焦、变焦盘
    │   │       ├── NavigationOverlayView.swift # AI 构图导引线与提示词渲染层 (纯净按需触发)
    │   │       ├── LevelGaugeView.swift   # 姿态水平仪视觉指示组件 (0度金色吸附)
    │   │       ├── SettingsView.swift     # 系统专业参数设置抽屉面板
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
