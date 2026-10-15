# AestheticLens-AI 代码仓库 (code)

本目录为整个项目的**代码统一保存目录**，严格遵循架构规范归档。

## 📂 目录与文件详细功能说明书

- **`app/`**：云端后端服务核心代码（FastAPI 微服务应用）
  - `main.py`：微服务主入口，负责挂载路由、全局中间件、CORS、汉化 Swagger UI (`/docs`) 以及托管桌面端真机仿真器根路由；
  - `api/v1/`：提供给 iOS 端与 Web 仿真器调用的核心业务 RESTful API：
    - `health.py`：系统健康探针接口 (`/health`)；
    - `auth.py`：设备匿名注册与 JWT 令牌下发 (`/auth/device-register`)；
    - `vision.py`：实时构图分析与机位空间微调导航 (`/vision/analyze-composition`)，以及新增的 **AI 连通性排查诊断探针 (`/vision/check-ai-status`)**；
    - `retouch.py`：拍后 10 维可逆胶片调色诊断 (`/retouch/analyze-and-grade`)；
    - `assets.py`：3D LUT 胶卷资产元数据与贴图下发 (`/assets/luts`)；
  - `core/`：系统核心支撑与安全防护：
    - `config.py`：全局环境配置（支持自动加载本地 `.env`、VLM 弹性超时阈值 `VLM_TIMEOUT_SECONDS` 配置等）；
    - `security.py`：基于 HS256 的 JWT 令牌签名与鉴权依赖；
    - `limiter.py`：滑动窗口限流器（1.5 秒/次频控防护）；
    - `middleware.py`：PayloadGuard 载荷守卫中间件（抽帧 200KB、成片 2.5MB 上限拦截）；
  - `prompt/`：AI 提示词工程与美学专家 Skill：
    - `photography_skill.py`：四维美学提示词编排与 JSON 校验自愈修复引擎；
  - `schemas/`：Pydantic 请求体与响应体 Schema 定义（包含新增的 `AIDiagnostics` 元数据）；
  - `services/`：外部大模型协同中枢：
    - `vlm_service.py`：阿里云百炼 Qwen-VL-Plus 调用调度、弹性超时熔断保护、DashScope 网络探针与离线黄金数据桩兜底；
- **`client/`**：iOS 原生客户端工程（SwiftUI + Metal）
  - `AestheticLens.xcodeproj`：Xcode 工程配置文件；
  - `AestheticLens/`：原生应用源码，涵盖 MetalRenderer (120fps 实时 3D LUT 渲染)、CameraManager (0.1x 无级变焦)、APIClient (端云双引擎通信与无 Key 毫秒级 Vision 兜底)；
- **`static/`**：静态资产与电脑端交互仿真器
  - `simulator.html`：电脑端 1:1 免安装 iPhone 仿真交互工作台（具备自适应 API 网关探测、AI 状态 HUD 指示灯、网络设置抽屉与纯离线极速仿真引擎）；
- **`tests/`**：自动化单元与集成测试套件（运行 `python -m pytest -v` 执行全部 31 项测试）
  - `test_vision_ai_diagnostics.py`：**最新构建的 AI 构图调用排查与自动化验收测试套件**（覆盖在线成功、超时熔断、401 失效、免 Key 兜底、请求头透传等 6 大核心验收项）；
  - `test_vision.py`：基础构图接口测试；
  - `test_auth.py`：设备注册与鉴权测试；
  - `test_health.py`：健康探针测试；
  - `test_limiter.py`：滑动窗口限流保护测试；
  - `test_retouch.py`：拍后调色配方测试；
  - `test_video_retouch.py`：视频调色测试；
  - `test_photography_skill.py`：美学专家 Skill 提示词与容错测试；
  - `test_e2e_integration.py`：端到端集成测试；
- **`poc/`**：算法与多模态模型评测验证脚本（VLM Benchmark 与基准数据集）；
- **`open_pc_preview.bat`**：Windows 一键双击直接启动电脑端真机交互仿真器脚本；
- **`Dockerfile`** / **`docker-compose.yml`** / **`docker_run.ps1`**：容器化打包与一键启动脚本；
- **`requirements.txt`**：Python 依赖包清单；
- **`.env.example`**：服务端环境变量配置示例。

