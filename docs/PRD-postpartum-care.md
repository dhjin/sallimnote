# 📋 프로젝트 명세서 — 산후조리원 멀티테넌트 업무 관리 솔루션

> 본 문서는 **현재 저장소(`dhjin/sallimnote`)의 실제 코드베이스**를 기반으로,
> "산후조리원 멀티테넌트 SaaS"로의 전환을 위한 **현실 반영 PRD + 기술 명세서**다.
> 코딩 에이전트는 이 문서를 그대로 읽고 작업을 시작할 수 있다.

---

## 0. 현황 분석 (As-Is) — 반드시 먼저 읽을 것

이 저장소는 원래 **"살림노트"라는 부부 가계부 PWA**다. 외부 기획서(Flutter+SQLite+Firebase 신규 앱)와
실제 코드가 **충돌**하므로, 사용자와 합의한 **하이브리드 방향**을 기준으로 한다.

| 영역 | 실제 현황 | 비고 |
|---|---|---|
| 백엔드 | **FastAPI + PostgreSQL** (`backend/main.py`, `models.py`, `auth.py`) | SQLite/Firebase 아님 |
| 인증 | JWT (HS256, 30일), bcrypt, `OAuth2PasswordBearer` (`backend/auth.py`) | **재사용** |
| 권한 | `role = admin | member`, 가족 초대코드(`FamilyInvite`) | 멀티테넌트로 **확장** |
| 동기화 | `POST /sync` 풀 업서트(last-write-wins) + `GET /sync` 전체 상태 | **재사용/확장** |
| 도메인 | 가계부(예산/고정지출/투자/적금/할일/일정) | **산후조리원 도메인으로 교체** |
| 프론트엔드 | `frontend/dist/`에 **빌드 산출물만** 존재 (소스 없음) | 클라이언트는 **신규 작성** 불가피 |
| 배포 | k3s + Longhorn PVC + NodePort 30881, 사설 레지스트리 (`backend/k8s.yaml`) | **재사용** |

### 핵심 결정 (사용자 합의됨)
1. **기술 스택 = 하이브리드.** 백엔드는 FastAPI+PostgreSQL 유지(멀티테넌트로 전환).
   클라이언트는 **Flutter**(태블릿+모바일)로 신규 작성, 오프라인 캐시 + FCM 푸시.
2. **산출 순서 = 본 PRD 문서 먼저** → 합의 → 코딩.

> ⚠️ 외부 기획서의 "단일 기기 SQLite + Firebase per-device" 모델은 **멀티테넌트 SaaS와 상충**한다.
> 멀티테넌트의 신뢰원본(source of truth)은 **서버(PostgreSQL)**이고, 단말 SQLite는 **오프라인 캐시**역할만 한다.

---

## 1. 프로젝트 개요 (Overview)

* **목적:** 산후조리원 현장 직원의 업무 누락 방지 + 관리자(원장)의 실시간 원격 모니터링.
* **멀티테넌트:** 하나의 서버/DB 인스턴스로 **여러 산후조리원(=테넌트)**을 격리 수용한다.
* **타겟 디바이스:**
  * 현장 직원: 공용 태블릿 — 가로/세로, 큰 버튼, PIN 빠른 전환, 오프라인 입력 중심.
  * 관리자: 개인 스마트폰 — 세로, 예외상황 알림 + 요약 대시보드, FCM 푸시.
* **비즈니스 모델:** Freemium (테넌트 단위 구독)
  * **Free:** 단일 조리원, 단일 태블릿, 클라우드 백업 제한.
  * **Premium(IAP/구독):** 다기기 동기화, 관리자 앱 연동, FCM 알림, 데이터 보관 연장.

---

## 2. 기술 스택 (Tech Stack) — 하이브리드 확정본

| 레이어 | 채택 | 근거 |
|---|---|---|
| 백엔드 API | **FastAPI** (기존 유지) | 이미 인증/동기화 구현됨 |
| 주 DB(서버) | **PostgreSQL** (기존 유지) | 멀티테넌트 격리·집계·임계치 트리거에 적합 |
| 클라이언트 | **Flutter** (Android/iOS 단일 코드베이스) | 태블릿+모바일 네이티브 |
| 로컬 캐시(단말) | **sqflite (SQLite)** | 오프라인 입력 버퍼 (신뢰원본 아님) |
| 상태관리 | **Riverpod** | |
| 푸시 | **FCM (HTTP v1 API)** | 임계치 알림 발송 — Cloud Functions 대신 **FastAPI에서 발송** |
| 백업 동기화 | 기존 `/sync` 확장 (테넌트 스코프 delta sync) | |
| 결제 | `in_app_purchase` (App Store / Play) + 서버 영수증 검증 | |
| 배포 | k3s + Longhorn + NodePort (기존 `k8s.yaml`) | |

> Firebase는 **FCM(푸시)만** 사용한다. Firestore/RTDB/Cloud Functions는 **사용하지 않는다**(서버가 PostgreSQL이므로).

---

## 3. 멀티테넌시 아키텍처 (Multi-Tenancy) — 가장 중요

### 3.1 격리 모델: 공유 DB + `tenant_id` 행 단위 격리
* 단일 PostgreSQL, 모든 도메인 테이블에 `tenant_id`(FK→`tenants.id`) 컬럼 추가.
* **모든 쿼리는 현재 토큰의 `tenant_id`로 강제 필터링**한다(누수 방지가 1순위 보안 요건).
* 구현: FastAPI 의존성 `get_tenant_scope()`가 JWT의 `tid`를 추출 → 모든 Repository에 주입.

```python
# auth.py 확장 예시
def create_token(member_id, username, role, tenant_id):  # tid 추가
    data = {"sub": member_id, "username": username, "role": role,
            "tid": tenant_id, "exp": expire}
    ...

def get_tenant_scope(payload: dict = Depends(get_current_member)) -> str:
    tid = payload.get("tid")
    if not tid:
        raise HTTPException(403, "No tenant scope")
    return tid
```

> 누락 방지 규칙: 도메인 테이블 조회 시 `tenant_id == scope`를 **항상** WHERE에 포함.
> 가능하면 PostgreSQL **Row-Level Security(RLS)**를 2차 방어선으로 추가 검토(Phase 2).

### 3.2 가입/온보딩 흐름 (기존 invite 구조 확장)
1. **원장(owner) 가입:** 신규 테넌트 생성 + owner 계정 생성.
   * 기존 `ADMIN_INIT_CODE` 단일 전역 코드 → **테넌트 생성용 가입 흐름**으로 대체.
2. **직원 가입:** owner/admin이 발급한 **테넌트 초대코드**(`TenantInvite`, 기존 `FamilyInvite` 확장)로 가입 → 동일 `tenant_id` 부여.
3. **공용 태블릿 빠른 전환:** 태블릿은 테넌트 단위 디바이스 토큰으로 로그인하고,
   화면 내에서 직원이 **4자리 PIN(`pin_code`)**으로 세션 사용자만 전환(매번 비번 입력 불필요).

### 3.3 역할(Role) 재정의
| role | 권한 |
|---|---|
| `owner` | 테넌트 소유자(결제·직원관리·전체조회) |
| `admin` | 관리자(모니터링·알림수신·직원관리) |
| `nurse` | 간호/조리 직원(건강로그·수유 기록) |
| `cleaner` | 환경 직원(루틴업무 체크) |

---

## 4. 데이터베이스 스키마 (To-Be, PostgreSQL)

> 기존 가계부 테이블(`monthly_budgets`, `fixed_expenses`, `investments`,
> `installment_savings`, `todos`, `schedules`)은 **도메인 테이블로 교체**한다.
> 신규 빈 DB 가정(운영 데이터 없음, 커밋이 "extracted from containers" 초기상태)이므로
> 파괴적 마이그레이션 허용. 운영 데이터가 있으면 Alembic 마이그레이션 별도 수립.

### 4.1 `tenants` (조리원, 신규)
| 필드 | 타입 | 설명 |
|---|---|---|
| id | String(PK, uuid) | 테넌트 ID |
| name | String | 조리원 이름 |
| plan | String | `free` \| `premium` |
| plan_expires_at | DateTime? | 구독 만료 |
| temp_threshold | Float | 체온 알림 임계치(기본 37.5) |
| created_at | DateTime | |

### 4.2 `members` (직원, 기존 확장)
기존 컬럼 + **추가**: `tenant_id`(FK), `pin_code`(4자리), `role`(owner/admin/nurse/cleaner).

### 4.3 `tenant_invites` (기존 `FamilyInvite` 확장)
기존 컬럼 + `tenant_id`, `role`(초대 시 부여할 역할), `expires_at`.

### 4.4 `rooms` (구역/방, 신규)
| 필드 | 타입 | 설명 |
|---|---|---|
| id | String(PK) | |
| tenant_id | String(FK) | |
| name | String | 방/구역명 |

### 4.5 `babies` (신생아, 신규)
| 필드 | 타입 | 설명 |
|---|---|---|
| id | String(PK, uuid) | 신생아 ID |
| tenant_id | String(FK) | |
| name | String | 식별명(예: 아기이름/산모성+호실) |
| room_id | String(FK→rooms)? | 배정 구역 |
| birth_date | Date? | |
| guardian_name | String | 보호자(산모) |
| is_active | Boolean | 재원 여부 |
| created_at / updated_at / deleted | | 동기화 메타 |

### 4.6 `neonatal_health_log` (신생아 건강 로그, 신규)
| 필드 | 타입 | 설명 |
|---|---|---|
| id | String(PK, uuid) | |
| tenant_id | String(FK) | |
| baby_id | String(FK→babies) | |
| temperature | Float | 체온 — `>= tenants.temp_threshold` 시 알림 트리거 |
| feeding_ml | Integer | 수유량 |
| memo | Text | 특이사항 |
| timestamp | DateTime | 기록 시각 |
| worker_id | String(FK→members) | 기록자 |
| created_at / updated_at | | |
| is_synced | Integer | **클라이언트 SQLite 전용** 컬럼(서버엔 불필요) |

### 4.7 `routine_tasks` (루틴 업무 체크, 신규)
| 필드 | 타입 | 설명 |
|---|---|---|
| id | String(PK, uuid) | |
| tenant_id | String(FK) | |
| room_id | String(FK→rooms)? | 구역 |
| task_name | String | 업무명(소독/환기 등) |
| scheduled_time | DateTime | 예정 시각 |
| completed_time | DateTime? | 실제 완료(Null=미완료) |
| completed_by | String(FK→members)? | 완료자 |
| created_at / updated_at / deleted | | |
| is_synced | Integer | **클라이언트 SQLite 전용** |

> **서버 vs 단말 컬럼 구분:** `is_synced`는 단말 SQLite에서 미전송 표시용. 서버 PostgreSQL은
> `updated_at` 기반 delta로 충분하므로 `is_synced`를 저장하지 않는다.

---

## 5. 동기화 로직 (Offline-First, 테넌트 스코프)

신뢰원본은 **서버**. 단말 SQLite는 오프라인 입력 버퍼.

1. 직원이 태블릿에서 입력 → 즉시 로컬 SQLite Insert/Update, `is_synced = 0`.
2. 백그라운드 워커가 `connectivity_plus`로 네트워크 감지.
3. 연결 시 `is_synced = 0` 레코드를 **테넌트 토큰**과 함께 `POST /sync` 배치 업로드.
4. 서버는 `tenant_id` 강제 주입 + last-write-wins(`updated_at`) 업서트 → 성공 시 단말이 `is_synced = 1`.
5. 서버는 임계치(체온 ≥ `temp_threshold`) 위반 로그 감지 시 해당 테넌트의 admin/owner에게 **FCM 발송**
   (기존 `/sync` 업서트 핸들러 내부에서 검사 — Cloud Functions 불필요).
6. 다기기 일관성: `GET /sync?since=<updated_at>` delta pull로 다른 기기 변경분 수신.

> 기존 `backend/main.py`의 `upsert()` / `_full_state()`를 **테넌트 필터 + 신규 모델**로 교체/확장한다.

---

## 6. 푸시 알림 (FCM, 서버 발송)

* 단말은 FCM 토큰을 `POST /devices`로 등록(테넌트·멤버 스코프).
* 트리거 조건(설정 가능): 체온 ≥ 임계치, 수유 누락(예정 대비 미기록), 루틴업무 시간 초과.
* 발송 주체: **FastAPI** (FCM HTTP v1 API + 서비스계정). 대상: 해당 테넌트의 `admin`/`owner` 디바이스 토큰.
* 페이로드: `{ tenant_id, type, baby_id/room_id, severity, message }` (딥링크용 식별자 포함).

---

## 7. 인앱 결제 / 권한 게이팅 (Freemium)

* 결제 단위 = **테넌트**(원장이 구독). `tenants.plan` 으로 기능 게이팅.
* Free: 단일 태블릿 + 로컬 위주, 백업/관리자앱/FCM 제한.
* Premium: 다기기 동기화·관리자 앱·FCM 알림·보관 연장 해제.
* 서버에서 영수증 검증 후 `plan`/`plan_expires_at` 갱신. 클라이언트는 서버 plan 값을 신뢰.

---

## 8. 개발 마일스톤 (하이브리드 현실 반영)

### Phase 0 — 백엔드 멀티테넌트 전환 (서버 기반 공사) ⭐ 최우선
* `tenants`, `tenant_invites` 추가, `members`에 `tenant_id`/`pin_code`/role 확장.
* JWT에 `tid` 포함, `get_tenant_scope` 의존성, 모든 라우트 테넌트 강제 필터.
* 가계부 모델 제거 → `rooms`/`babies`/`neonatal_health_log`/`routine_tasks` 추가.
* `/sync`(GET/POST) 테넌트 스코프 + 신규 모델로 재작성, delta(`since`) 지원.
* **DoD:** 두 테넌트 데이터가 서로 절대 보이지 않음을 자동 테스트로 증명(격리 테스트).

### Phase 1 — Flutter 공용 태블릿 앱 (오프라인 코어)
* 바둑판 대시보드, 큰 버튼 터치 UI(가로/세로).
* PIN 기반 빠른 직원 전환(세션), sqflite 로컬 CRUD(`is_synced=0`).
* 신생아 건강 로그 + 루틴 체크리스트 입력. (서버 없이도 동작)

### Phase 2 — 동기화/백업 모듈 (프리미엄 토대)
* `connectivity_plus` 네트워크 감지 + 배치 업로드 워커.
* `/sync` 양방향(업로드 + `since` delta pull), 충돌 last-write-wins.
* **DoD:** 비행기모드 입력 → 복귀 시 자동 동기화 + 다른 기기 반영.

### Phase 3 — 관리자 모바일 앱 + 푸시
* 예외 중심 알림 뷰 + 요약 대시보드(세로).
* 서버 임계치 감지 → FCM 발송, 단말 디바이스 토큰 등록.
* **DoD:** 체온 37.5 입력 → 관리자 폰 푸시 수신.

### Phase 4 — IAP + 권한 분리
* `in_app_purchase` 연동 + 서버 영수증 검증.
* `tenants.plan` 기반 Free/Premium 기능 락 해제.

---

## 9. 보안·운영 체크리스트

* [ ] 모든 도메인 쿼리 `tenant_id` 필터(테넌트 누수 0) — 테스트로 강제.
* [ ] `JWT_SECRET`/`ADMIN_INIT_CODE`는 k8s Secret로만 주입(`k8s.yaml`), 코드 하드코딩 금지.
* [ ] CORS `allow_origins=["*"]` → 운영 도메인으로 제한.
* [ ] PIN은 평문 저장 금지(해시 또는 테넌트 스코프 내 제한적 사용 + rate-limit).
* [ ] FCM 서비스계정 키는 Secret 주입.
* [ ] (검토) PostgreSQL RLS 2차 방어선.

---

## 10. 코딩 에이전트 첫 작업 프롬프트 (Phase 0)

> "위 PRD의 **Phase 0**부터 시작한다. `backend/models.py`에 `Tenant`, `Room`, `Baby`,
> `NeonatalHealthLog`, `RoutineTask` 모델을 추가하고 `Member`에 `tenant_id`/`pin_code`/role을
> 확장하라. 기존 가계부 모델(MonthlyBudget/FixedExpense/Investment/InstallmentSavings/
> TodoItem/Schedule)은 제거한다. `auth.py`의 `create_token`에 `tid`를 추가하고
> `get_tenant_scope` 의존성을 만들어라. `main.py`의 가입/로그인/`/sync`를 테넌트 스코프로
> 재작성하고, **서로 다른 두 테넌트의 데이터가 교차 조회되지 않음**을 검증하는 pytest
> 격리 테스트를 추가하라. PostgreSQL과 FastAPI 기존 구조를 유지한다."
