FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

VOLUME ["/data"]

ENV DATABASE_URL=postgresql://sallimnote:makemoney!@sallimnote-postgres:5432/sallimnote
ENV JWT_SECRET=change-me-in-production
ENV CORS_ORIGINS=*

EXPOSE 8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
