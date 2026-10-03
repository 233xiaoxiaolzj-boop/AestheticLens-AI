# ==============================================================================
# AestheticLens-AI 本地 Docker 一键构建与启动脚本
# ==============================================================================

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   AestheticLens-AI 云端服务 Docker 本地一键构建与部署工具   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. 检测 Docker CLI 是否存在
$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCmd) {
    Write-Host "[错误] 系统未检测到 docker 命令，请确认 Docker Desktop 是否正确安装。" -ForegroundColor Red
    exit 1
}

# 2. 检测 Docker Daemon 是否正在运行
Write-Host "[1/4] 正在检测 Docker 引擎运行状态..." -ForegroundColor Yellow
$dockerPing = docker version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[提示] Docker Desktop 尚未启动！" -ForegroundColor Red
    Write-Host "请按以下步骤操作：" -ForegroundColor Yellow
    Write-Host "  1. 打开电脑桌面上的 'Docker Desktop' 图标启动软件；" -ForegroundColor White
    Write-Host "  2. 观察电脑右下角任务栏小鲸鱼图标，变为绿色常亮状态；" -ForegroundColor White
    Write-Host "  3. 重新运行本脚本即可！" -ForegroundColor White
    exit 1
}
Write-Host "[OK] Docker 引擎运行正常！" -ForegroundColor Green

# 3. 构建本地镜像
Write-Host "[2/4] 正在根据 code/Dockerfile 构建镜像 (aestheticlens-cloud:v2.0.0)..." -ForegroundColor Yellow
docker build -t aestheticlens-cloud:v2.0.0 -f Dockerfile .
if ($LASTEXITCODE -ne 0) {
    Write-Host "[错误] 镜像构建失败，请检查网络或依赖清单！" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] 镜像构建成功！" -ForegroundColor Green

# 4. 启动容器
Write-Host "[3/4] 正在启动容器并在后台运行 (映射本地端口 8000)..." -ForegroundColor Yellow
docker rm -f aestheticlens-backend 2>$null
docker run -d --name aestheticlens-backend -p 8000:8000 aestheticlens-cloud:v2.0.0
if ($LASTEXITCODE -ne 0) {
    Write-Host "[错误] 容器启动失败！" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] 容器已在后台成功启动！" -ForegroundColor Green

# 5. 健康检查验证
Write-Host "[4/4] 正在进行端点连通性测试 (http://127.0.0.1:8000/health)..." -ForegroundColor Yellow
Start-Sleep -Seconds 3
try {
    $resp = Invoke-RestMethod -Uri "http://127.0.0.1:8000/health" -Method Get -TimeoutSec 5
    if ($resp.status -eq "ok") {
        Write-Host "==========================================================" -ForegroundColor Green
        Write-Host " [成功] AestheticLens-AI 云端服务已在 Docker 容器中平稳运行！" -ForegroundColor Green
        Write-Host " * 健康探测接口: http://127.0.0.1:8000/health" -ForegroundColor Cyan
        Write-Host " * Swagger 文档: http://127.0.0.1:8000/docs" -ForegroundColor Cyan
        Write-Host "==========================================================" -ForegroundColor Green
    }
} catch {
    Write-Host "[警告] 服务启动中，请在几秒后手动访问 http://127.0.0.1:8000/docs 进行验证。" -ForegroundColor Yellow
}
