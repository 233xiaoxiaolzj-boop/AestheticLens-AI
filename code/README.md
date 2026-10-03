# AestheticLens-AI 代码仓库 (code)

本目录为整个项目的**代码统一保存目录**，结构清晰分为：

- `app/`：云端后端服务核心代码（FastAPI 微服务应用）
  - `api/v1/`：提供给手机 App 调用的 API 接口（`/health`, `/auth`, `/vision`, `/retouch`, `/assets`）
  - `core/`：安全与限流防护（JWT 鉴权、1.5秒滑动窗口限流、200KB 载荷上限拦截）
  - `schemas/`：数据格式定义（输入参数与输出返回结构）
- `tests/`：自动化测试套件（运行 `python -m pytest tests -v` 即可执行全部 11 项质量测试）
- `Dockerfile`：云端容器打包文件，用于一键部署到 Zeabur
- `requirements.txt`：Python 依赖包清单
- `.env.example`：环境变量配置文件模板
