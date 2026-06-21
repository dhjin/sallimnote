import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'local_db.dart';

/// 현재 로그인 세션. 공용 태블릿은 tenant 토큰을 유지하고,
/// 화면 내에서 PIN 으로 member 만 전환한다.
class Session {
  final String token;
  final String memberId;
  final String displayName;
  final String role;
  final String tenantId;
  final String tenantName;

  const Session({
    required this.token,
    required this.memberId,
    required this.displayName,
    required this.role,
    required this.tenantId,
    required this.tenantName,
  });

  factory Session.fromTokenResponse(Map<String, dynamic> m) => Session(
        token: m['access_token'] as String,
        memberId: m['member_id'] as String,
        displayName: m['display_name'] as String,
        role: m['role'] as String,
        tenantId: m['tenant_id'] as String,
        tenantName: m['tenant_name'] as String? ?? '',
      );

  bool get isAdmin => role == 'owner' || role == 'admin';
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// 세션 상태 + 영속화(자동 로그인).
class SessionNotifier extends StateNotifier<Session?> {
  SessionNotifier(this._ref) : super(null);
  final Ref _ref;

  static const _kToken = 'session_token';
  static const _kMember = 'session_member';
  static const _kName = 'session_name';
  static const _kRole = 'session_role';
  static const _kTenant = 'session_tenant';
  static const _kTenantName = 'session_tenant_name';

  Future<void> restore() async {
    final sp = await SharedPreferences.getInstance();
    final token = sp.getString(_kToken);
    // 빈/누락 토큰은 세션으로 인정하지 않는다(로그인 화면으로 유도).
    if (token == null || token.isEmpty) return;
    final s = Session(
      token: token,
      memberId: sp.getString(_kMember) ?? '',
      displayName: sp.getString(_kName) ?? '',
      role: sp.getString(_kRole) ?? 'nurse',
      tenantId: sp.getString(_kTenant) ?? '',
      tenantName: sp.getString(_kTenantName) ?? '',
    );
    _apply(s);
  }

  void _apply(Session s) {
    _ref.read(apiClientProvider).setToken(s.token);
    state = s;
  }

  Future<void> _persist(Session s) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kToken, s.token);
    await sp.setString(_kMember, s.memberId);
    await sp.setString(_kName, s.displayName);
    await sp.setString(_kRole, s.role);
    await sp.setString(_kTenant, s.tenantId);
    await sp.setString(_kTenantName, s.tenantName);
  }

  /// 로그인/개설 성공 응답 적용.
  Future<void> setFromResponse(Map<String, dynamic> resp) async {
    final s = Session.fromTokenResponse(resp);
    // 토큰이 비어 있으면(비정상 응답) 빈 세션을 저장하지 않고 실패 처리.
    if (s.token.isEmpty) {
      throw Exception('로그인 응답에 토큰이 없습니다');
    }
    _apply(s);
    await _persist(s);
  }

  /// PIN 전환 — 같은 테넌트 내 member 만 교체.
  Future<void> switchMember(Map<String, dynamic> resp) async {
    final s = Session.fromTokenResponse(resp);
    _apply(s);
    await _persist(s);
  }

  Future<void> logout() async {
    final sp = await SharedPreferences.getInstance();
    await sp.clear();
    _ref.read(apiClientProvider).setToken(null);
    await LocalDb.instance.clearAll();
    state = null;
  }
}

final sessionProvider =
    StateNotifierProvider<SessionNotifier, Session?>((ref) => SessionNotifier(ref));
