import 'package:dio/dio.dart';

import 'config.dart';

/// FastAPI 백엔드 통신. 토큰은 Session 에서 주입한다.
class ApiClient {
  final Dio _dio;
  String? _token;

  ApiClient()
      : _dio = Dio(BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
        ));

  void setToken(String? token) => _token = token;

  Options get _auth => Options(headers: {
        if (_token != null) 'Authorization': 'Bearer $_token',
      });

  // ── Auth ───────────────────────────────────────────────────────────────

  /// 조리원 개설 + owner 계정. 토큰 응답 반환.
  Future<Map<String, dynamic>> registerTenant({
    required String tenantName,
    required String username,
    required String displayName,
    required String password,
    String? pinCode,
  }) async {
    final r = await _dio.post('/auth/register-tenant', data: {
      'tenant_name': tenantName,
      'username': username,
      'display_name': displayName,
      'password': password,
      'pin_code': pinCode,
    });
    return Map<String, dynamic>.from(r.data);
  }

  /// username/password 로그인 (FastAPI OAuth2 form).
  Future<Map<String, dynamic>> login(String username, String password,
      {String? tenantId}) async {
    final r = await _dio.post(
      '/auth/login',
      data: {
        'username': username,
        'password': password,
        if (tenantId != null) 'client_id': tenantId,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    return Map<String, dynamic>.from(r.data);
  }

  /// 공용 태블릿 PIN 빠른 전환 (현재 테넌트 토큰 필요).
  Future<Map<String, dynamic>> pinLogin(String pinCode) async {
    final r = await _dio.post('/auth/pin-login',
        data: {'pin_code': pinCode}, options: _auth);
    return Map<String, dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> me() async {
    final r = await _dio.get('/auth/me', options: _auth);
    return Map<String, dynamic>.from(r.data);
  }

  // ── Sync ───────────────────────────────────────────────────────────────

  /// 로컬 미동기화 변경분 업로드 + 서버 상태/알림 수신.
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload,
      {String? since}) async {
    final r = await _dio.post('/sync',
        data: payload,
        queryParameters: since != null ? {'since': since} : null,
        options: _auth);
    return Map<String, dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> pull({String? since}) async {
    final r = await _dio.get('/sync',
        queryParameters: since != null ? {'since': since} : null,
        options: _auth);
    return Map<String, dynamic>.from(r.data);
  }
}
