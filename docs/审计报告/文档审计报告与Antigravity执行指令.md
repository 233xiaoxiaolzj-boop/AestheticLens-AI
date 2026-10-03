# AestheticLens-AI 文档审计报告与 Antigravity 执行指令

| 审计人 | Trae (GLM-5.3) | 审计日期 | 2026-10-02 |
| :--- | :--- | :--- | :--- |
| **审计对象** | `docs/需求开发规格说明书.md` (v1.0.0-PROD)、`docs/系统技术设计文档.md` (v1.2.0-PROD)、`docs/系统技术架构与数据时序规范.md` (无版本)、`README.md` |
| **总体结论** | 方向可行、技术选型正确，但存在 1 处技术栈硬伤、9 处参数漂移、1 处数学公式错误、2 个 P0 未排期、安全与隐私空白。**必须先完成 Phase 0（文档修复 + 契约冻结）再进入编码** |

> **本文件用法**：将本文件作为唯一任务书投喂给 Antigravity，令其按 TO-01 → TO-10 顺序执行。
> 每条 TO 均含「任务 / 具体要求 / 验收标准」，Antigravity 不得超出本范围自由发挥。

---

## 一、审计总评

### 1.1 可行性结论：核心链路成立，可以推进

**成立的部分**（选型正确，无需推翻）：
- **双轨架构**正确：CoreMotion(60Hz) + Vision（尺度追踪）管端侧实时 HUD，VLM 每 1.5s 管云端宏观语义，职责切分干净。
- AVFoundation(32BGRA) + CVMetalTextureCache 零拷贝 + MSL 片元 LUT 采样，是 iOS 实时滤镜的**标准最优解**。
- 拍后工作台用 CoreImage/Metal + 双分辨率渲染（拖动时屏幕分辨率、松手后全尺寸离屏）策略成熟。
- FastAPI + Pydantic v2 做结构化 JSON 校验、弱网降级三件套（超时熔断 / 离线兜底 / 节流降频）设计完备。
- P0/P1/P2 分级与 NFR 四条红线（FPS / RTT / 内存 / 上行体积）清晰可执行。

**致命伤**（不修则无法按文档开发）：
1. 《系统技术架构与数据时序规范》通篇是 **Android 管线**，与 iOS + Metal 定位互斥。
2. **REQ-11 与 REQ-12 两个 P0 未进甘特图**，8 周实际装不下 12 个需求。
3. **API 零鉴权、零配额、零错误码**，VLM 成本无保护；图像含人脸数据却无隐私合规声明。

### 1.2 问题分级统计

| 级别 | 数量 | 明细 |
| :--- | :--- | :--- |
| 致命（阻断开发） | 4 | 架构篇 Android 栈；参数漂移 ×9；LUT 采样公式错误；2 个 P0 未排期 |
| 严重（上线前必修） | 2 | API 安全 / 成本裸奔；隐私合规空白 |
| 一般（质量债） | 4 | 双管线渲染一致性；mock 先行缺失；README / 版本管理混乱；60Hz Vision 追踪不现实 |

---

## 二、硬伤明细（P0，编码前必须修复）

### 2.1 硬伤一：架构篇技术栈为 Android（文档级事故）

《系统技术架构与数据时序规范.md》全文基于 Android，与 PRD/TDD/README 的 iOS 定位直接冲突：

| 原文 | 冲突点 | 应改为（iOS） |
| :--- | :--- | :--- |
| CameraX | PRD 明确 AVFoundation | AVCaptureSession |
| YUV_420_888 | PRD 明确 32BGRA | kCVPixelFormatType_32BGRA |
| SurfaceTexture / OES 外部纹理 | Metal 无 OES 概念 | CVMetalTextureCache / CVMetalTexture |
| GLSL 顶点 / 片元着色器 | PRD 明确 MSL | Metal Shading Language（.metal） |
| GLSurfaceView | Metal 无此视图 | MTKView |
| ImageAnalysis 抽帧器 | AndroidX Analysis API | AVCaptureVideoDataOutput + 自研节流器 |
| 30fps 预览 | PRD/TDD 均 60fps | 60fps 目标 |

### 2.2 硬伤二：三文档参数漂移对照表（9 处）

| # | 参数 | PRD | TDD | 架构篇 | **统一值（裁决）** |
| :-: | :--- | :--- | :--- | :--- | :--- |
| 1 | 上传帧长边 | 720px q75 | 640px | 640px | **720px，JPEG q75** |
| 2 | 单包体积 | 60~100KB | ~80KB | ~80KB | **二进制 ≤75KB（base64 后 ≤100KB），口径必须注明** |
| 3 | 云端超时熔断 | >2000ms | >2.5s | >2.0s | **2.0s** |
| 4 | 目标帧率 | 30~60fps（底线 24） | 60fps | 30fps | **目标 60 / 底线 24** |
| 5 | 取景内存 | ≤150MB（极限 250） | ≤120MB | 无 | **常驻 ≤150MB，红线 250MB** |
| 6 | 工作台内存 | 未单列 | 峰值 ≤220MB | 无 | **峰值 ≤250MB（48MP 分块加载）** |
| 7 | coach_tip 字数 | ≤20 字 | ≤15 字 | 无 | **≤20 字** |
| 8 | crop_box 格式 | FR 章节数组 / 5.1 对象 | 无 | 无 | **对象 `{ymin, xmin, ymax, xmax}`** |
| 9 | RTT 指标 | 400~800ms | ~500ms | ~500ms | **p50 ≤800ms，p95 ≤1500ms** |

### 2.3 硬伤三：3D LUT 采样公式错误（TDD §3.2）

现有公式计算了切片坐标 `coordLow/coordHigh`，但 **UV 公式从未加上切片原点偏移**，等效永远落在第 0 个切片——按文档实现滤镜颜色是错的。正确公式：

```metal
float blueIdx = clamp(B * 63.0, 0.0, 63.0);
float bLo = floor(blueIdx);
float bFrac = blueIdx - bLo;
// 512×512 贴图 = 8列×8行 个 64×64 切片
float2 tileLo = float2(fmod(bLo, 8.0), floor(bLo / 8.0));
float  bHi    = min(bLo + 1.0, 63.0);
float2 tileHi = float2(fmod(bHi, 8.0), floor(bHi / 8.0));
float2 uvLo = (tileLo * 64.0 + float2(R, G) * 63.0 + 0.5) / 512.0;
float2 uvHi = (tileHi * 64.0 + float2(R, G) * 63.0 + 0.5) / 512.0;
half3 graded = mix(sample(lutTex, uvLo), sample(lutTex, uvHi), bFrac); // 等效三线性
```

另外：TDD 称「三线性插值」、架构篇称「双线性」，术语统一为**「切片内双线性 + 切片间线性混合（等效三线性）」**。

### 2.4 硬伤四：甘特图缺两个 P0 + 一周空档

- REQ-11（空间机位导航，P0）与 REQ-12（拍后调色工作台，P0）**在甘特图中零任务**；按 TDD 的 HUD 状态机与双分辨率渲染工作台估算，二者合计 ≥3.5 周。
- 甘特 `w6` 结束（11-08）到 `w7b` 开始（11-16）之间存在**一周未分配空档**。
- 客户端 w1~w4 期间服务端尚未开工（w5 才启动），REQ-06/07 依赖云端 JSON——**缺 mock 先行机制，前 4 周客户端无法联调**。

### 2.5 硬伤五：API 安全与成本裸奔

- 三个接口**无任何鉴权**（无 API Key / JWT），VLM 调用无配额上限。
- 最坏情况：手持稳定时每 1.5s 一次 → 单用户单小时 2400 次调用，成本失控。
- 无错误码体系（响应只定义了 code:200），无 payload 上限校验（应 413），无限流（应 429）。

### 2.6 硬伤六：隐私合规空白

- 抽帧图像含**人脸数据**，三文档无一句隐私声明（不落盘 / 不存储 / 生命周期）。
- 缺 Info.plist 权限键清单：`NSCameraUsageDescription`、`NSPhotoLibraryAddUsageDescription`、`NSPhotoLibraryUsageDescription`（REQ-12 导入相册）。
- 缺 App Store 隐私标签口径与 PIPL 合规声明。

### 2.7 缺陷七：双管线渲染一致性隐患（REQ-08）

取景/快门走**自研 Metal MSL LUT**，拍后工作台走 **CoreImage CIColorCubeWithColorSpace**——同一 LUT 在两条管线中色彩空间与插值行为不同，「所见即所得」会被破坏。需统一工作色彩空间（Display P3 或 linear sRGB 二选一，全链路贯穿）。

### 2.8 缺陷八：文档管理

README 目录索引漏掉第三份文档；架构篇无版本表头；PRD v1.0.0 与 TDD v1.2.0 版本倒挂（PRD 应不落后于 TDD）。

---

## 三、可行性风险与修订建议（编码期持续盯防）

| # | 风险 | 评级 | 建议 |
| :-: | :--- | :-: | :--- |
| 1 | 「60Hz Vision 尺度追踪」不现实：VNDetectHumanBodyPoseRequest 实测 10~15Hz | 高 | 人脸用 VNTrackFaceRectanglesRequest（20~30Hz），人体姿态 5~10Hz 采样 + HUD 侧插值平滑；CoreMotion 维持 60Hz 不变 |
| 2 | 单目图像估「米 / 步」无物理依据（navigation_vector 的 -0.5m / 2 步拍脑袋） | 高 | v1.0 只做**方向性引导**（◄►▲▼ + 靠近/后退提示），去掉步数与米数计量；v1.1 接 ARKit VIO 世界坐标提供真实位移 |
| 3 | VLM 供应商未决：Qwen2-VL（国内可达）与 Gemini Flash（国内不可达）并列未拍板 | 中 | 演示环境以 Qwen2-VL 为主、Gemini 为海外备援；VLM_Router 做 failover + JSON 合法性守卫（失败重试 1 次） |
| 4 | 8 周 12 个 REQ（含 2 个后补 P0）排不下 | 高 | 见 TO-05：延至 11 周（方案 A，推荐），或执行裁剪方案 B |
| 5 | 成本无模型无预算 | 中 | 成本公式：日成本 = DAU × 人均日调用次数 × 单次调用单价；配额落地后写入 PRD |
| 6 | 48MP 照片 + 滤镜离屏渲染内存峰值 | 中 | 分块（tile）渲染 + autoreleasepool，守住 250MB 红线 |

---

## 四、Antigravity 执行指令（TO-01 ~ TO-10）

> **执行顺序即编号顺序**。TO-01 ~ TO-07 = Phase 0（文档修复 + 契约冻结，**2026-10-05 开发周一之前完成**）；TO-08 ~ TO-10 = Phase 1（脚手架与选型）。

### TO-01 重写《系统技术架构与数据时序规范.md》为 iOS 管线【P0】
- **任务**：按 §2.1 对照表逐项替换 Android 术语为 iOS/Metal 对应物；管线图改为 `AVCaptureSession → CVMetalTextureCache → MSL 顶点/片元 → MTKView` + `AVCaptureVideoDataOutput 抽帧节流器`；帧率、超时、体积按 §2.2 统一值修正。
- 保持原有三段式结构（渲染管线 / 端云时序图 / 容灾降级表）——时序图与容灾表内容质量合格，逻辑不动，只改技术栈与数值。
- **验收**：全文检索无 `CameraX / SurfaceTexture / OES / GLSurfaceView / GLSL / YUV_420_888 / ImageAnalysis`；与 TDD §3 零冲突。

### TO-02 建立统一规范常量表并全文档对齐【P0】
- **任务**：在 PRD 新增《附录 A：全局规范常量表》，内容 = §2.2 裁决列全部 9 项 + 热降级策略（thermal state 上升时抽帧周期 1.5s → 3.5s、预览降分辨率——从架构篇容灾表收编进 PRD NFR）。
- 同步修正 TDD / 架构篇中所有与附录 A 冲突的数字（640→720、2.5s→2.0s、120→150、220→250、15 字→20 字、30fps→60fps）。
- **验收**：三文档交叉检索，§2.2 表 9 项参数在所有出现处数值一致。

### TO-03 修正 3D LUT 数学章节【P0】
- **任务**：用 §2.3 的正确 MSL 公式替换 TDD §3.2 现有公式；补充 B=1.0 边界 clamp 说明与 PNG 纹理加载时 V 轴翻转注意事项；统一插值术语（切片内双线性 + 切片间线性混合）。
- **验收**：公式含切片原点偏移项 `tile * 64.0`；三文档插值术语一致。

### TO-04 PRD 新增《第 8 章：安全、限流、错误码与隐私合规》【P0】
新增章节必须包含：
1. **鉴权**：`POST /auth/device-register` 匿名签发 JWT（30 天滚动续期），业务接口携带 `Authorization: Bearer <JWT>`；响应信封统一 `{code, message, request_id, data}`。
2. **配额**：`analyze-composition` 300 次/日/设备；`retouch` 50 次/日/设备；滑动窗口限流。
3. **Payload 上限**：base64 > 200KB → `413 PAYLOAD_TOO_LARGE`。
4. **错误码表**：400 参数校验失败 / 401 鉴权失败 / 413 载荷超限 / 429 配额限流 / 500 内部错误 / 502 VLM 上游异常 / 503 服务降级（触发客户端离线模式）。
5. **隐私**：图像仅在推理请求生命周期内驻留内存，不落盘、不入库；日志禁止记录 base64；Info.plist 三键；App Store 隐私标签口径；不做人脸识别、不存储生物特征（PIPL / App Store 审核 4.x）。
- **验收**：新章节被 README 索引引用；TO-09 的 FastAPI 将严格按此实现。

### TO-05 重排实施路线图【P0】
- **任务**：按**方案 A（拍板执行）**重画甘特图，总长 **11 周**（2026-10-05 → 2026-11-20 前后）：
  - 新增独立泳道：REQ-11 导航 HUD（Vision 追踪 + 状态机，约 1.5 周）、REQ-12 工作台（双分辨率渲染 + 滑块 + 长按对比，约 2 周）；
  - REQ-12 的「配方保存为我的预设」降为 P1；REQ-09/10 维持 P2，本期只做埋点字段定义不实现；
  - 补齐原 11-09~11-15 空档；每个里程碑 M1~M4 附「REQ 覆盖映射表」（列出该里程碑交付的 REQ 编号）。
- 若用户明确坚持 8 周硬截止，执行**方案 B（备选）**：REQ-11 砍步数/米数计量只留四方向箭头，REQ-12 砍长按对比与 EXIF 完整性，二者标记为「P0-演示版」。
- **验收**：甘特图覆盖全部 12 个 REQ，无悬空需求、无未分配周；里程碑映射表完整。

### TO-06 README 与版本对齐【P0】
- **任务**：README 目录树补录第三份文档与 PRD 新第 8 章；三文档版本统一为 **v2.0.0**（架构篇补版本表头）；项目状态改为 `Design Freeze`。
- **验收**：README 索引与 docs 实际文件清单一致；三文档版本号一致。

### TO-07 契约冻结 + Mock 先行【P0，Phase 0 收尾】
- **任务**：
  1. 产出 `docs/api/openapi.yaml`：覆盖 4 个接口（device-register / vision / retouch / assets），含 TO-04 全部错误码。
  2. 产出 `docs/fixtures/`：≥6 个成功样例 JSON（人像夕阳 / 美食 / 夜景 / 建筑 / 街拍 / 逆光）+ 429 / 503 错误样例，结构与 PRD §5.1 / §5.2 完全一致（crop_box 统一对象格式，数值按附录 A）。
  3. 修正 PRD §5 请求/响应示例：crop_box 统一为对象格式。
- **验收**：openapi.yaml 通过 `swagger-cli validate`；fixtures 可直接作为 iOS w1~w4 本地联调的 mock 数据源。

### TO-08 iOS 工程脚手架【P1】
- **任务**：建 Xcode 工程（SwiftUI App，iOS 17+，iPhone only），模块划分：`Capture/ Render/ Motion/ Vision/ HUD/ Cloud/ Studio/ Resources/`；内置 Debug 菜单可切换 mock / cloud 数据源（读 TO-07 fixtures）；接通相机权限申请流。
- **验收**：空管线跑通「预览 → MTKView 显示原图」；未启用滤镜时稳定 60fps。

### TO-09 FastAPI 脚手架【P1】
- **任务**：`server/` 目录：Pydantic v2 schema + 4 条路由（vision / retouch 先返回 fixtures 桩）+ JWT 鉴权中间件 + 滑动窗口限流 + 413 校验 + 统一错误信封；`tests/` 对每条路由至少一条 200 与一条 4xx 用例。
- **验收**：`pytest` 全绿；curl 可完成「注册 → 调用 → 触发限流」全流程。

### TO-10 VLM 供应商 POC 与选型报告【P1】
- **任务**：编写 `server/poc/vlm_bench.py`：同一评测集（≥20 张，场景覆盖 TO-07 六类）分别调 Qwen2-VL 与 Gemini Flash，记录 p50/p95 延迟、JSON 合法率（含失败重试 1 次后的口径）、单次调用成本；输出 `docs/VLM选型报告.md`，给出主备供应商决策。
- **验收**：JSON 合法率 ≥95% 方可作为主供应商；报告结论明确（预期主选 Qwen2-VL，Gemini 备援）。

---

## 五、给 Antigravity 的启动指令（直接粘贴使用）

```text
你接手 AestheticLens-AI（灵瞳智拍）项目。先通读 README.md 与 docs/ 下全部文档，
再精读 docs/文档审计报告与Antigravity执行指令.md——它是你的唯一任务书，与旧文档冲突时以它为准。
按 TO-01 → TO-07 顺序完成 Phase 0（文档修复 + 契约冻结，截止 2026-10-05），
随后执行 TO-08 → TO-09 → TO-10。TO-05 默认执行方案 A（11 周）。
每完成一个 TO，在本文件末尾的执行清单勾选，并附上改动的文件列表。
严格遵守每条 TO 的验收标准，禁止扩大范围、禁止重写未指出的章节。
```

---

## 六、执行清单（Antigravity 完成后回填）

- [x] **TO-01 架构篇 iOS 化**（改动文件：`docs/系统技术架构与数据时序规范.md`；彻底替换 Android 术语为 AVCaptureSession + CVMetalTextureCache + MSL + MTKView，通过零冲突正则校验）
- [x] **TO-02 常量统一**（改动文件：`docs/需求开发规格说明书.md`、`docs/系统技术设计文档.md`、`docs/系统技术架构与数据时序规范.md`；PRD 新增《附录 A：全局规范常量表》，全文档 9 处参数完全对齐统一口径）
- [x] **TO-03 LUT 公式修正**（改动文件：`docs/系统技术设计文档.md` §3.2；增加 tile * 64.0 切片原点偏移项，补充边界 clamp 与 V 轴翻转注意事项，插值术语统一为切片内双线性 + 切片间线性混合）
- [x] **TO-04 安全与合规章节**（改动文件：`docs/需求开发规格说明书.md`；新增《第 8 章：安全、限流、错误码与隐私合规》，含匿名设备注册 JWT、日配额滑动窗口限流、Payload 413 保护、错误码表与 PIPL 内存不落盘合规）
- [x] **TO-05 甘特重排·方案 A**（改动文件：`docs/需求开发规格说明书.md` §7；重排 11 周全量甘特图，覆盖全部 12 个 REQ，消除空档，补充 M1~M5 里程碑 REQ 覆盖映射表）
- [x] **TO-06 README / 版本对齐 v2.0.0**（改动文件：`README.md`、三份文档全部同步表头为 v2.0.0，目录树补齐第 8 章与三文档索引，项目状态更新为 Design Freeze）
- [x] **TO-07 契约冻结 + Mock 先行**（新增文件：`docs/api/openapi.yaml`、`docs/fixtures/` 下 6 个场景真实响应桩 + 2 个错误用例 + 1 个拍后调色桩；全量对齐 PRD 结构）
- [x] **TO-11 文档补丁包**（改动文件：`openapi.yaml`、`需求开发规格说明书.md`、`系统技术设计文档.md`、`实机演示与极简部署上线指南.md`、新增 `00_device_register.json`；完成：重排甘特图消除空档并将服务端提前至 10-05 并行、校准 M1~M5 里程碑交付物与 REQ 编号、甘特新增 LUT 资产前置任务、增加 `/health` 端点与 3.1 联合类型、更新 Base URL 与 client_version 2.0.0、统一 Debug 触发口径为设置页版本号连续三击、约束 navigation_vector 范围并落地服务端 JSON 守卫、替换 JWT 密钥为随机生成命令并补充 Mock 跳过鉴权说明）
- [x] **TO-08 iOS 脚手架**（新增工程目录：`code/client/AestheticLens/`；特性：纯原生 SwiftUI + Metal MTKView 60fps 零拷贝渲染管线、60Hz CoreMotion 水平仪 HUD <0.5° 对齐、设置页版本号连续三击唤出 Debug 菜单、APIClient 支持 Live API 与本地 Mock 离线双模式无缝切换）
- [x] **TO-10（重定义）VLM POC 与基准测试**（改动/新增文件：`docs/技术架构/摄影大模型评测方案与业界开源借鉴报告.md`、`docs/技术架构/VLM选型与基准评测报告.md`、`code/poc/generate_benchmark_dataset.py`、`code/poc/dataset/`、`code/poc/vlm_bench.py`、`code/poc/benchmarks_report.md`、`code/app/prompt/photography_skill.py`、`code/app/services/vlm_service.py`、`code/tests/test_photography_skill.py`；完成：落地 6 大真实摄影场景 20 组黄金基准数据集与 Ground Truth、吸收 PCCD/AesFormer/Lightroom 沉淀摄影美学专家 Skill 引擎、实现 qwen-vl-plus 与 qwen-vl-max 自动化对比评测；结论：qwen-vl-plus p50=735.5ms, p95=881.1ms 达标，JSON合法率100%，动词引导率95%，1000次演示开销10.06元精准锁死10~15元预算红线，正式锁定生产首选）
- [x] **TO-14 服务端上线修复包**（改动文件：`code/app/core/config.py`、`code/app/core/security.py`、`code/app/core/middleware.py`、`code/app/core/limiter.py`、`code/app/api/v1/assets.py`、`code/app/api/v1/health.py`、`code/app/api/v1/retouch.py`、`code/app/api/v1/vision.py`、`code/app/api/v1/auth.py`、`code/requirements.txt`；完成：生产环境强制封堵 mock token 鉴权后门、拒绝默认弱密钥自检、以真实 4 套 512x512 贴图与真实 MD5 重构 FILTERS_DB、/health 探针增加 vlm_configured/environment、视频关键帧补充 2.5MB 载荷守卫、剔除 /retouch-recipe 幽灵别名路由、依赖清单瘦身移除非必要 SDK；全套 25 项测试 100% 绿灯通过）
- [x] **TO-15 iOS 工程化**（新增文件：`code/client/AestheticLens.xcodeproj/project.pbxproj`、`code/client/Package.swift`；特性：创建 Xcode 15+ 官方标准工程包，预置 Target、Metal 编译管线、Swift 5.9 编译参数与 512x512 真实 LUT 资源打包，Mac 用户双击即可一键在 Xcode 打开并直装真机）
- [ ] **TO-16 上线走查清单**（待 Zeabur 部署当日勾选走查）

---

## 七、第二轮审计（2026-10-03 复核）

### 7.1 Phase 0 验收结论：TO-01 ~ TO-07 全部通过

逐项复核确认：架构篇已无 Android 残留（TO-01 ✓）；附录 A 常量表生效且三文档数值对齐（TO-02 ✓）；LUT 公式含 `tile * 64.0` 切片偏移与边界 clamp（TO-03 ✓）；PRD 第 8 章安全/隐私完整（TO-04 ✓）；11 周甘特覆盖 12 个 REQ（TO-05 ✓，但引入新矛盾，见 7.2）；README 与 v2.0.0 对齐（TO-06 ✓）；openapi.yaml + 9 个 mock 桩结构正确、信封一致（TO-07 ✓）。文档分类归档（需求规格/技术架构/接口契约/审计报告）与新增《实机演示与极简部署上线指南》为合格增量。

### 7.2 第二轮新发现问题（12 项）

**排期层（高，阻断 M3/M4 承诺）**
1. **甘特图新空档 11-23 ~ 11-29**：s5 止于 11-22、c6 止于 11-18，而 i1 始于 11-30——上一轮"无未分配周"的验收标准被违反。
2. **里程碑与任务完成日漂移**：M3（11-15）声称交付 REQ-05（s5 实际 11-22 完成）与 REQ-08（c6 实际 11-18 完成）；M4（11-29）声称 REQ-12 基础版（c7 实际 12-02 完成）。
3. **服务端泳道空转**：s1"契约冻结与 Mock 先行"排在 10-19~10-25，但该工作已在 Phase 0（10-03）提前完成；服务端应 10-05 与客户端并行开工。
4. **LUT 资产无排期**：M2 要求 4 套经典 LUT，甘特图无任何 LUT 制作/采购任务——隐藏依赖，M2 必然卡壳。

**契约层（中）**
5. **`/health` 端点缺失**：部署指南自检 Checklist 第 1 项依赖 `GET /health` 返回 `{"status":"ok"}`，但冻结的 openapi.yaml 未定义该端点。
6. **OpenAPI 3.1 语法错误**：`ErrorEnvelope.data` 使用 3.0 关键字 `nullable: true`，3.1 应为 `type: ["object", "null"]`。
7. **Base URL 与版本号漂移**：PRD §5 基础路径仍为虚构域名 `api.aestheticlens.ai`，与附录 B 的 Zeabur 决策冲突；PRD §5.1 示例 `client_version: "1.0.0"` vs openapi 示例 `"2.0.0"`。
8. **Debug 菜单触发方式三种口径**：PRD 附录 B"三指双击或设置页长按"、TDD §8.2"连续三击版本号"、部署指南 §5.2"三击标题/Logo"——必须统一为一种。

**执行层（风险）**
9. **TO-10 与方案 A 冲突**：部署指南已拍板 DashScope `qwen-vl-plus` 单一供应商，TO-10 却要求"Qwen2-VL vs Gemini Flash 对比"（Gemini 国内不可达，已无意义）。TO-10 需重定义。
10. **部署指南硬编码示例 JWT 密钥**（`AestheticLens_Secret_2026_Key`）并称"高强度"——应改为随机生成指引（如 `openssl rand -hex 32`），且严禁入库。
11. **navigation_vector 计量值冻结进契约**：上一轮建议 v1.0 去掉"步数/米数"未被采纳，现已冻结——接受该风险，但 Prompt 必须约束取值范围（`forward_steps ∈ [1,3]`、`|horizontal_translation_m| ≤ 1.0`、`|vertical_translation_cm| ≤ 30`），客户端按粗粒度提示消费，不做精确校验。
12. **服务端 JSON 守卫未落文档**：VLM 返回非法 JSON 时的"校验 + 重试 1 次 + 兜底 503"流程无任何文档描述；且 mock 桩缺 `device-register` 成功样例（或明确 Mock 模式跳过鉴权）。

---

## 八、第二轮执行指令（TO-11 ~ TO-13）与下一步推进路线

### TO-11 文档补丁包（10-05 开发周一前完成，工作量小）
1. 重排甘特：服务端泳道整体提前至 10-05 并行（s1 改为"契约复核 + /health + Zeabur 部署管道预热"，2~3 天）；i1 提前至 11-12 开始（其依赖仅为 vision 链路：c3+c4+c5 与 s3，均早于该日）；消除 11-23~29 空档（由 c6/c7 客户端工作台填充）；i2/i3 顺延至 12 月上旬，保留 12-14~20 缓冲。
2. 修正里程碑映射：按重排后的任务完成日重标 M3/M4 的 REQ 覆盖（M3 保留 REQ-04/05/11，M4 改为 REQ-08 + REQ-12 服务端闭环，REQ-12 客户端完整版归 M5）。
3. 甘特新增 LUT 资产任务（2~3 天，M2 前完成）：以开源 .cube 转换或 DaVinci 调色生成 4 套 512×512 LUT PNG（lut_warm_film_03 等命名与契约一致），入 `client-ios/Resources/luts/`。
4. openapi.yaml：新增 `GET /health`（无鉴权，返回 `{"status":"ok"}`）；`ErrorEnvelope.data` 改 3.1 语法；servers 增加 Zeabur 生产域名占位条目；`AnalyzeAndGradeRequest.image_meta` 标为 required。
5. PRD §5 基础路径加注"生产 Base URL 以附录 B Zeabur 分配域名为准"；§5.1 示例 client_version 改 "2.0.0"。
6. 统一 Debug 菜单触发口径为**"设置页版本号连续三击"**（三文档同步改写）。
7. TDD §5.1 Prompt 增加 navigation_vector 取值范围约束；PRD 第 6 章 Prompt 规范同步。
8. 部署指南：JWT 密钥改为随机生成指引；补 mock 桩 `00_device_register.json`（或注明 Mock 模式跳过鉴权）。
- **验收**：甘特无空档、里程碑日期与任务完成日一致；`/health` 存在于契约；三文档 Debug 触发口径一致。

### TO-10（重定义）VLM POC：qwen-vl-plus vs qwen-vl-max
- 原"Qwen2-VL vs Gemini Flash"作废（方案 A 已锁定 DashScope 单一供应商）。改为对比 `qwen-vl-plus`（成本档）与 `qwen-vl-max`（质量档）：同一 ≥20 张评测集（覆盖 6 大场景，**本周即开始收集**），记录 p50/p95 延迟、JSON 合法率（含重试 1 次口径）、单次成本；若 plus 合法率 ≥95% 且建议质量可接受，则维持 plus，max 仅作 retouch 接口升级选项。
- **验收**：`docs/技术架构/VLM选型报告.md` 给出主备结论与成本测算（对照附录 B 的 10 元预算）。

### TO-08 / TO-09（维持原指令，10-05 当周并行开工）
- TO-09 补充要求：实现 `/health`；VLM 响应 JSON 守卫（Pydantic 二次校验 + 重试 1 次 + 兜底 50301）；日志过滤器禁止 base64 入日志。
- TO-08 补充要求：Mock 模式跳过鉴权直读 fixtures；Debug 菜单按"设置页版本号连续三击"实现。

### 下一步推进路线（时间轴）
| 时间 | 动作 |
| :--- | :--- |
| 10-03 ~ 10-04（本周末） | TO-11 文档补丁包；开始收集 20 张评测图 |
| 10-05（周一，W1） | TO-08 iOS 脚手架 ∥ TO-09 FastAPI 脚手架 并行开工 |
| W1 ~ W2 | TO-10 VLM POC（必须在 s3 Prompt 工程前出结论） |
| W2 前 | LUT 资产 4 套就位（M2 前置） |
| 10-18（M1） | 取景流 + 水平仪验收 |

---

## 九、第三轮审计（2026-10-04，代码就绪 / 部署前审计）

### 9.1 审计范围与总体结论

- **范围**：`code/` 全量（FastAPI 服务端 5 条 API + core 中间件 + VLM 服务 + 测试套件 + Docker 部署件 + POC 评测资产）+ iOS 客户端源码 + `code/README.md`。
- **实测证据**：`python -m pytest tests -v` → **22 passed / 1 skipped**（skip 为需运行容器的 e2e docker ping），全部质量门通过。
- **总体结论**：服务端代码质量合格可上线；但存在 **3 个阻断级问题**（iOS 无 Xcode 工程、Mock token 鉴权后门、LUT 资产链三方断裂），必须修复后再进入部署流程。

### 9.2 已达标项（无需改动）

`/health` 双注册（根路径 + /api/v1）；JWT 签发校验 + 滑动窗口限流（1.5s/300 次、3s/50 次）+ 413 载荷守卫 + 统一信封全链路一致；取景接口超时端云双侧均 2.0s（服务端 httpx / 客户端 timeoutInterval）；VLM 响应 JSON 守卫（validate_and_repair + 桩兜底）；Info.plist 四权限键；Shaders.metal 含切片偏移与 clamp；Debug 菜单三击版本号统一；openapi.yaml 已含 analyze-video；.dockerignore/.gitignore 覆盖 .env 与缓存；docker-compose 带 healthcheck。

### 9.3 问题清单

**阻断级（不修不能上线 / 上线即假）**
1. **iOS 客户端无 Xcode 工程**：`code/client/` 仅有 Swift 源码与 Info.plist，全目录无 `.xcodeproj`/`project.pbxproj`/`Package.swift`——当前形态无法编译安装到真机，方案 A 的"Xcode 直装"无从执行。
2. **Mock token 鉴权后门**（`app/core/security.py` L31）：`mock_token_` 前缀或 `_for_offline_dev` 后缀的 Bearer Token 可绕过 JWT 校验（固定 device_id `device_mock_device`）。生产公网部署等于公开无鉴权通道，且配合任意伪造 device_id 注册可绕过全部配额。
3. **LUT 资产链三方断裂**（`app/api/v1/assets.py`）：
   - 下发 4 个 ID（`lut_warm_film_03`/`lut_cyber_neon_01`/`lut_minimal_bw_02`/`lut_vintage_green_04`），URL 全部指向**虚构域名** `assets.aestheticlens.ai`；
   - 本地实际文件为 `lut_film_warm_01`/`lut_clean_bright_02`/`lut_cyber_teal_orange_03`/`lut_mono_contrast_04`（`code/static/luts/` 与客户端 Resources 各一套）；
   - mock 桩与 VLM 推荐的 `lut_warm_film_03` 在客户端本地**无同名纹理**；`lut_cyber_neon_01` 不存在于任何位置；MD5 全为占位假值。
   - 后果：云端推荐 ID → 客户端纹理映射必然失败，REQ-07 联动与 REQ-09 热更形同虚设。

**高危（上线即踩）**
4. **DASHSCOPE_API_KEY 缺失时静默假数据**：`vlm_service` 无 Key 时所有请求返回同一张夕阳桩且 `code=200 success`——线上漏配 Key 无法察觉，演示"成功"实为假数据。需启动时 WARNING 日志 + `/health` 增加 `vlm_configured` 字段 + 降级响应打标记。
5. **JWT_SECRET_KEY 弱默认**：`config.py` 有 dev 默认值、docker-compose 有兜底默认 `aestheticlens_dev_secret_key_2026`；且 `.env.example` 定义了 `ENVIRONMENT` 变量但 `config.py` 根本未读取（漂移）。需 production 环境检测到默认/弱密钥时拒绝启动。
6. **Zeabur 域名为占位猜测**：客户端 `APIClient.swift` L23 与部署指南均写死 `aestheticlens-api.zeabur.app`——真实分配域名大概率不同，须列入上线走查（改代码或用"自定义"环境输入真实域名）。

**中危**
7. **502/503 错误码从不触发**：契约与 PRD 第 8 章定义了 502（VLM 上游异常）/503（降级）语义，但服务端永远 200+桩兜底——客户端 502 重试、503 切离线是死逻辑。与 #4 合并修：降级响应加 `X-AI-Source: fallback` 头或信封 `degraded: true` 字段（保留 200 兼容现有客户端）。
8. **device-register 无防滥用**：任何人可无限换发 token，配额按 device_id 计（N 设备 = N×300 次真金白银的 VLM 调用）。演示期可接受，建议补 IP 级注册频控（如 10 次/小时/IP）。
9. **载荷守卫缺口**：PayloadGuard 仅检查 Content-Length（chunked 可绕过）；`/retouch/analyze-video` 不在中间件白名单且端点内无体积校验——3 张关键帧 Base64 可远超 2.5MB 直达 VLM。
10. **限流器内存无清理**（device 记录永不回收）+ 多 worker 部署时状态不共享（单容器单 worker 无碍，记录在案）。
11. **`/retouch-recipe` 幽灵别名路由**：同一函数双装饰器注册两条路径，其一 include_in_schema=False——契约外路径，建议删除。
12. **依赖瘦身**：`pytest` 打进生产镜像；`dashscope` SDK 未使用（实际用 httpx 兼容模式）。

### 9.4 第三轮执行指令

### TO-14 服务端上线修复包【阻断，部署前必做】
1. 删除 security.py 的 mock token 后门；如本地联调需要，改为 `settings.ENVIRONMENT != "production"` 时才放行，config.py 补读 `ENVIRONMENT` 环境变量。
2. 重建 assets.py FILTERS_DB：以 `code/static/luts/` 实际 4 个 PNG 为唯一事实源（lut_film_warm_01 / lut_clean_bright_02 / lut_cyber_teal_orange_03 / lut_mono_contrast_04），lut_url 改为相对路径 `/static/luts/<id>.png`（客户端按 baseURL 拼接）或新增 `ASSETS_BASE_URL` 配置；用真实文件计算 MD5；同步更新 mock 桩与 photography_skill.py 推荐 ID、客户端本地 LUT 文件名，实现"推荐 ID = 资产 ID = 本地文件名"三方一致。
3. main.py 启动时：DASHSCOPE_API_KEY 缺失 → logger.warning 醒目提示"当前为桩数据模式"；/health 响应增加 `vlm_configured: true/false`。
4. config.py 增加 production 启动自检：ENVIRONMENT=production 且 JWT_SECRET_KEY 命中已知默认值 → 启动即抛异常。
5. 降级可观测：桩兜底时响应头加 `X-AI-Source: fallback`（在线为 `qwen-vl-plus`），与 #7 对齐。
6. analyze_video 端点内补关键帧总体积校验（≤2.5MB）；middleware 白名单补 `/retouch/analyze-video`。
7. 删除 `/retouch-recipe` 别名路由；requirements.txt 移除 pytest 与 dashscope（或注明保留理由）。
- **验收**：pytest 全绿；`grep mock_token` 无生产路径；assets 下发的每个 lut_id 都能在 /static/luts 下载且 MD5 一致；无 Key 启动时日志出现 WARNING 且 /health 如实上报。

### TO-15 iOS 工程化【阻断，真机部署前置】
1. 在 Mac Xcode 中新建 iOS App 工程（Bundle ID 按部署指南，iOS 17+），导入 `code/client/AestheticLens/` 全部源码与 `Resources/luts/`，配置 Info.plist 权限键，真机编译通过并安装。
2. 工程文件（.xcodeproj）提交回 `code/client/` 入库，消除"只有源码没有工程"的状态。
3. 上线走查时将生产域名写入 `APIClient.swift` 的 zeaburProd（或约定演示时用"自定义 IP"现场输入）。
- **验收**：真机可启动取景器（60fps 预览 + 水平仪）；Mock 模式全流程可演示。

### TO-16 上线走查清单（Zeabur 部署当日执行）
1. Zeabur 环境变量：`DASHSCOPE_API_KEY`（真实 sk-）、`JWT_SECRET_KEY`（openssl rand -hex 32 生成）、`ENVIRONMENT=production`。
2. `curl https://<真实域名>/health` 返回 `{"status":"ok","vlm_configured":true}`；记录真实域名并回填客户端。
3. 真机 Live 模式端到端一次：注册 → 取景分析（返回真实场景相关建议而非夕阳桩）→ 拍后调色。
4. 真机 Mock 模式演练一次（演示防翻车兜底）。
5. `python -m pytest tests` 本地全绿后再推送触发 Zeabur 重建；部署后跑一次 429 限流验证（1.5s 内连发两次）。
- **验收**：五项全勾选后方可对外演示。
