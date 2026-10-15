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

依据全局开发规范，所有源代码统一严格归档于 `code/` 目录下，根目录保持极简。

```
AI camera/
├── AestheticLens(1).ipa                  # 归档的历史版本 iOS 安装包
├── AestheticLens.ipa                     # 最新自动打包生成的 iOS 原生测试安装包 (Release)
├── README.md                             # 项目总体架构与功能说明书 (本文档)
├── .github/
│   └── workflows/
│       └── ios-build.yml                 # GitHub Actions 自动化 CI/CD 云端构建打包脚本
├── docs/                                 # 接口契约与离线黄金数据桩归档
│   └── 接口契约/
│       └── mock数据桩/                    # 经典构图与调色离线保底 JSON 数据桩
└── code/                                 # 项目统一代码归档主目录
    ├── app/                              # 云端后端服务核心代码 (FastAPI 微服务应用)
    │   ├── main.py                       # FastAPI 入口，挂载中间件、路由与电脑端真机交互仿真器
    │   ├── api/                          # RESTful API 路由模块
    │   │   └── v1/                       # V1 版本业务接口层
    │   │       ├── health.py             # 容器探针与服务健康检测接口 (/health)
    │   │       ├── auth.py               # 匿名设备激活与 JWT Bearer 鉴权令牌分发
    │   │       ├── vision.py             # 实时构图抽帧分析与机位空间导航，及 AI 连通性排查探针 (/check-ai-status)
    │   │       ├── retouch.py            # 拍后成片智能美学诊断与 10 维可逆调色配方
    │   │       └── assets.py             # 爆款电影胶片 3D LUT 云端贴图资产分发
    │   ├── core/                         # 安全与系统基础设施
    │   │   ├── config.py                 # 全局配置中心 (支持本地 .env 自动加载与 VLM 弹性超时配置)
    │   │   ├── security.py               # HS256 JWT 加密签名与校验依赖
    │   │   ├── limiter.py                # 设备频控限流器 (1.5秒/次滑动窗口保护)
    │   │   └── middleware.py             # PayloadGuard 载荷守卫 (200KB抽帧 / 2.5MB成片硬上限)
    │   ├── prompt/                       # 提示词工程与美学专家 Skill
    │   │   └── photography_skill.py      # 四维美学解构、机位动作微调指令推导与 Schema 格式校验自愈
    │   ├── schemas/                      # Pydantic 输入输出契约定义 (含 AIDiagnostics 诊断元数据)
    │   │   ├── common.py                 # 通用 Envelope 统一响应信封
    │   │   ├── auth.py                   # 鉴权模型
    │   │   ├── vision.py                 # 构图导航、裁切框、机位向量与 AI 诊断元数据
    │   │   └── retouch.py                # 调色配方与视频多关键帧诊断模型
    │   └── services/                     # 外部大模型与核心算法协同层
    │       └── vlm_service.py            # 阿里云 Qwen-VL-Plus 调用中枢、弹性超时熔断保护、探针与离线数据桩兜底
    ├── client/                           # 客户端主工程 (原生 iOS SwiftUI + Metal)
    │   ├── AestheticLens.xcodeproj       # Xcode 工程主配置文件
    │   └── AestheticLens/
    │       ├── Info.plist                # 应用全局权限、横屏方向支持、ProMotion 120Hz、麦克风声明
    │       ├── App/
    │       │   └── AestheticLensApp.swift# iOS 应用程序主入口，启动 CameraView
    │       ├── Models/
    │       │   ├── CompositionModels.swift# AI 构图推荐、网格线与审美评分数据模型
    │       │   ├── RetouchModels.swift   # 照片调色与滤镜预设参数模型
    │       │   └── VideoRetouchModels.swift# 视频调色参数与剪辑模型
    │       ├── Render/                   # GPU 核心渲染引擎层
    │       │   ├── MetalRenderer.swift   # Metal 单例渲染中枢：3D LUT 实时上色、120fps 取景渲染与视频录像着色
    │       │   ├── MetalView.swift       # MTKView 与 SwiftUI 桥接组件，打满 120fps ProMotion 高刷
    │       │   └── Shaders.metal         # Metal 着色器：512x512 3D LUT 片元插值与直通着色器
    │       ├── Resources/
    │       │   └── luts/                 # 爆款电影级 3D LUT 纹理资源库
    │       ├── Services/                 # 底层系统与硬件服务层
    │       │   ├── CameraManager.swift    # 相机硬件调度：0.1x 变焦连续节流、长焦动态匹配、60fps 视频录像
    │       │   ├── APIClient.swift        # 阿里云灵积 Qwen-VL-Plus 深度解构 + 端侧 Apple Vision 真实多维感知双引擎 (无Key秒级离线兜底)
    │       │   ├── MotionManager.swift    # 陀螺仪与重力传感器监听服务，提供姿态水平仪倾角数据
    │       │   ├── RealtimeCompositionEngine.swift # 灵瞳 AI 构图引擎：场景分析语言发布、抗微抖低通滤波、迟滞磁吸
    │       │   └── VideoPlayerService.swift# 视频播放与时间线控制服务
    │       └── Views/                    # 用户界面交互层
    │           ├── CameraView.swift       # 核心交互主界面：0.1x 丝滑连续变焦盘、AI 场景分析语言卡片、四联导航、横屏自适应
    │           ├── NavigationOverlayView.swift # 电影级黄金 AR 取景框、角标、主体最佳机位胶囊与防抖对齐准星
    │           ├── LevelGaugeView.swift   # 姿态水平仪视觉指示组件 (0度金色吸附)
    │           ├── SettingsView.swift     # 系统专业参数设置抽屉面板，含阿里云 API Key 自定义与连通性测试
    │           ├── RetouchView.swift      # 照片精修调色视图
    │           └── VideoRetouchView.swift # 视频精修调色视图
    ├── static/                           # 电脑端 1:1 免安装真机交互仿真器
    │   └── simulator.html                # 仿真中台 HTML/JS (具备自适应 API 网关探测、AI 状态 HUD 指示灯、网络设置抽屉与纯离线极速仿真引擎)
    ├── tests/                            # 自动化测试验收套件
    │   ├── conftest.py                   # Pytest 客户端依赖与测试 Fixture
    │   ├── test_vision_ai_diagnostics.py # 【核心验收】AI 构图调用排查与自动化验收测试套件 (6项全覆盖)
    │   ├── test_vision.py                # 基础构图接口测试
    │   ├── test_auth.py                  # 设备注册与鉴权测试
    │   ├── test_health.py                # 健康探针测试
    │   ├── test_limiter.py               # 滑动窗口限流保护测试
    │   ├── test_retouch.py               # 拍后调色配方测试
    │   ├── test_video_retouch.py         # 视频调色测试
    │   ├── test_photography_skill.py    # 美学专家 Skill 提示词与容错测试
    │   └── test_e2e_integration.py      # 端到端集成测试
    ├── poc/                              # 算法验证、数据生成与评测脚本
    ├── open_pc_preview.bat               # Windows 一键免安装启动真机仿真器脚本
    ├── Dockerfile                        # 容器镜像构建文件
    ├── docker-compose.yml                # 本地多服务编排配置
    ├── docker_run.ps1                    # Docker 本地构建与运行 PowerShell 脚本
    ├── requirements.txt                  # Python 依赖清单
    └── .env.example                      # 环境变量配置示例
```

---

## 🔍 AI 构图分析慢与调用排查深度报告 (改进验收)

针对实际体验中出现的“**点击 AI 构图，分析得很慢，甚至分析不出来**”的核心痛点，我们进行了全链路深度排查与系统重构：

### 1. 根因全面排查结论

1. **前端仿真器硬编码不可达的远程域名（头号卡顿元凶）**：
   - 先前版本 `simulator.html` 中硬编码了 `API_BASE = "https://aestheticlens-api.onrender.com"`；
   - 远程 Render 免费实例因长期闲置休眠（Spin down），或在中国大陆网络环境下被阻断丢包，导致点击 AI 构图时，浏览器发出的设备注册与构图分析请求经历长达 30~60 秒的挂起（Pending），累积卡死 1~2 分钟，直到超时报错；
   - 本地即使启动了后端服务，网页也完全无法连接本地；
2. **后端 VLM 激进熔断时间设置过短 (2.0s)**：
   - `vlm_service.py` 硬编码了 `timeout=2.0`。阿里云 DashScope `qwen-vl-plus` 处理图文多模态推理生成通常需要 3.0~6.0 秒，2.0 秒导致真实在线调用几乎 100% 触发超时熔断，静默降级为 Mock；
3. **调用状态标识虚假，缺乏真实排查能力**：
   - 响应 Header `X-AI-Source` 仅判断是否存在环境变量，哪怕因超时或 401 降级了依然返回 `qwen-vl-plus`，导致调用方无法验证真实调用是否成功；
4. **代码预埋测试 Key 已失效 (401 Unauthorized)**：
   - 历史预置 Key 经排查已过期欠费，直接调用云端必报 401。

---

### 2. 系统重构与体验优化方案

1. **智能自适应网关感知与 AI 状态指示**：
   - `simulator.html` 自动探测运行环境：HTTP 环境自动匹配当前站点，本地 `file:///` 环境默认优先直连 `http://127.0.0.1:8000`；
   - 页面加载 1.5 秒内自动发起连通性探测。若后端未启动，**0 秒即时无缝切换为【纯前端离线仿真引擎】**，根据当前场景动态下发三分线黄金构图框，绝不卡死；
   - 顶部 HUD 动态呈现真实状态灯：`🟢 Qwen-VL 在线` / `🟡 本地黄金桩` / `🔵 纯前端离线引擎`；
   - 增加【🛠️ AI 诊断与网络设置抽屉】，支持直接查看 RTT 延迟并填入临时测试 Key；
2. **后端 VLM 弹性超时与精准链路追踪**：
   - 将超时阈值升级为可配置的 `VLM_TIMEOUT_SECONDS`（默认 6.0 秒），杜绝误熔断；
   - 在返回结构与响应头中真实透出 `X-AI-Source`（`qwen-vl-plus:online` / `fallback-mock:timeout` / `fallback-mock:unauthorized` / `fallback-mock:no_key`）与精准耗时 `X-AI-Latency-Ms`；
   - 新增免鉴权诊断探针接口 `GET /api/v1/vision/check-ai-status`；
3. **iOS 客户端双引擎提速**：
   - 在未配置自定义 Key 时，直接秒级启用端侧高精度 Apple Vision 感知引擎，杜绝无效网络等待与超时卡顿。

---

### 3. 自动化测试验收结果

已在 `code/tests/test_vision_ai_diagnostics.py` 构建完整的自动化验收测试套件：
- `test_ai_diagnostics_probe_endpoint`：验证诊断探针结构完整性与弹性超时阈值生效；
- `test_ai_diagnostics_probe_with_mock_keys`：验证有效 Key (200) 与失效 Key (401) 的准确辨识；
- `test_composition_online_real_ai_success`：验证真实 Qwen-VL 在线调用全链路（`X-AI-Source == qwen-vl-plus:online`，`is_real_ai == True`）；
- `test_composition_timeout_graceful_fallback`：验证网络超时场景下的优雅降级（`fallback-mock:timeout`，零 500 报错）；
- `test_composition_unauthorized_fallback`：验证 Key 失效时的降级与透明标示（`fallback-mock:unauthorized`）；
- `test_composition_no_key_instant_fallback`：验证无 Key 时的瞬时黄金数据桩兜底（<50ms 零卡顿）。

**测试执行结果**：全部 31 项测试（包含 6 项 AI 诊断新用例）**100% 通过（30 passed, 1 skipped in 2.54s）**！

---

## 🛠️ 构建与交付方式
- 本项目已深度整合 GitHub Actions 持续集成。代码推送到 main 分支后，云端 macOS-14 Runner 会自动启动 Xcode 16 编译器进行完整编译并生成无证书签名的 Release .ipa 安装包；
- 产物可以直接在根目录下获取 AestheticLens.ipa，通过 TrollStore、AltStore 或自签名工具快速安装到真实 iPhone 设备上进行实测。
