"""JWT 인증 + 테넌트 스코프 — 산후조리원 멀티테넌트."""

import os
import bcrypt
from datetime import datetime, timedelta
from jose import jwt, JWTError
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer

SECRET_KEY = os.environ.get("JWT_SECRET", "change-me-in-production-please")
ALGORITHM  = "HS256"
TOKEN_EXPIRE_DAYS = 30

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


def hash_password(plain: str) -> str:
    return bcrypt.hashpw(plain.encode(), bcrypt.gensalt()).decode()


def verify_password(plain: str, hashed: str) -> bool:
    return bcrypt.checkpw(plain.encode(), hashed.encode())


def create_token(member_id: str, username: str, role: str, tenant_id: str) -> str:
    expire = datetime.utcnow() + timedelta(days=TOKEN_EXPIRE_DAYS)
    data = {
        "sub":      member_id,
        "username": username,
        "role":     role,
        "tid":      tenant_id,   # 테넌트 스코프
        "exp":      expire,
    }
    return jwt.encode(data, SECRET_KEY, algorithm=ALGORITHM)


def decode_token(token: str) -> dict:
    try:
        return jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )


def get_current_member(token: str = Depends(oauth2_scheme)) -> dict:
    """FastAPI 의존성 — 디코드된 토큰 payload 반환."""
    return decode_token(token)


def get_tenant_scope(payload: dict = Depends(get_current_member)) -> str:
    """현재 토큰의 tenant_id. 모든 도메인 쿼리는 이 값으로 강제 필터링한다."""
    tid = payload.get("tid")
    if not tid:
        raise HTTPException(status_code=403, detail="No tenant scope in token")
    return tid


def require_admin(payload: dict = Depends(get_current_member)) -> dict:
    """owner/admin 만 허용."""
    if payload.get("role") not in ("owner", "admin"):
        raise HTTPException(status_code=403, detail="Admin only")
    return payload
