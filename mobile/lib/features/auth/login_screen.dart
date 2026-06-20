import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/session.dart';
import '../../data/sync_service.dart';

/// 로그인 + 신규 조리원 개설. 공용 태블릿은 한 번 로그인하면 PIN 으로 전환.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _registerMode = false;
  bool _busy = false;
  String? _error;

  final _tenant = TextEditingController();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  final _pin = TextEditingController();

  @override
  void dispose() {
    for (final c in [_tenant, _username, _displayName, _password, _pin]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final resp = _registerMode
          ? await api.registerTenant(
              tenantName: _tenant.text.trim(),
              username: _username.text.trim(),
              displayName: _displayName.text.trim(),
              password: _password.text,
              pinCode: _pin.text.trim().isEmpty ? null : _pin.text.trim(),
            )
          : await api.login(_username.text.trim(), _password.text);
      await ref.read(sessionProvider.notifier).setFromResponse(resp);
      ref.read(syncServiceProvider).syncNow();
    } on DioException catch (e) {
      // 서버가 응답(4xx/5xx)을 준 경우엔 detail 을, 응답 자체가 없으면
      // (연결 실패/주소 오류/권한 없음) 원인 타입과 접속 주소를 노출해 진단을 돕는다.
      final data = e.response?.data;
      final serverMsg = data is Map ? data['detail']?.toString() : null;
      setState(() => _error = serverMsg ??
          '네트워크 오류 (${e.type.name})\n${e.message ?? ''}\n접속 주소: ${AppConfig.apiBaseUrl}');
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.child_care, size: 64, color: Color(0xFF4C8DFF)),
                const SizedBox(height: 12),
                Text(_registerMode ? '조리원 개설' : '로그인',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                if (_registerMode) ...[
                  _field(_tenant, '조리원 이름'),
                  _field(_displayName, '내 이름(원장)'),
                ],
                _field(_username, '사용자명(ID)'),
                _field(_password, '비밀번호', obscure: true),
                if (_registerMode) _field(_pin, '내 PIN(4자리, 선택)'),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_registerMode ? '개설하고 시작' : '로그인'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => setState(() {
                    _registerMode = !_registerMode;
                    _error = null;
                  }),
                  child: Text(_registerMode ? '이미 계정이 있어요 — 로그인' : '신규 조리원 개설'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {bool obscure = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(
          controller: c,
          obscureText: obscure,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
      );
}
