# 산후조리원 관리 앱 (Flutter) — Phase 1 오프라인 코어

공용 태블릿용 오프라인 우선 클라이언트. 신뢰원본은 서버(FastAPI+PostgreSQL),
단말 SQLite 는 오프라인 입력 버퍼.

## 부트스트랩

이 디렉터리에는 **Dart 소스(`lib/`)와 `pubspec.yaml` 만** 들어있다.
플랫폼 폴더(`android/`, `ios/`)와 진입 설정은 Flutter SDK 로 생성한다:

```bash
cd mobile
flutter create .            # android/ios/ 등 플랫폼 스캐폴드 생성 (lib/ 는 보존됨)
flutter pub get
flutter analyze             # 정적 분석 (이 저장소엔 Flutter SDK 미포함이라 미검증)
flutter run --dart-define=API_BASE_URL=http://<백엔드주소>:30881
```

> 이 환경에는 Flutter SDK 가 없어 컴파일/분석을 수행하지 못했다.
> 최초 실행 시 `flutter analyze` 로 검증 후 진행할 것.

## 아키텍처

```
lib/
  core/
    config.dart        # API_BASE_URL 등 설정 (--dart-define 로 주입)
    api_client.dart    # dio — auth / sync 호출
    local_db.dart      # sqflite 스키마(서버와 동일 컬럼 + is_synced)
    session.dart       # 세션/자동로그인 (Riverpod + SharedPreferences)
  models/models.dart   # Room/Baby/HealthLog/RoutineTask (+toSyncJson)
  data/
    local_repo.dart    # 로컬 CRUD — 모든 쓰기 is_synced=0
    sync_service.dart  # 연결 감지 → is_synced=0 업로드 → 서버상태 병합
    providers.dart     # Riverpod FutureProvider 목록
  features/
    auth/login_screen.dart        # 로그인 / 조리원 개설
    dashboard/dashboard_screen.dart  # 바둑판 대시보드 + PIN 전환 + 알림배너
    health/baby_list_screen.dart, health_log_screen.dart
    routine/routine_screen.dart
```

## 오프라인 동기화 흐름 (Phase 2 와 연동)

1. 입력 → 로컬 SQLite `is_synced=0` 즉시 저장(오프라인에서도 동작).
2. `connectivity_plus` 가 네트워크 복귀 감지 → `SyncService.syncNow()`.
3. `is_synced=0` 레코드를 `POST /sync` 배치 업로드(서버가 tenant_id 강제 주입).
4. 성공 시 `is_synced=1`, 서버 응답 전체 상태를 로컬 병합.
5. 응답 `alerts`(체온 임계치 등)는 대시보드 상단 배너로 표시(Phase 3 에서 FCM 으로 확장).

## 공용 태블릿 빠른 전환(PIN)

태블릿은 테넌트 토큰을 유지하고, 대시보드의 **직원 전환(PIN)** 으로
`POST /auth/pin-login` 호출 → 같은 조리원 내 직원 세션만 교체(비밀번호 재입력 불필요).

## 미구현(다음 단계)

- Phase 2: 양방향 delta pull(`?since=`) 주기 동기화, 충돌 UI.
- Phase 3: FCM 토큰 등록/수신, 관리자 모바일 전용 뷰.
- Phase 4: `in_app_purchase` + plan 게이팅.
- 위젯/통합 테스트.
