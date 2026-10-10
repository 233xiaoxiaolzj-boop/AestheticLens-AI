# AestheticLens 灵瞳相机 · 工业级专业全栈电影相机

AestheticLens 是一款专为摄影发烧友与创作者打造的高性能专业电影相机 iOS 原生应用。融合现代高品质黑金专业摄影美学，以苹果 Metal GPU 驱动全链路 120fps 高刷上色取景与 60fps 电影视频直录直出，并深度对标 Doka 相机与专业摄影“做减法”理念，集成阿里云多模态大模型与端侧真实多维视觉双引擎。

---

## 🌟 核心功能与最新升级特性 (Latest v3.2)

### 1. 0.1x 丝滑连续变焦轮 (防卡死增量引擎)
- **手势冲突彻底清除与即时位移增量驱动**：重构变焦盘手势响应链路，剥离原生 Button 拦截，改用原生高优先级手势与即时增量位移（Incremental Delta）引擎。无论滑动幅度大小均能实现 **0.1x 细腻步进无级微调**，伴随清脆细腻的触觉震动反馈，彻底解决滑动卡住与失灵问题；
- **动态匹配手机长焦硬件性能**：自适应读取手机摄像头硬件的最大可用变焦倍率（`maxAvailableVideoZoomFactor`），最高可平滑拉伸至 10x ~ 15x 超长焦空间压缩；
- **双模快捷操控**：刻度盘上方常驻 `.5`、`1×`、`2`、`3`、`5` 快捷微胶囊，轻触直接跳转，滑动则无级平滑变焦；
- **1:1 原生硬件倍率对齐**：深度对齐 iOS 虚拟多摄设备底层物理镜头切换点（`virtualDeviceSwitchOverVideoZoomFactors`），UI 0.5x 对应硬件超广角，1.0x 严格对应广角主摄，告别虚大变形。

### 2. AI 实时场景真实动态识别与场景构建（消灭写死文案）
- **真实场景实时感知（双引擎驱动）**：
  - **端侧 Vision 深度多维感知引擎**：
    - 集成苹果 `VNClassifyImageRequest`：实时识别当前画面真实场景类别（案头桌案/电子设备、室内生活、自然山野、花卉植物、餐饮美食、建筑街景等）；
    - 集成 `VNGenerateAttentionBasedSaliencyImageRequest`：实时提取画面视觉注意力显著焦点坐标 `(saliencyCenter)` 与主体轮廓边界；
    - 集成真实像素采样与高光定位算法：计算全画幅平均亮度与高光倾泻方向（如“左上方透射斜射光”）；
    - 集成 `VNDetectFaceRectanglesRequest`：实时识别人脸位置、距离与构图占比；
    - **彻底废除所有写死的假文案**：无论处于什么场景，端侧与云端均 100% 根据当前镜头画面的真实计算数据动态推导输出场景解构、光影建议与最佳机位！
  - **阿里云灵积 (Qwen-VL-Plus) 实时深度大模型**：
    - 支持直接上传当前帧并调用多模态大模型进行深度解构（如人像在山野中的三分线黄金机位、阳光透射丁达尔效应的高光压暗与顺光反差拍摄指导）；
    - 智能卡片顶部清晰标识分析来源（【阿里云灵积 Qwen-VL-Plus】或【端侧神经视觉引擎 (Vision Pro)】）。
- **AI 大师场景卡片浮层**：点击【✨ AI 分析】后在取景器自动弹出精致的“场景解构”、“光影技巧”、“最佳机位”卡片，并提供 `[📷 一键推荐焦段]` 与 `[🎨 一键应用风格]` 快捷按钮。

### 3. 默认原镜头色彩 (True-to-Life RAW) & 随心调色
- **打开相机默认保持原镜头真实色彩**：应用启动时默认开启 `00-原画`，Metal 片元着色器直通原生摄像头传感器原始帧，关闭 LUT 滤镜，忠实还原环境原色；
- **胶卷轮盘首位常驻 `00-原画 (RAW)`**：胶卷选择器第一个选项为“00-原画 (RAW)”，用户可随时一键切回原生真实画质；
- **大师胶卷按需即时切换**：向右滑动胶卷轮盘即可随心切换 `01-暖金`、`02-富士`、`03-青橙`、`06-黑白` 等高品质电影胶卷。

### 4. 拍照成片 3D LUT 胶卷色彩全链路烘焙
- **所见即所拍，成片 100% 带滤镜**：拍照触发时，系统捕获的高清大图自动进入 Metal 离屏渲染管线，执行标准 512x512 3D LUT 片元着色器烘焙，无论选择暖金、富士、青橙还是黑白，导出的照片均带有浓郁的胶片色彩；
- **自然原画直通保真**：选择 `00-原画` 时自动绕过着色器，100% 保持传感器原生动态范围与真实光影。

### 5. App 内部沉浸式成片大图检视器 (内建回放与系统分享)
- **快门旁成片实时缩略图反馈**：拍照成功后，快门右侧圆钮立即切换为最新成片的圆角缩略图，外圈点缀专业微金色光环，并伴随弹性回弹触觉反馈；
- **App 内部即时全屏检视**：轻触缩略图或点击底部【媒体】导航，无需切换至系统相册，即可在应用内全屏欣赏带滤镜的成片大图；
- **手势双击/捏合平滑缩放**：支持双击放大或双指捏合无级缩放检视焦点细节；
- **电影级元数据 HUD 与系统分享**：底部实时呈现所用胶卷、拍摄焦段倍率、时间戳与原图分辨率，右上角集成 iOS 系统分享面板（支持 AirDrop 隔空投送、微信发送等）。

### 4. AI 构图防微抖低通滤波与双门槛迟滞磁吸 (Hysteresis Snap)
- **一阶低通滤波平滑（$\alpha=0.28$）**：针对人手生理 3~5Hz 微抖引入低通滤波平滑算法，彻底消除准星与目标晃动；
- **双门槛迟滞磁吸**：进入对齐容差 8.5%，脱离容差 14.0%，对准后自动锁定 **1.5 秒从容快门窗口（Sticky Lock Window）**，并伴随触觉微震与翠绿发光脉冲，不再因呼吸或微小抖动丢失最佳角度。

### 5. 严谨 4:3 几何保真与全系统原生横屏拍摄自适应
- **拒绝画面上下拉伸**：拍照模式严格锁定 4:3 传感器几何视口，避免拉伸变形；
- **横屏自适应**：监听重力传感器物理方向，横屏握持时，所有 HUD 按钮、图标、胶卷标签、变焦文字、快门图标均平滑原地旋转 90°/270°，底层的照片 EXIF 元数据与 60fps 视频录制写入器自动锁定横屏方向。

### 6. 120fps Metal GPU 高刷取景与 60fps 电影滤镜视频录制直出
- **所见即所得**：取景层直通 `MetalView`，基于 512x512 3D LUT 片元着色器实时上色，打满 iPhone Pro 120Hz ProMotion 高刷；
- **60fps 电影视频硬编码**：`FilteredVideoRecorder` 硬编码直存相册，音频 48kHz AAC 同步混流。

---

## 📂 项目全目录结构与文件功能透明说明书

依据全局开发规范，所有源代码严格归档于 `code/` 目录下，根目录保持极简。

```
AI camera/
├── AestheticLens.ipa                     # 最新自动打包生成的 iOS 原生测试安装包 (Release)
├── README.md                             # 项目总体架构与功能说明书 (本文档)
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
    │   │   │   ├── MetalRenderer.swift   # Metal 单例渲染中枢：3D LUT 实时上色、120fps 取景渲染与视频录像着色
    │   │   │   ├── MetalView.swift       # MTKView 与 SwiftUI 桥接组件，打满 120fps ProMotion 高刷
    │   │   │   └── Shaders.metal         # Metal 着色器：512x512 3D LUT 片元插值与直通着色器
    │   │   ├── Resources/
    │   │   │   └── luts/                 # 爆款电影级 3D LUT 纹理资源库
    │   │   │       ├── lut_film_warm_01.png       # 01-暖金电影 / 电影质感 LUT
    │   │   │       ├── lut_clean_bright_02.png    # 02-富士冷萃 LUT
    │   │   │       ├── lut_cyber_teal_orange_03.png# 03-赛博青橙 LUT
    │   │   │       ├── lut_mono_contrast_04.png   # 06-徕卡黑白 LUT
    │   │   │       └── lut_identity.png           # 00-自然原画直通 LUT
    │   │   ├── Services/                 # 底层系统与硬件服务层
    │   │   │   ├── CameraManager.swift    # 相机硬件会话调度：0.1x 变焦连续节流、长焦动态匹配、60fps 视频录像
    │   │   │   ├── APIClient.swift        # 阿里云灵积 Qwen-VL-Plus 深度解构 + 端侧 Apple Vision 真实多维感知双引擎
    │   │   │   ├── MotionManager.swift    # 陀螺仪与重力传感器监听服务，提供姿态水平仪倾角数据
    │   │   │   ├── RealtimeCompositionEngine.swift # 灵瞳 AI 构图引擎：场景分析语言发布、抗微抖低通滤波、迟滞磁吸
    │   │   │   └── VideoPlayerService.swift# 视频播放与时间线控制服务
    │   │   └── Views/                    # 用户界面交互层
    │   │       ├── CameraView.swift       # 核心交互主界面：0.1x 丝滑连续变焦盘、AI 场景分析语言卡片、四联导航、横屏自适应
    │   │       ├── NavigationOverlayView.swift # 电影级黄金 AR 取景框、角标、主体最佳机位胶囊与防抖对齐准星
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
- 产物可以直接在根目录下获取 `AestheticLens.ipa`，通过 TrollStore、AltStore 或自签名工具快速安装到真实 iPhone 设备上进行实测。
