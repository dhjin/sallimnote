FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
RUN chmod +x start.sh

VOLUME ["/data"]

ENV DATABASE_URL=postgresql://sallimnote:makemoney!@sallimnote-postgres:5432/sallimnote
ENV JWT_SECRET=change-me-in-production
ENV CORS_ORIGINS=*

EXPOSE 8080
# 시작 시 alembic upgrade head 후 uvicorn 기동 (스키마 자동 최신화)
CMD ["./start.sh"]
