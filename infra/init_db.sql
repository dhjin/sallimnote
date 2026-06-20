-- ============================================================================
-- 산후조리원 관리 시스템 — PostgreSQL 초기화 스크립트
-- ----------------------------------------------------------------------------
-- 실행: postgres 슈퍼유저로
--   psql -U postgres -h <DB_HOST> -f init_db.sql
--
-- ⚠️ 실행 전 아래 'CHANGE_ME' 를 강력한 비밀번호로 교체할 것.
--    (생성 예: openssl rand -base64 24)
--
-- 멀티테넌트는 tenant_id 행 단위 격리이므로 DB 는 1개만 있으면 된다.
-- 테이블은 앱이 Alembic(운영) 또는 create_all(개발) 로 생성하므로
-- 이 스크립트는 "DB + 롤 + 권한"까지만 준비한다.
-- ============================================================================

-- 1) 애플리케이션 롤 (없을 때만 생성 — 재실행 안전)
DO $$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'sallimnote') THEN
      CREATE ROLE sallimnote WITH LOGIN PASSWORD 'CHANGE_ME';
   END IF;
END
$$;

-- 2) 데이터베이스 (없을 때만 생성 — CREATE DATABASE 는 트랜잭션 밖에서 실행)
SELECT 'CREATE DATABASE sallimnote OWNER sallimnote ENCODING ''UTF8'''
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'sallimnote')\gexec

-- 3) public 스키마 권한 (PG15+ 는 기본 제한적 — create_all/Alembic 이
--    테이블을 만들 수 있도록 명시 부여)
\connect sallimnote
GRANT ALL ON SCHEMA public TO sallimnote;
ALTER SCHEMA public OWNER TO sallimnote;

-- 확인: \du (롤), \l (DB), 배포 후 \dt (테이블 7개)
