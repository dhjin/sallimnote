#!/bin/sh
# 컨테이너 시작 시 DB 스키마를 항상 최신으로 맞춘 뒤 서버를 띄운다.
# (PostgreSQL 은 create_all 을 쓰지 않으므로 마이그레이션이 선행되어야 함)
set -e

echo "[start] alembic upgrade head ..."
alembic upgrade head

echo "[start] launching uvicorn ..."
exec uvicorn main:app --host 0.0.0.0 --port 8080
