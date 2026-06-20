import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/session.dart';
import 'data/sync_service.dart';
import 'features/auth/login_screen.dart';
import 'features/dashboard/dashboard_screen.dart';

void main() {
  runApp(const ProviderScope(child: PostpartumCareApp()));
}

class PostpartumCareApp extends ConsumerStatefulWidget {
  const PostpartumCareApp({super.key});
  @override
  ConsumerState<PostpartumCareApp> createState() => _AppState();
}

class _AppState extends ConsumerState<PostpartumCareApp> {
  @override
  void initState() {
    super.initState();
    // 자동 로그인 복원 + 자동 동기화 시작.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(sessionProvider.notifier).restore();
      ref.read(syncServiceProvider).startAutoSync();
      if (ref.read(sessionProvider) != null) {
        ref.read(syncServiceProvider).syncNow();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    return MaterialApp(
      title: '산후조리원 관리',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4C8DFF),
        useMaterial3: true,
        // 공용 태블릿 — 큰 터치 타깃.
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 56),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      home: session == null ? const LoginScreen() : const DashboardScreen(),
    );
  }
}
