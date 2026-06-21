import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session.dart';
import '../../data/sync_service.dart';
import '../health/baby_list_screen.dart';
import '../notice/notice_screen.dart';
import '../routine/routine_screen.dart';

/// 바둑판 대시보드 — 큰 버튼 위주의 공용 태블릿 메인 화면.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // 진입 시 1회 자동 동기화 → 로그인 직후 남아있던 오류 배너 자동 정리.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncServiceProvider).syncNow();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final sync = ref.read(syncServiceProvider);
    if (session == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        title: Text(session.tenantName.isEmpty ? '산후조리원' : session.tenantName),
        actions: [
          IconButton(
            tooltip: '동기화',
            onPressed: () async {
              final ok = await sync.syncNow();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok ? '동기화 완료' : '동기화 실패: ${sync.lastError.value ?? ''}'),
                  backgroundColor: ok ? null : Colors.red,
                ));
              }
            },
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: '로그아웃',
            onPressed: () => ref.read(sessionProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          _AlertBanner(notifier: sync.alerts),
          _SyncErrorBanner(notifier: sync.lastError),
          _CurrentWorkerBar(session: session),
          Expanded(
            child: GridView.count(
              crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
              padding: const EdgeInsets.all(16),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              children: [
                _Tile(
                  icon: Icons.thermostat,
                  label: '신생아 건강기록',
                  color: const Color(0xFF4C8DFF),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const BabyListScreen())),
                ),
                _Tile(
                  icon: Icons.checklist,
                  label: '루틴 업무 체크',
                  color: const Color(0xFF2EB872),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const RoutineScreen())),
                ),
                _Tile(
                  icon: Icons.campaign,
                  label: '조리원 공지',
                  color: const Color(0xFF8E5BFF),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const NoticeScreen())),
                ),
                _Tile(
                  icon: Icons.switch_account,
                  label: '직원 전환(PIN)',
                  color: const Color(0xFFFFA000),
                  onTap: () => _showPinSwitch(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showPinSwitch(BuildContext context, WidgetRef ref) async {
  final pin = TextEditingController();
  String? error;
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('직원 전환'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pin,
              keyboardType: TextInputType.number,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'PIN 4자리', border: OutlineInputBorder()),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () async {
              try {
                final resp = await ref.read(apiClientProvider).pinLogin(pin.text.trim());
                await ref.read(sessionProvider.notifier).switchMember(resp);
                if (ctx.mounted) Navigator.pop(ctx);
              } on DioException {
                setState(() => error = '잘못된 PIN');
              }
            },
            child: const Text('전환'),
          ),
        ],
      ),
    ),
  );
  pin.dispose();
}

class _SyncErrorBanner extends StatelessWidget {
  const _SyncErrorBanner({required this.notifier});
  final ValueNotifier<String?> notifier;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: notifier,
      builder: (context, err, _) {
        if (err == null) return const SizedBox.shrink();
        return Material(
          color: Colors.orange.shade50,
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.cloud_off, color: Colors.orange),
            title: Text('동기화 안 됨 · $err',
                style: const TextStyle(color: Colors.deepOrange)),
          ),
        );
      },
    );
  }
}

class _CurrentWorkerBar extends StatelessWidget {
  const _CurrentWorkerBar({required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.person, size: 20),
          const SizedBox(width: 8),
          Text('현재 직원: ${session.displayName} (${session.role})',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  const _AlertBanner({required this.notifier});
  final ValueNotifier<List<Map<String, dynamic>>> notifier;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: notifier,
      builder: (context, alerts, _) {
        if (alerts.isEmpty) return const SizedBox.shrink();
        return Material(
          color: Colors.red.shade50,
          child: Column(
            children: [
              for (final a in alerts)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.warning, color: Colors.red),
                  title: Text(a['message']?.toString() ?? '알림',
                      style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: Colors.white),
            const SizedBox(height: 12),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
