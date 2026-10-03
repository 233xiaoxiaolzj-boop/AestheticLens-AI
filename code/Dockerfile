FROM python:3.11-slim

WORKDIR /app

# 设置时区与环境变量
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TZ=Asia/Shanghai

# 安装依赖
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt --extra-index-url https://pypi.tuna.tsinghua.edu.cn/simple

# 复制代码
COPY . .

# 暴露端口并启动
EXPOSE 8000
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
