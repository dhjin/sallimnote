"""SQLAlchemy ORM models — 산후조리원 멀티테넌트 백엔드.

모든 도메인 테이블은 tenant_id 로 격리된다. (공유 DB + 행 단위 격리)
"""

import uuid
from datetime import datetime
from sqlalchemy import (
    Boolean, Column, DateTime, Float, Integer, String, ForeignKey, Text, Date,
    Index,
)
from sqlalchemy.orm import declarative_base

Base = declarative_base()


def _uuid() -> str:
    return str(uuid.uuid4())


def _now() -> datetime:
    return datetime.utcnow()


class Tenant(Base):
    """산후조리원 = 테넌트. 결제/구독 단위."""
    __tablename__ = "tenants"

    id              = Column(String, primary_key=True, default=_uuid)
    name            = Column(String, nullable=False)
    plan            = Column(String, default="free")      # "free" | "premium"
    plan_expires_at = Column(DateTime, nullable=True)
    temp_threshold  = Column(Float, default=37.5)         # 체온 알림 임계치
    created_at      = Column(DateTime, default=_now)


class Member(Base):
    """직원 계정. 인증 주체이자 테넌트 소속."""
    __tablename__ = "members"

    id           = Column(String, primary_key=True, default=_uuid)
    tenant_id    = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    username     = Column(String, nullable=False, index=True)
    display_name = Column(String, nullable=False)
    hashed_pw    = Column(String, nullable=False)
    pin_code     = Column(String, nullable=True)   # 4자리 빠른 전환 PIN (테넌트 내 유일)
    role         = Column(String, default="nurse") # owner|admin|nurse|cleaner
    created_at   = Column(DateTime, default=_now)

    # username 은 테넌트 내에서만 유일 (테넌트 간 중복 허용)
    __table_args__ = (
        Index("ix_member_tenant_username", "tenant_id", "username", unique=True),
    )


class TenantInvite(Base):
    """직원 초대코드 (owner/admin 발급). 가입 시 tenant_id + role 부여."""
    __tablename__ = "tenant_invites"

    code       = Column(String, primary_key=True)
    tenant_id  = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    role       = Column(String, default="nurse")   # 가입 시 부여할 역할
    created_by = Column(String, ForeignKey("members.id"))
    used_by    = Column(String, ForeignKey("members.id"), nullable=True)
    expires_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=_now)


class Room(Base):
    """구역/방."""
    __tablename__ = "rooms"

    id         = Column(String, primary_key=True, default=_uuid)
    tenant_id  = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    name       = Column(String, nullable=False)
    created_at = Column(DateTime, default=_now)
    updated_at = Column(DateTime, default=_now, onupdate=_now)
    deleted    = Column(Boolean, default=False)


class Baby(Base):
    """신생아."""
    __tablename__ = "babies"

    id            = Column(String, primary_key=True, default=_uuid)
    tenant_id     = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    name          = Column(String, nullable=False)
    room_id       = Column(String, ForeignKey("rooms.id"), nullable=True)
    birth_date    = Column(Date, nullable=True)
    guardian_name = Column(String, default="")
    is_active     = Column(Boolean, default=True)
    created_at    = Column(DateTime, default=_now)
    updated_at    = Column(DateTime, default=_now, onupdate=_now)
    deleted       = Column(Boolean, default=False)


class NeonatalHealthLog(Base):
    """신생아 건강 로그. temperature >= tenant.temp_threshold 시 알림 트리거."""
    __tablename__ = "neonatal_health_log"

    id          = Column(String, primary_key=True, default=_uuid)
    tenant_id   = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    baby_id     = Column(String, ForeignKey("babies.id"), nullable=False, index=True)
    temperature = Column(Float, nullable=True)
    feeding_ml  = Column(Integer, nullable=True)
    memo        = Column(Text, default="")
    timestamp   = Column(DateTime, default=_now)
    worker_id   = Column(String, ForeignKey("members.id"), nullable=True)
    created_at  = Column(DateTime, default=_now)
    updated_at  = Column(DateTime, default=_now, onupdate=_now)
    deleted     = Column(Boolean, default=False)


class RoutineTask(Base):
    """루틴 업무 체크 (소독/환기 등). completed_time Null = 미완료."""
    __tablename__ = "routine_tasks"

    id             = Column(String, primary_key=True, default=_uuid)
    tenant_id      = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    room_id        = Column(String, ForeignKey("rooms.id"), nullable=True)
    task_name      = Column(String, nullable=False)
    scheduled_time = Column(DateTime, nullable=True)
    completed_time = Column(DateTime, nullable=True)
    completed_by   = Column(String, ForeignKey("members.id"), nullable=True)
    created_at     = Column(DateTime, default=_now)
    updated_at     = Column(DateTime, default=_now, onupdate=_now)
    deleted        = Column(Boolean, default=False)


class Notice(Base):
    """조리원 공지. owner/admin 이 작성, 전 직원이 조회."""
    __tablename__ = "notices"

    id         = Column(String, primary_key=True, default=_uuid)
    tenant_id  = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    title      = Column(String, nullable=False)
    body       = Column(Text, default="")
    pinned     = Column(Boolean, default=False)   # 상단 고정
    created_by = Column(String, ForeignKey("members.id"), nullable=True)
    created_at = Column(DateTime, default=_now)
    updated_at = Column(DateTime, default=_now, onupdate=_now)
    deleted    = Column(Boolean, default=False)
