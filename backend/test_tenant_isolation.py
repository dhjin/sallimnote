"""테넌트 격리 자동 테스트 — 두 조리원의 데이터가 절대 교차 조회되지 않음을 증명.

실행:
    cd backend
    DATABASE_URL=sqlite:///./test.db pytest -q
(테스트는 임시 sqlite 파일을 사용하므로 PostgreSQL 불필요.)
"""

import os
import tempfile
import importlib

import pytest
from fastapi.testclient import TestClient


@pytest.fixture()
def client():
    # 각 테스트마다 깨끗한 임시 DB 로 main 모듈을 새로 로드한다.
    db_path = tempfile.mktemp(suffix=".db")
    os.environ["DATABASE_URL"] = f"sqlite:///{db_path}"
    os.environ["JWT_SECRET"] = "test-secret"

    import main
    importlib.reload(main)
    with TestClient(main.app) as c:
        yield c
    if os.path.exists(db_path):
        os.remove(db_path)


def _register_tenant(client, tenant_name, username):
    r = client.post("/auth/register-tenant", json={
        "tenant_name": tenant_name, "username": username,
        "display_name": username, "password": "pw12345", "pin_code": "1111",
    })
    assert r.status_code == 200, r.text
    return r.json()


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def test_two_tenants_are_isolated(client):
    a = _register_tenant(client, "조리원A", "ownerA")
    b = _register_tenant(client, "조리원B", "ownerB")

    assert a["tenant_id"] != b["tenant_id"]
    assert a["role"] == "owner"

    # A 가 신생아/방/건강로그 입력
    r = client.post("/sync", headers=_auth(a["access_token"]), json={
        "rooms":  [{"id": "room-a", "name": "A동 101호"}],
        "babies": [{"id": "baby-a", "name": "아기A", "room_id": "room-a"}],
        "health_logs": [{"id": "log-a", "baby_id": "baby-a", "temperature": 36.8}],
    })
    assert r.status_code == 200, r.text

    # B 가 자기 데이터 입력
    client.post("/sync", headers=_auth(b["access_token"]), json={
        "babies": [{"id": "baby-b", "name": "아기B"}],
    })

    # A 의 상태에는 A 데이터만
    state_a = client.get("/sync", headers=_auth(a["access_token"])).json()
    assert {x["id"] for x in state_a["babies"]} == {"baby-a"}
    assert {x["id"] for x in state_a["rooms"]} == {"room-a"}

    # B 의 상태에는 B 데이터만 — A 데이터 누수 없음
    state_b = client.get("/sync", headers=_auth(b["access_token"])).json()
    assert {x["id"] for x in state_b["babies"]} == {"baby-b"}
    assert state_b["rooms"] == []
    assert state_b["health_logs"] == []


def test_cannot_overwrite_other_tenant_record(client):
    a = _register_tenant(client, "조리원A", "ownerA")
    b = _register_tenant(client, "조리원B", "ownerB")

    client.post("/sync", headers=_auth(a["access_token"]), json={
        "babies": [{"id": "baby-a", "name": "아기A"}],
    })

    # B 가 A 의 baby id 로 덮어쓰기 시도 → 같은 id 가 B 테넌트에 없으므로
    # B 소속 신규 레코드로 생성될 뿐, A 의 레코드는 불변이어야 한다.
    client.post("/sync", headers=_auth(b["access_token"]), json={
        "babies": [{"id": "baby-a", "name": "해킹시도"}],
    })

    state_a = client.get("/sync", headers=_auth(a["access_token"])).json()
    baby_a = next(x for x in state_a["babies"] if x["id"] == "baby-a")
    assert baby_a["name"] == "아기A"  # 변경되지 않음


def test_high_temp_triggers_alert(client):
    a = _register_tenant(client, "조리원A", "ownerA")
    r = client.post("/sync", headers=_auth(a["access_token"]), json={
        "babies": [{"id": "baby-a", "name": "아기A"}],
        "health_logs": [{"id": "log-hot", "baby_id": "baby-a", "temperature": 38.1}],
    })
    body = r.json()
    assert len(body["alerts"]) == 1
    assert body["alerts"][0]["type"] == "high_temp"
    assert body["alerts"][0]["temperature"] == 38.1


def test_pin_login_switches_within_tenant(client):
    a = _register_tenant(client, "조리원A", "ownerA")
    # owner 가 간호사 초대코드 생성 → 가입
    inv = client.post("/admin/invite", headers=_auth(a["access_token"]),
                      json={"role": "nurse"}).json()
    nurse = client.post("/auth/register", json={
        "username": "nurse1", "display_name": "간호사", "password": "pw12345",
        "invite_code": inv["code"], "pin_code": "2222",
    }).json()
    assert nurse["role"] == "nurse"

    # 공용 태블릿: 현재 토큰(owner)로 PIN 2222 전환 → nurse 세션
    r = client.post("/auth/pin-login", headers=_auth(a["access_token"]),
                    json={"pin_code": "2222"})
    assert r.status_code == 200, r.text
    assert r.json()["member_id"] == nurse["member_id"]
    assert r.json()["tenant_id"] == a["tenant_id"]


def test_notice_admin_writes_staff_reads(client):
    a = _register_tenant(client, "조리원A", "ownerA")
    # owner 가 공지 작성
    r = client.post("/sync", headers=_auth(a["access_token"]), json={
        "notices": [{"id": "n1", "title": "오늘 소독 일정", "body": "14시 전체 소독",
                     "pinned": True}],
    })
    assert r.status_code == 200, r.text
    assert {n["id"] for n in r.json()["notices"]} == {"n1"}

    # 직원(nurse)도 공지를 조회할 수 있어야 한다
    inv = client.post("/admin/invite", headers=_auth(a["access_token"]),
                      json={"role": "nurse"}).json()
    nurse = client.post("/auth/register", json={
        "username": "nurse1", "display_name": "간호사", "password": "pw12345",
        "invite_code": inv["code"],
    }).json()
    state = client.get("/sync", headers=_auth(nurse["access_token"])).json()
    n = next(x for x in state["notices"] if x["id"] == "n1")
    assert n["title"] == "오늘 소독 일정"
    assert n["pinned"] is True


def test_notice_write_blocked_for_non_admin(client):
    a = _register_tenant(client, "조리원A", "ownerA")
    inv = client.post("/admin/invite", headers=_auth(a["access_token"]),
                      json={"role": "nurse"}).json()
    nurse = client.post("/auth/register", json={
        "username": "nurse1", "display_name": "간호사", "password": "pw12345",
        "invite_code": inv["code"],
    }).json()

    # 직원이 공지 작성 시도 → 서버가 무시(반영 안 됨)
    r = client.post("/sync", headers=_auth(nurse["access_token"]), json={
        "notices": [{"id": "n-bad", "title": "권한없는공지"}],
    })
    assert r.status_code == 200
    assert r.json()["notices"] == []


def test_staff_invite_scopes_to_inviter_tenant(client):
    a = _register_tenant(client, "조리원A", "ownerA")
    b = _register_tenant(client, "조리원B", "ownerB")
    inv_a = client.post("/admin/invite", headers=_auth(a["access_token"]),
                        json={"role": "cleaner"}).json()

    joined = client.post("/auth/register", json={
        "username": "cleaner1", "display_name": "환경", "password": "pw12345",
        "invite_code": inv_a["code"],
    }).json()
    # A 의 초대코드로 가입했으니 tenant_id 는 A 여야 한다 (B 아님)
    assert joined["tenant_id"] == a["tenant_id"]
    assert joined["tenant_id"] != b["tenant_id"]
