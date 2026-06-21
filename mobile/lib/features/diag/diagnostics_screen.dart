import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/session.dart';

/// 연결 진단 — curl 과 동일한 테스트를 앱이 직접 수행해 어디서 깨지는지 표시.
/// (토큰 배선 문제 vs 서버 문제 vs 네트워크 문제를 한 화면에서 구분)
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});
  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  final _user = TextEditingController();
  final _pw = TextEditingController();
  final List<String> _log = [];
  bool _busy = false;

  @override
  void dispose() {
    _user.dispose();
    _pw.dispose();
    super.dispose();
  }

  void _add(String s) => setState(() => _log.add(s));

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _log.clear();
    });
    final dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      validateStatus: (_) => true, // 모든 상태코드 받기(예외 대신 표시)
    ));

    _add('BASE_URL = ${AppConfig.apiBaseUrl}');

    // 현재 앱 세션/토큰 상태
    final session = ref.read(sessionProvider);
    final hasTok = ref.read(apiClientProvider).hasToken;
    _add('현재 세션: ${session == null ? "없음" : "있음(${session.displayName})"}');
    _add('앱 토큰 보유(hasToken): $hasTok, 길이=${session?.token.length ?? 0}');
    _add('─────────────');

    // 0) 현재 앱 세션 토큰으로 바로 /sync (아이디 입력 불필요 — 진짜 토큰 검증)
    final curTok = session?.token;
    if (curTok != null && curTok.isNotEmpty) {
      try {
        final s0 = await dio.get('/sync',
            options: Options(headers: {'Authorization': 'Bearer $curTok'}));
        _add('⓪ 현재토큰 /sync(GET) → ${s0.statusCode}');
        if (s0.statusCode != 200 && s0.data != null) _add('   ${s0.data}');
      } catch (e) {
        _add('⓪ 현재토큰 /sync 예외: $e');
      }
      _add('─────────────');
    }

    // 1) health
    try {
      final h = await dio.get('/health');
      _add('① /health → ${h.statusCode} ${h.data}');
    } catch (e) {
      _add('① /health 예외: $e');
    }

    // 2) login
    String? token;
    try {
      final r = await dio.post('/auth/login',
          data: {'username': _user.text.trim(), 'password': _pw.text},
          options: Options(contentType: Headers.formUrlEncodedContentType));
      _add('② /auth/login → ${r.statusCode}');
      if (r.data is Map) {
        token = (r.data as Map)['access_token']?.toString();
        _add('   access_token 길이 = ${token?.length ?? 0}');
        _add('   tenant_id = ${(r.data as Map)['tenant_id']}');
      } else {
        _add('   응답이 Map 아님: ${r.data.runtimeType} → ${r.data}');
      }
    } catch (e) {
      _add('② /auth/login 예외: $e');
    }

    // 3) sync with token
    if (token != null && token.isNotEmpty) {
      try {
        final s = await dio.post('/sync',
            data: <String, dynamic>{},
            options: Options(headers: {'Authorization': 'Bearer $token'}));
        _add('③ /sync(토큰) → ${s.statusCode}');
        if (s.statusCode != 200 && s.data != null) _add('   ${s.data}');
      } catch (e) {
        _add('③ /sync 예외: $e');
      }
    } else {
      _add('③ /sync 생략 (토큰 없음)');
    }

    _add('─────────────  완료');
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('연결 진단')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
                controller: _user,
                decoration: const InputDecoration(
                    labelText: '아이디', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(
                controller: _pw,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: '비밀번호', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _run,
              child: _busy
                  ? const SizedBox(
                      height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('진단 실행 (health → login → sync)'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Colors.black87,
                child: SingleChildScrollView(
                  child: SelectableText(
                    _log.isEmpty ? '진단을 실행하세요' : _log.join('\n'),
                    style: const TextStyle(
                        color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 13),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
