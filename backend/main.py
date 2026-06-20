"""산후조리원 멀티테넌트 backend — FastAPI + PostgreSQL.

모든 도메인 데이터는 tenant_id 로 격리된다. 도메인 쿼리는 예외 없이
get_tenant_scope 로 얻은 tenant_id 로 필터링한다(테넌트 누수 방지).
"""

import os
import secrets
import string
from datetime import datetime, date
from typing import Optional

from fastapi import FastAPI, Depends, HTTPException, Query
from fastapi.security import OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session

from models import (
    Base, Tenant, Member, TenantInvite,
    Room, Baby, NeonatalHealthLog, RoutineTask,
)
from auth import (
    hash_password, verify_password, create_token,
    get_current_member, get_tenant_scope, require_admin,
)

DATABASE_URL = os.environ.get("DATABASE_URL", "sqlite:///./dev.db")

# SQLite(개발/테스트)는 스레드 체크 옵션 필요
_connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}
engine       = create_engine(DATABASE_URL, connect_args=_connect_args)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# sqlite(개발/테스트)에서는 편의상 자동 생성한다.
# PostgreSQL(운영)에서는 `alembic upgrade head` 로 스키마를 관리하므로 create_all 을
# 호출하지 않는다(마이그레이션 이력과 충돌 방지).
if DATABASE_URL.startswith("sqlite"):
    Base.metadata.create_all(bind=engine)

app = FastAPI(title="산후조리원 관리 API", version="2.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.environ.get("CORS_ORIGINS", "*").split(","),
    allow_methods=["*"],
    allow_headers=["*"],
)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def _parse_dt(s: Optional[str]) -> Optional[datetime]:
    if not s:
        return None
    try:
        return datetime.fromisoformat(s)
    except Exception:
        return None


def _parse_date(s: Optional[str]) -> Optional[date]:
    if not s:
        return None
    try:
        return date.fromisoformat(s)
    except Exception:
        return None


# ── Schema (Pydantic) ─────────────────────────────────────────────────────────

class RegisterTenantRequest(BaseModel):
    """신규 조리원 + owner 계정 생성."""
    tenant_name:  str
    username:     str
    display_name: str
    password:     str
    pin_code:     Optional[str] = None


class RegisterStaffRequest(BaseModel):
    """초대코드로 직원 가입."""
    username:     str
    display_name: str
    password:     str
    invite_code:  str
    pin_code:     Optional[str] = None


class TokenResponse(BaseModel):
    access_token: str
    token_type:   str = "bearer"
    member_id:    str
    display_name: str
    role:         str
    tenant_id:    str
    tenant_name:  str


class PinLoginRequest(BaseModel):
    pin_code: str


class InviteRequest(BaseModel):
    role: str = "nurse"


class InviteResponse(BaseModel):
    code: str
    role: str


class RoomIn(BaseModel):
    id:      Optional[str] = None
    name:    str
    deleted: bool = False


class BabyIn(BaseModel):
    id:            Optional[str] = None
    name:          str
    room_id:       Optional[str] = None
    birth_date:    Optional[str] = None      # "YYYY-MM-DD"
    guardian_name: str  = ""
    is_active:     bool = True
    deleted:       bool = False


class HealthLogIn(BaseModel):
    id:          Optional[str] = None
    baby_id:     str
    temperature: Optional[float] = None
    feeding_ml:  Optional[int]   = None
    memo:        str = ""
    timestamp:   Optional[str] = None
    worker_id:   Optional[str] = None
    deleted:     bool = False


class RoutineTaskIn(BaseModel):
    id:             Optional[str] = None
    room_id:        Optional[str] = None
    task_name:      str
    scheduled_time: Optional[str] = None
    completed_time: Optional[str] = None
    completed_by:   Optional[str] = None
    deleted:        bool = False


class SyncRequest(BaseModel):
    """오프라인 단말의 로컬 변경분 업로드. 서버는 테넌트 상태 반환."""
    rooms:         list[RoomIn]        = []
    babies:        list[BabyIn]        = []
    health_logs:   list[HealthLogIn]   = []
    routine_tasks: list[RoutineTaskIn] = []


# ── Auth ──────────────────────────────────────────────────────────────────────

@app.post("/auth/register-tenant", response_model=TokenResponse)
def register_tenant(req: RegisterTenantRequest, db: Session = Depends(get_db)):
    """신규 조리원 개설 + owner 계정 생성."""
    tenant = Tenant(name=req.tenant_name)
    db.add(tenant)
    db.flush()  # tenant.id 확보

    member = Member(
        tenant_id    = tenant.id,
        username     = req.username,
        display_name = req.display_name,
        hashed_pw    = hash_password(req.password),
        pin_code     = req.pin_code,
        role         = "owner",
    )
    db.add(member)
    db.commit()
    db.refresh(member)
    db.refresh(tenant)

    token = create_token(member.id, member.username, member.role, tenant.id)
    return TokenResponse(
        access_token=token, member_id=member.id, display_name=member.display_name,
        role=member.role, tenant_id=tenant.id, tenant_name=tenant.name,
    )


@app.post("/auth/register", response_model=TokenResponse)
def register_staff(req: RegisterStaffRequest, db: Session = Depends(get_db)):
    """초대코드로 직원 가입 — 해당 코드의 tenant_id / role 을 부여받는다."""
    invite = db.query(TenantInvite).filter(
        TenantInvite.code == req.invite_code,
        TenantInvite.used_by == None,
    ).first()
    if not invite:
        raise HTTPException(400, "유효하지 않거나 이미 사용된 초대코드")
    if invite.expires_at and invite.expires_at < datetime.utcnow():
        raise HTTPException(400, "만료된 초대코드")

    # username 은 테넌트 내에서만 유일하면 됨
    dup = db.query(Member).filter(
        Member.tenant_id == invite.tenant_id,
        Member.username == req.username,
    ).first()
    if dup:
        raise HTTPException(400, "이미 사용 중인 사용자명")

    tenant = db.query(Tenant).filter(Tenant.id == invite.tenant_id).first()
    if not tenant:
        raise HTTPException(400, "초대코드의 조리원이 존재하지 않음")

    member = Member(
        tenant_id    = invite.tenant_id,
        username     = req.username,
        display_name = req.display_name,
        hashed_pw    = hash_password(req.password),
        pin_code     = req.pin_code,
        role         = invite.role,
    )
    db.add(member)
    db.flush()
    invite.used_by = member.id
    db.commit()
    db.refresh(member)

    token = create_token(member.id, member.username, member.role, tenant.id)
    return TokenResponse(
        access_token=token, member_id=member.id, display_name=member.display_name,
        role=member.role, tenant_id=tenant.id, tenant_name=tenant.name,
    )


@app.post("/auth/login", response_model=TokenResponse)
def login(form: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    """username 은 테넌트 간 중복될 수 있으므로 password 로 매칭되는 계정을 찾는다.

    클라이언트가 tenant 를 명시하려면 form.client_id 에 tenant_id 를 넣을 수 있다.
    """
    q = db.query(Member).filter(Member.username == form.username)
    if form.client_id:  # 선택: tenant_id 명시
        q = q.filter(Member.tenant_id == form.client_id)
    candidates = q.all()
    member = next((m for m in candidates if verify_password(form.password, m.hashed_pw)), None)
    if not member:
        raise HTTPException(status_code=401, detail="잘못된 사용자명 또는 비밀번호")

    tenant = db.query(Tenant).filter(Tenant.id == member.tenant_id).first()
    token = create_token(member.id, member.username, member.role, member.tenant_id)
    return TokenResponse(
        access_token=token, member_id=member.id, display_name=member.display_name,
        role=member.role, tenant_id=member.tenant_id,
        tenant_name=tenant.name if tenant else "",
    )


@app.post("/auth/pin-login", response_model=TokenResponse)
def pin_login(req: PinLoginRequest, tid: str = Depends(get_tenant_scope),
              db: Session = Depends(get_db)):
    """공용 태블릿 빠른 전환 — 현재 테넌트 토큰 보유 상태에서 PIN 으로 직원 전환."""
    member = db.query(Member).filter(
        Member.tenant_id == tid,
        Member.pin_code == req.pin_code,
    ).first()
    if not member or not req.pin_code:
        raise HTTPException(401, "잘못된 PIN")

    tenant = db.query(Tenant).filter(Tenant.id == tid).first()
    token = create_token(member.id, member.username, member.role, tid)
    return TokenResponse(
        access_token=token, member_id=member.id, display_name=member.display_name,
        role=member.role, tenant_id=tid, tenant_name=tenant.name if tenant else "",
    )


@app.get("/auth/me")
def me(payload: dict = Depends(get_current_member), tid: str = Depends(get_tenant_scope),
       db: Session = Depends(get_db)):
    member = db.query(Member).filter(
        Member.id == payload["sub"], Member.tenant_id == tid,
    ).first()
    if not member:
        raise HTTPException(404, "Member not found")
    return {
        "id": member.id, "username": member.username,
        "display_name": member.display_name, "role": member.role,
        "tenant_id": member.tenant_id,
    }


@app.post("/admin/invite", response_model=InviteResponse)
def create_invite(req: InviteRequest, payload: dict = Depends(require_admin),
                  tid: str = Depends(get_tenant_scope), db: Session = Depends(get_db)):
    if req.role not in ("admin", "nurse", "cleaner"):
        raise HTTPException(400, "잘못된 역할")
    code = "".join(secrets.choice(string.ascii_uppercase + string.digits) for _ in range(8))
    invite = TenantInvite(code=code, tenant_id=tid, role=req.role, created_by=payload["sub"])
    db.add(invite)
    db.commit()
    return InviteResponse(code=code, role=req.role)


@app.get("/admin/members")
def list_members(payload: dict = Depends(require_admin),
                 tid: str = Depends(get_tenant_scope), db: Session = Depends(get_db)):
    return [
        {"id": m.id, "username": m.username, "display_name": m.display_name,
         "role": m.role, "created_at": m.created_at.isoformat()}
        for m in db.query(Member).filter(Member.tenant_id == tid).all()
    ]


# ── Sync ──────────────────────────────────────────────────────────────────────

@app.post("/sync")
def sync(req: SyncRequest, tid: str = Depends(get_tenant_scope),
         payload: dict = Depends(get_current_member), db: Session = Depends(get_db),
         since: Optional[str] = Query(None)):
    """오프라인 단말 변경분 업서트 (테넌트 강제 주입, last-write-wins).

    반환: 테넌트 전체/델타 상태 + 임계치 위반 알림(alerts).
    """
    now = datetime.utcnow()

    def upsert(ModelClass, items, field_map):
        """tenant_id 를 항상 서버가 강제 주입한다(클라이언트 값 신뢰 안 함)."""
        for item in items:
            obj = None
            if item.id:
                obj = db.query(ModelClass).filter(
                    ModelClass.id == item.id, ModelClass.tenant_id == tid,
                ).first()
            if obj:
                for attr, val in field_map(item).items():
                    setattr(obj, attr, val)
                obj.updated_at = now
                obj.deleted = item.deleted
            elif not item.deleted:
                # id 가 다른 테넌트에 이미 존재하면(글로벌 PK 충돌/탈취 시도) 무시한다.
                if item.id and db.query(ModelClass).filter(ModelClass.id == item.id).first():
                    continue
                new_obj = ModelClass(tenant_id=tid, updated_at=now)
                if item.id:
                    new_obj.id = item.id
                for attr, val in field_map(item).items():
                    setattr(new_obj, attr, val)
                db.add(new_obj)

    upsert(Room, req.rooms, lambda i: {"name": i.name, "deleted": i.deleted})

    upsert(Baby, req.babies, lambda i: {
        "name": i.name, "room_id": i.room_id,
        "birth_date": _parse_date(i.birth_date),
        "guardian_name": i.guardian_name, "is_active": i.is_active,
        "deleted": i.deleted,
    })

    upsert(NeonatalHealthLog, req.health_logs, lambda i: {
        "baby_id": i.baby_id, "temperature": i.temperature,
        "feeding_ml": i.feeding_ml, "memo": i.memo,
        "timestamp": _parse_dt(i.timestamp) or now,
        "worker_id": i.worker_id, "deleted": i.deleted,
    })

    upsert(RoutineTask, req.routine_tasks, lambda i: {
        "room_id": i.room_id, "task_name": i.task_name,
        "scheduled_time": _parse_dt(i.scheduled_time),
        "completed_time": _parse_dt(i.completed_time),
        "completed_by": i.completed_by, "deleted": i.deleted,
    })

    db.commit()

    alerts = _detect_alerts(db, tid, req.health_logs, now)
    state = _full_state(db, tid, _parse_dt(since))
    state["alerts"] = alerts
    return state


@app.get("/sync")
def get_state(tid: str = Depends(get_tenant_scope), db: Session = Depends(get_db),
              since: Optional[str] = Query(None)):
    """전체/델타 상태 pull. since(ISO) 지정 시 updated_at 이후 변경분만."""
    return _full_state(db, tid, _parse_dt(since))


def _detect_alerts(db: Session, tid: str, health_logs, now: datetime) -> list[dict]:
    """체온 임계치 위반 감지. (Phase 3 에서 이 결과로 FCM 발송)"""
    tenant = db.query(Tenant).filter(Tenant.id == tid).first()
    threshold = tenant.temp_threshold if tenant else 37.5
    alerts = []
    for log in health_logs:
        if log.deleted or log.temperature is None:
            continue
        if log.temperature >= threshold:
            alerts.append({
                "type": "high_temp", "severity": "warning",
                "baby_id": log.baby_id, "temperature": log.temperature,
                "threshold": threshold,
                "message": f"체온 {log.temperature}℃ (임계치 {threshold}℃ 초과)",
            })
    return alerts


def _full_state(db: Session, tid: str, since: Optional[datetime] = None) -> dict:
    def _f(query, model):
        if since is not None:
            query = query.filter(model.updated_at > since)
        else:
            query = query.filter(model.deleted == False)
        return query

    def room_dict(r: Room) -> dict:
        return {"id": r.id, "name": r.name, "deleted": r.deleted,
                "updated_at": r.updated_at.isoformat()}

    def baby_dict(b: Baby) -> dict:
        return {"id": b.id, "name": b.name, "room_id": b.room_id,
                "birth_date": b.birth_date.isoformat() if b.birth_date else None,
                "guardian_name": b.guardian_name, "is_active": b.is_active,
                "deleted": b.deleted, "updated_at": b.updated_at.isoformat()}

    def log_dict(l: NeonatalHealthLog) -> dict:
        return {"id": l.id, "baby_id": l.baby_id, "temperature": l.temperature,
                "feeding_ml": l.feeding_ml, "memo": l.memo,
                "timestamp": l.timestamp.isoformat() if l.timestamp else None,
                "worker_id": l.worker_id, "deleted": l.deleted,
                "updated_at": l.updated_at.isoformat()}

    def task_dict(t: RoutineTask) -> dict:
        return {"id": t.id, "room_id": t.room_id, "task_name": t.task_name,
                "scheduled_time": t.scheduled_time.isoformat() if t.scheduled_time else None,
                "completed_time": t.completed_time.isoformat() if t.completed_time else None,
                "completed_by": t.completed_by, "deleted": t.deleted,
                "updated_at": t.updated_at.isoformat()}

    rooms = _f(db.query(Room).filter(Room.tenant_id == tid), Room).all()
    babies = _f(db.query(Baby).filter(Baby.tenant_id == tid), Baby).all()
    logs = _f(db.query(NeonatalHealthLog).filter(NeonatalHealthLog.tenant_id == tid),
              NeonatalHealthLog).all()
    tasks = _f(db.query(RoutineTask).filter(RoutineTask.tenant_id == tid), RoutineTask).all()

    return {
        "rooms":         [room_dict(r) for r in rooms],
        "babies":        [baby_dict(b) for b in babies],
        "health_logs":   [log_dict(l) for l in logs],
        "routine_tasks": [task_dict(t) for t in tasks],
        "synced_at":     datetime.utcnow().isoformat(),
    }


@app.get("/health")
def health():
    return {"status": "ok", "service": "산후조리원 관리"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
