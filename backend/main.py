"""살림노트 backend server — FastAPI + PostgreSQL."""

import os
import secrets
import string
from datetime import datetime, date
from typing import Optional

from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session

from models import (
    Base, Member, FamilyInvite,
    MonthlyBudget, FixedExpense, Investment, InstallmentSavings, TodoItem, Schedule,
)
from auth import (
    hash_password, verify_password, create_token,
    get_current_member, require_admin,
)

DATABASE_URL = os.environ["DATABASE_URL"]
engine       = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base.metadata.create_all(bind=engine)

ADMIN_INIT_CODE = os.environ.get("ADMIN_INIT_CODE", "admin-setup-2025")

app = FastAPI(title="살림노트 API", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def _now_str() -> str:
    return datetime.utcnow().isoformat()


def _parse_dt(s: Optional[str]) -> Optional[datetime]:
    if not s:
        return None
    try:
        return datetime.fromisoformat(s)
    except Exception:
        return None


# ── Schema (Pydantic) ─────────────────────────────────────────────────────────

class RegisterRequest(BaseModel):
    username:     str
    display_name: str
    password:     str
    invite_code:  str   # admin-setup code OR family invite code

class TokenResponse(BaseModel):
    access_token:  str
    token_type:    str = "bearer"
    member_id:     str
    display_name:  str
    role:          str

class InviteResponse(BaseModel):
    code: str

class BudgetIn(BaseModel):
    husband_income: float = 0
    wife_income:    float = 0
    husband_pocket: float = 0
    wife_pocket:    float = 0
    note:           str   = ""

class ExpenseIn(BaseModel):
    id:         Optional[str] = None
    name:       str
    amount:     float = 0
    category:   str   = "기타"
    note:       str   = ""
    is_active:  bool  = True
    sort_order: int   = 0
    deleted:    bool  = False

class InvestmentIn(BaseModel):
    id:             Optional[str] = None
    name:           str
    type:           str   = "기타"
    monthly_amount: float = 0
    current_value:  float = 0
    note:           str   = ""
    is_active:      bool  = True
    deleted:        bool  = False

class SavingsIn(BaseModel):
    id:             Optional[str] = None
    name:           str
    target_amount:  float = 0
    monthly_amount: float = 0
    paid_months:    int   = 0
    total_months:   int   = 12
    start_date:     Optional[str] = None
    status:         str   = "진행중"
    note:           str   = ""
    deleted:        bool  = False

class TodoIn(BaseModel):
    id:               Optional[str] = None
    title:            str
    note:             str   = ""
    is_completed:     bool  = False
    priority:         int   = 1
    assignee:         str   = "공동"
    category:         str   = "일반"
    due_date:         Optional[str] = None
    reminder_enabled: bool  = False
    reminder_date:    Optional[str] = None
    completed_at:     Optional[str] = None
    deleted:          bool  = False

class ScheduleIn(BaseModel):
    id:       Optional[str] = None
    title:    str
    date:     str           # "YYYY-MM-DD"
    time:     Optional[str] = None   # "HH:MM" or null
    all_day:  bool  = True
    category: str   = "일반"
    note:     str   = ""
    deleted:  bool  = False

class SyncRequest(BaseModel):
    """Full sync payload — client sends all local changes, receives full server state."""
    expenses:    list[ExpenseIn]    = []
    investments: list[InvestmentIn] = []
    savings:     list[SavingsIn]    = []
    todos:       list[TodoIn]       = []
    schedules:   list[ScheduleIn]   = []
    budgets:     list[dict]         = []  # [{year, month, ...BudgetIn}] — plural to match client

# ── Auth ──────────────────────────────────────────────────────────────────────

@app.post("/auth/register", response_model=TokenResponse)
def register(req: RegisterRequest, db: Session = Depends(get_db)):
    # Validate invite code
    is_admin_setup = req.invite_code == ADMIN_INIT_CODE
    invite = None

    if not is_admin_setup:
        invite = db.query(FamilyInvite).filter(
            FamilyInvite.code == req.invite_code,
            FamilyInvite.used_by == None,
        ).first()
        if not invite:
            raise HTTPException(400, "Invalid or already-used invite code")

    if db.query(Member).filter(Member.username == req.username).first():
        raise HTTPException(400, "Username already taken")

    # Admin only if using admin setup code AND no admin exists yet
    admin_exists = db.query(Member).filter(Member.role == "admin").first()
    role = "admin" if (is_admin_setup and not admin_exists) else "member"

    member = Member(
        username     = req.username,
        display_name = req.display_name,
        hashed_pw    = hash_password(req.password),
        role         = role,
        invite_code  = req.invite_code,
    )
    db.add(member)

    if invite:
        invite.used_by = member.id
    db.commit()
    db.refresh(member)

    token = create_token(member.id, member.username, member.role)
    return TokenResponse(
        access_token = token,
        member_id    = member.id,
        display_name = member.display_name,
        role         = member.role,
    )


@app.post("/auth/login", response_model=TokenResponse)
def login(form: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    member = db.query(Member).filter(Member.username == form.username).first()
    if not member or not verify_password(form.password, member.hashed_pw):
        raise HTTPException(status_code=401, detail="잘못된 사용자명 또는 비밀번호")
    token = create_token(member.id, member.username, member.role)
    return TokenResponse(
        access_token = token,
        member_id    = member.id,
        display_name = member.display_name,
        role         = member.role,
    )


@app.get("/auth/me")
def me(payload: dict = Depends(get_current_member), db: Session = Depends(get_db)):
    member = db.query(Member).filter(Member.id == payload["sub"]).first()
    if not member:
        raise HTTPException(404, "Member not found")
    return {
        "id":           member.id,
        "username":     member.username,
        "display_name": member.display_name,
        "role":         member.role,
    }


@app.post("/admin/invite", response_model=InviteResponse)
def create_invite(payload: dict = Depends(require_admin), db: Session = Depends(get_db)):
    code = "".join(secrets.choice(string.ascii_uppercase + string.digits) for _ in range(8))
    invite = FamilyInvite(code=code, created_by=payload["sub"])
    db.add(invite)
    db.commit()
    return InviteResponse(code=code)


@app.get("/admin/members")
def list_members(payload: dict = Depends(require_admin), db: Session = Depends(get_db)):
    return [
        {"id": m.id, "username": m.username, "display_name": m.display_name,
         "role": m.role, "created_at": m.created_at.isoformat()}
        for m in db.query(Member).all()
    ]


# ── Sync ──────────────────────────────────────────────────────────────────────

@app.post("/sync")
def sync(req: SyncRequest, payload: dict = Depends(get_current_member), db: Session = Depends(get_db)):
    """
    Merge strategy: last-write-wins by updated_at.
    Client sends all local changes; server applies and returns full current state.
    """
    now = datetime.utcnow()

    # --- Budgets (iterate list sent by client) ---
    for b in req.budgets:
        year  = b.get("year")
        month = b.get("month")
        if not (year and month):
            continue
        existing = db.query(MonthlyBudget).filter(
            MonthlyBudget.year == year,
            MonthlyBudget.month == month,
        ).first()
        if existing:
            existing.husband_income = b.get("husband_income", existing.husband_income)
            existing.wife_income    = b.get("wife_income",    existing.wife_income)
            existing.husband_pocket = b.get("husband_pocket", existing.husband_pocket)
            existing.wife_pocket    = b.get("wife_pocket",    existing.wife_pocket)
            existing.note           = b.get("note",           existing.note)
            existing.updated_at     = now
        else:
            db.add(MonthlyBudget(
                year           = year,
                month          = month,
                husband_income = b.get("husband_income", 0),
                wife_income    = b.get("wife_income",    0),
                husband_pocket = b.get("husband_pocket", 0),
                wife_pocket    = b.get("wife_pocket",    0),
                note           = b.get("note",           ""),
                updated_at     = now,
            ))

    # --- Generic upsert helper ---
    def upsert(ModelClass, items, field_map: dict):
        for item in items:
            obj = db.query(ModelClass).filter(ModelClass.id == item.id).first() if item.id else None
            if obj:
                for attr, val in field_map(item).items():
                    setattr(obj, attr, val)
                obj.updated_at = now
                obj.deleted    = item.deleted
            elif not item.deleted:
                new_obj = ModelClass(updated_at=now)
                if item.id:
                    new_obj.id = item.id
                for attr, val in field_map(item).items():
                    setattr(new_obj, attr, val)
                db.add(new_obj)

    upsert(FixedExpense, req.expenses, lambda i: {
        "name": i.name, "amount": i.amount, "category": i.category,
        "note": i.note, "is_active": i.is_active, "sort_order": i.sort_order,
        "deleted": i.deleted,
    })

    upsert(Investment, req.investments, lambda i: {
        "name": i.name, "type": i.type, "monthly_amount": i.monthly_amount,
        "current_value": i.current_value, "note": i.note, "is_active": i.is_active,
        "deleted": i.deleted,
    })

    upsert(InstallmentSavings, req.savings, lambda i: {
        "name": i.name, "target_amount": i.target_amount, "monthly_amount": i.monthly_amount,
        "paid_months": i.paid_months, "total_months": i.total_months,
        "start_date": _parse_dt(i.start_date) or datetime.utcnow(),
        "status": i.status, "note": i.note, "deleted": i.deleted,
    })

    upsert(TodoItem, req.todos, lambda i: {
        "title": i.title, "note": i.note, "is_completed": i.is_completed,
        "priority": i.priority, "assignee": i.assignee, "category": i.category,
        "due_date": _parse_dt(i.due_date), "reminder_enabled": i.reminder_enabled,
        "reminder_date": _parse_dt(i.reminder_date),
        "completed_at": _parse_dt(i.completed_at), "deleted": i.deleted,
    })

    upsert(Schedule, req.schedules, lambda i: {
        "title": i.title, "date": i.date, "time": i.time,
        "all_day": i.all_day, "category": i.category,
        "note": i.note, "deleted": i.deleted,
    })

    db.commit()

    # Return full server state
    return _full_state(db)


@app.get("/sync")
def get_state(payload: dict = Depends(get_current_member), db: Session = Depends(get_db)):
    """Pull full current state (used on first launch / pull-to-refresh)."""
    return _full_state(db)


def _full_state(db: Session) -> dict:
    def budget_dict(b: MonthlyBudget) -> dict:
        return {
            "id": b.id, "year": b.year, "month": b.month,
            "husband_income": b.husband_income, "wife_income": b.wife_income,
            "husband_pocket": b.husband_pocket, "wife_pocket": b.wife_pocket,
            "note": b.note, "updated_at": b.updated_at.isoformat(),
        }

    def expense_dict(e: FixedExpense) -> dict:
        return {
            "id": e.id, "name": e.name, "amount": e.amount, "category": e.category,
            "note": e.note, "is_active": e.is_active, "sort_order": e.sort_order,
            "created_at": e.created_at.isoformat(), "updated_at": e.updated_at.isoformat(),
        }

    def inv_dict(i: Investment) -> dict:
        return {
            "id": i.id, "name": i.name, "type": i.type,
            "monthly_amount": i.monthly_amount, "current_value": i.current_value,
            "note": i.note, "is_active": i.is_active,
            "created_at": i.created_at.isoformat(), "updated_at": i.updated_at.isoformat(),
        }

    def saving_dict(s: InstallmentSavings) -> dict:
        return {
            "id": s.id, "name": s.name, "target_amount": s.target_amount,
            "monthly_amount": s.monthly_amount, "paid_months": s.paid_months,
            "total_months": s.total_months,
            "start_date": s.start_date.isoformat() if s.start_date else None,
            "status": s.status, "note": s.note,
            "created_at": s.created_at.isoformat(), "updated_at": s.updated_at.isoformat(),
        }

    def todo_dict(t: TodoItem) -> dict:
        return {
            "id": t.id, "title": t.title, "note": t.note,
            "is_completed": t.is_completed, "priority": t.priority,
            "assignee": t.assignee, "category": t.category,
            "due_date": t.due_date.isoformat() if t.due_date else None,
            "reminder_enabled": t.reminder_enabled,
            "reminder_date": t.reminder_date.isoformat() if t.reminder_date else None,
            "completed_at": t.completed_at.isoformat() if t.completed_at else None,
            "created_at": t.created_at.isoformat(), "updated_at": t.updated_at.isoformat(),
        }

    def schedule_dict(s: Schedule) -> dict:
        return {
            "id": s.id, "title": s.title, "date": s.date, "time": s.time,
            "all_day": s.all_day, "category": s.category, "note": s.note,
            "created_at": s.created_at.isoformat(), "updated_at": s.updated_at.isoformat(),
        }

    return {
        "budgets":     [budget_dict(b) for b in db.query(MonthlyBudget).all()],
        "expenses":    [expense_dict(e) for e in db.query(FixedExpense).filter(FixedExpense.deleted == False).all()],
        "investments": [inv_dict(i) for i in db.query(Investment).filter(Investment.deleted == False).all()],
        "savings":     [saving_dict(s) for s in db.query(InstallmentSavings).filter(InstallmentSavings.deleted == False).all()],
        "todos":       [todo_dict(t) for t in db.query(TodoItem).filter(TodoItem.deleted == False).all()],
        "schedules":   [schedule_dict(s) for s in db.query(Schedule).filter(Schedule.deleted == False).all()],
        "synced_at":   datetime.utcnow().isoformat(),
    }


@app.get("/health")
def health():
    return {"status": "ok", "service": "살림노트"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
