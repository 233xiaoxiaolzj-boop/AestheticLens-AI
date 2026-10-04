import logging
import uuid
from fastapi import FastAPI, Request, HTTPException
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.openapi.docs import get_swagger_ui_html

from app.core.config import settings
from app.core.middleware import PayloadGuardMiddleware
from app.api.v1 import health, auth, vision, retouch, assets

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("AestheticLensApp")

PROJECT_DESCRIPTION_ZH = """
### 🚀 灵瞳智拍 (AestheticLens-AI) 端云协同微服务工作台

基于端云协同架构与 Metal 实时渲染技术打造的智能摄影构图与拍后调色相机后端中台。

---

#### 核心特性与技术指标
* **端云双向协同**：手机端负责 60Hz 姿态解算与 60fps 实时 3D LUT 渲染，云端负责 Qwen-VL-Plus 深度美学与机位规划；
* **极简上线方案 A**：Zeabur 轻量 PaaS + 阿里云 Qwen-VL + 免费 Apple ID 直装 + AltStore 局域网续期；
* **演示防翻车双保险**：在线支持 Qwen-VL-Plus 实时诊断，弱网超时（>2.0s）自动无缝降级至本地离线黄金数据桩；
* **严格安全限流**：匿名设备注册 JWT 鉴权，取景分析滑动窗口限流 1.5 秒/次（300 次/天），超额即时触发 429 与 Retry-After；
* **超重载荷拦截 (PayloadGuard)**：抽帧 Base64 上限 200KB，调色 Base64 上限 2.5MB，超限立即返回 413，保护云端内存安全。
"""

TAGS_METADATA = [
    {
        "name": "👁️ 实时取景构图与机位空间导航 (Live Vision)",
        "description": "接收 720px 预览帧与 CoreMotion 陀螺仪姿态，结合美学专家 Skill 提供 4 向空间导航建议与 AR 构图框。"
    },
    {
        "name": "🎨 拍后智能美学诊断与色彩配方 (Post Retouch)",
        "description": "针对拍摄成片进行美学诊断，输出曝光、对比、高光、阴影、色温等 10 项专业无损可逆调色滑块配方。"
    },
    {
        "name": "🔐 设备认证与鉴权 (Device Auth)",
        "description": "匿名设备首次激活与访问令牌管理，换发 30 天有效期的 JWT Bearer Token 与每日调用配额。"
    },
    {
        "name": "📦 胶片滤镜与 3D LUT 资产 (Filter Assets)",
        "description": "下发 4 套经典胶片滤镜（落日余晖、纯净通透物产、赛博青橙夜景、德味高反差黑白）的云端纹理与元数据。"
    },
    {
        "name": "🩺 系统健康监测 (Health)",
        "description": "免鉴权健康探测探针，供 Zeabur 容器探针与手机 App 进行连通性实时检测。"
    }
]

app = FastAPI(
    title="AestheticLens-AI (灵瞳智拍) —— 云端视觉微服务工作台",
    description=PROJECT_DESCRIPTION_ZH,
    version="2.0.0",
    openapi_tags=TAGS_METADATA,
    docs_url=None, # 关闭默认 docs，使用自定义汉化版 /docs
    redoc_url="/redoc",
    openapi_url="/openapi.json"
)

# 启动自检与状态日志
@app.on_event("startup")
async def startup_event():
    # 1. 生产环境硬安全自检 (拒绝默认弱密钥)
    settings.validate_production_secrets()
    # 2. VLM 凭据检查与醒目提示
    if not settings.DASHSCOPE_API_KEY:
        logger.warning(
            "\n========================================================================\n"
            "⚠️ [WARNING] 未检测到 DASHSCOPE_API_KEY 环境变量！\n"
            "   当前视觉大模型中台将自动运行于离线 Golden Mock 黄金数据桩兜底模式。\n"
            "   如需在线真实调用 Qwen-VL-Plus，请在环境变量注入 DASHSCOPE_API_KEY！\n"
            "========================================================================"
        )
    else:
        logger.info("[AestheticLens-AI] ✅ 成功加载 DASHSCOPE_API_KEY，在线大模型中台已就绪。")

# 1. 跨域允许 (CORS)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 2. 载荷大小守卫中间件
app.add_middleware(PayloadGuardMiddleware)

# 3. 自定义全中文 Swagger UI 路由
@app.get("/docs", include_in_schema=False)
async def custom_swagger_ui_html():
    html_content = get_swagger_ui_html(
        openapi_url="/openapi.json",
        title="AestheticLens-AI 接口测试工作台 (中文版)",
        swagger_js_url="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-bundle.js",
        swagger_css_url="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui.css"
    )
    
    # 注入轻量级 Swagger UI 全界面原生汉化与样式优化脚本
    localization_script = """
    <script>
    window.addEventListener('DOMContentLoaded', function() {
        const i18nMap = {
            'Authorize': '🔐 鉴权登录',
            'Close': '关闭',
            'Try it out': '🚀 点击调试',
            'Cancel': '取消',
            'Execute': '▶ 立即执行发送',
            'Clear': '清空重置',
            'Parameters': '📥 请求参数 (Parameters)',
            'Request body': '📦 请求载荷 (Request Body)',
            'Responses': '📤 响应结果 (Responses)',
            'No parameters': '无额外路径参数',
            'Download': '💾 下载结果',
            'Media type': '媒体类型',
            'Controls': '操作控制',
            'Description': '说明',
            'Code': '状态码',
            'Example Value': '参数示例',
            'Schema': '数据模型 (Schema)'
        };

        function translateNode(node) {
            if (node.nodeType === Node.TEXT_NODE) {
                const text = node.textContent.trim();
                if (i18nMap[text]) {
                    node.textContent = i18nMap[text];
                }
            } else if (node.nodeType === Node.ELEMENT_NODE) {
                if (node.tagName === 'BUTTON' && i18nMap[node.innerText.trim()]) {
                    node.innerText = i18nMap[node.innerText.trim()];
                }
                for (let child of node.childNodes) {
                    translateNode(child);
                }
            }
        }

        const observer = new MutationObserver(function(mutations) {
            mutations.forEach(function(mutation) {
                mutation.addedNodes.forEach(function(node) {
                    translateNode(node);
                });
            });
        });

        observer.observe(document.body, { childList: true, subtree: true });
        translateNode(document.body);
    });
    </script>
    <style>
        .swagger-ui .topbar { display: none !important; }
        .swagger-ui .info h2 { color: #10a37f; font-weight: bold; }
        .swagger-ui .btn.execute { background-color: #10a37f !important; border-color: #10a37f !important; color: white !important; font-weight: bold; }
        .swagger-ui .btn.try-out__btn { background-color: #0284c7 !important; color: white !important; }
    </style>
    """
    body = html_content.body.decode("utf-8").replace("</body>", f"{localization_script}</body>")
    return HTMLResponse(content=body)

# 4. 统一全局异常处理器
@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    if isinstance(exc.detail, dict):
        code = exc.detail.get("code", exc.status_code)
        message = exc.detail.get("message", "Request error")
        data = exc.detail.get("data", None)
    else:
        code = exc.status_code
        message = str(exc.detail)
        data = None
        
    req_id = f"req_err_{uuid.uuid4().hex[:8]}"
    headers = getattr(exc, "headers", None) or {}
    
    return JSONResponse(
        status_code=exc.status_code,
        headers=headers,
        content={
            "code": code,
            "message": message,
            "request_id": req_id,
            "data": data
        }
    )

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    req_id = f"req_val_{uuid.uuid4().hex[:8]}"
    return JSONResponse(
        status_code=400,
        content={
            "code": 40001,
            "message": f"请求参数校验失败: {exc.errors()[0]['msg'] if exc.errors() else 'Invalid payload'}",
            "request_id": req_id,
            "data": None
        }
    )

@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    req_id = f"req_fatal_{uuid.uuid4().hex[:8]}"
    logger.error(f"Internal server error: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={
            "code": 50001,
            "message": "云端微服务内部未捕获异常",
            "request_id": req_id,
            "data": None
        }
    )

# 5. 集中注册路由
app.include_router(health.router)
app.include_router(health.router, prefix=settings.API_V1_STR)
app.include_router(auth.router, prefix=settings.API_V1_STR)
app.include_router(vision.router, prefix=settings.API_V1_STR)
app.include_router(retouch.router, prefix=settings.API_V1_STR)
app.include_router(assets.router, prefix=settings.API_V1_STR)

# 6. 挂载静态资源服务 (3D LUT 贴图等)
import os
from fastapi.staticfiles import StaticFiles
static_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "static")
if os.path.exists(static_path):
    app.mount("/static", StaticFiles(directory=static_path), name="static")

# 7. 电脑端 1:1 免安装交互式真机仿真中台页面 (无需安装手机，电脑直接查看效果)
@app.get("/", response_class=HTMLResponse, include_in_schema=False)
async def desktop_simulator_html():
    simulator_file = os.path.join(static_path, "simulator.html")
    if os.path.exists(simulator_file):
        with open(simulator_file, "r", encoding="utf-8") as f:
            return HTMLResponse(content=f.read())
    return HTMLResponse("<h3>AestheticLens Simulator is Loading</h3>")

