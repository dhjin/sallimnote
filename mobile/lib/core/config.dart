/// 앱 전역 설정.
class AppConfig {
  /// 백엔드(FastAPI) 베이스 URL.
  /// 개발: 에뮬레이터에서 호스트 접근 시 10.0.2.2(Android) 사용.
  /// 운영: NodePort(30881) 또는 인그레스 도메인으로 교체.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://sallimnote.thechurch-plus.org',
  );

  /// 체온 알림 기본 임계치(서버 tenant.temp_threshold 와 동기화 전 로컬 기본값).
  static const double defaultTempThreshold = 37.5;
}
