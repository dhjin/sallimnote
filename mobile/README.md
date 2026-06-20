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

## ⚠️ 트러블슈팅 — "네트워크 오류" / 조리원 개설 실패

응답을 못 받았다는 뜻(요청이 서버에 도달 못 함). 순서대로 확인:

1. **릴리스 APK 인터넷 권한 누락 (가장 흔함).**
   Flutter 는 `INTERNET` 권한을 debug 매니페스트에만 자동 추가한다. `flutter build apk`
   (release)는 권한이 없어 모든 네트워크 호출이 실패한다.
   `android/app/src/main/AndroidManifest.xml` 의 `<manifest>` 바로 아래에 추가:
   ```xml
   <uses-permission android:name="android.permission.INTERNET"/>
   ```
2. **API 주소.** 기본값은 `https://sallimnote.thechurch-plus.org`. 다른 서버면:
   ```bash
   flutter build apk --dart-define=API_BASE_URL=https://<도메인>
   ```
   화면의 에러 메시지에 실제 접속 주소와 원인(connectionError/timeout 등)이 표시된다.
3. **HTTP(평문) 주소를 쓸 경우** Android 가 기본 차단한다. 운영은 https 를 쓸 것.
   불가피하게 http 면 `network_security_config` 설정 필요.
4. **서버 자체 확인:** `curl -i https://<도메인>/health` 가 200 인지 먼저 점검.

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
