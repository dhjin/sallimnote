# DB 인프라 셋업 가이드 (전용 서버)

산후조리원 관리 시스템의 데이터 계층은 **PostgreSQL 단일 인스턴스**다.
멀티테넌트는 `tenant_id` 행 단위 격리라 조리원마다 DB/스키마를 나눌 필요가 없다.

## 0. 요구사항
- PostgreSQL **15 또는 16** (12+ 동작), 인코딩 **UTF-8**
- 앱(k8s)에서 DB 서버 **5432** 포트 접근 가능
- 앱 시간값은 UTC 기준이라 서버 타임존 무관

## 1. DB · 롤 생성
```bash
# 1) 비밀번호 정하기
openssl rand -base64 24

# 2) init_db.sql 의 CHANGE_ME 를 위 비밀번호로 교체 후 실행
psql -U postgres -h <DB_HOST> -f init_db.sql
```
생성 결과: 롤 `sallimnote`, DB `sallimnote`(owner=sallimnote), public 스키마 권한.

## 2. 원격 접속 허용 (앱과 DB 가 다른 호스트일 때)
`postgresql.conf`:
```
listen_addresses = '*'
password_encryption = scram-sha-256
```
`pg_hba.conf` (앱 네트워크/Pod CIDR 만 허용):
```
host  sallimnote  sallimnote  <K8S_NODE_OR_POD_CIDR>/24  scram-sha-256
```
- 방화벽 5432 개방(가능하면 클러스터 IP 로 제한)
- 별도 서버면 SSL 권장 → 접속 URL 에 `?sslmode=require`
- 변경 후 `systemctl reload postgresql` (또는 `SELECT pg_reload_conf();`)

## 3. 접속 URL 구성
```
postgresql://sallimnote:<비밀번호>@<DB_HOST>:5432/sallimnote
```
> URL 특수문자는 인코딩 필요: `!`→`%21`, `@`→`%40`, `:`→`%3A`, `/`→`%2F`

## 4. 스키마 생성 (테이블 만들기)

### 운영: Alembic 마이그레이션 (권장)
```bash
cd backend
pip install -r requirements.txt
export DATABASE_URL='postgresql://sallimnote:<비밀번호>@<DB_HOST>:5432/sallimnote'
alembic upgrade head
```
이후 스키마 변경 시: 모델 수정 → `alembic revision --autogenerate -m "설명"` → 검토 → `alembic upgrade head`.

> 앱은 sqlite(개발/테스트)에서는 `create_all` 로 자동 생성하지만,
> **PostgreSQL 에서는 create_all 을 호출하지 않으므로 반드시 `alembic upgrade head` 를 먼저 실행**해야 한다.

## 5. k8s 시크릿 주입
`backend/k8s.yaml` 의 Deployment 는 `sallimnote-pg-secret` 의 `DATABASE_URL` 키를 참조한다.
```bash
kubectl create secret generic sallimnote-pg-secret \
  --from-literal=DATABASE_URL='postgresql://sallimnote:<비밀번호>@<DB_HOST>:5432/sallimnote'

# JWT_SECRET 도 placeholder 교체 권장
kubectl create secret generic sallimnote-secret \
  --from-literal=JWT_SECRET="$(openssl rand -hex 32)" \
  --from-literal=CORS_ORIGINS='https://<운영_프론트_도메인>'
```

## 6. 검증
```bash
psql "$DATABASE_URL" -c '\dt'
# tenants, members, tenant_invites, rooms, babies,
# neonatal_health_log, routine_tasks  (7개)

curl http://<서비스주소>:30881/health   # {"status":"ok",...}
```

## 7. 운영 권장
- **백업**: `pg_dump` 정기 크론 또는 WAL 아카이빙 (PVC 만으론 부족)
- **JWT_SECRET / CORS_ORIGINS**: placeholder → 운영값
- 모니터링: 연결 수 / 디스크 / 슬로우쿼리
