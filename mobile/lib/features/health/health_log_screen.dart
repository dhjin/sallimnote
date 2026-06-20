import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/config.dart';
import '../../core/session.dart';
import '../../data/providers.dart';
import '../../data/sync_service.dart';
import '../../models/models.dart';

/// 특정 신생아의 건강 로그 조회 + 빠른 기록(체온/수유량).
class HealthLogScreen extends ConsumerWidget {
  const HealthLogScreen({super.key, required this.baby});
  final Baby baby;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(logsForBabyProvider(baby.id));
    final fmt = DateFormat('MM/dd HH:mm');
    return Scaffold(
      appBar: AppBar(title: Text('${baby.name} 건강기록')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addLog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('기록 추가'),
      ),
      body: logs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (list) {
          if (list.isEmpty) return const Center(child: Text('기록이 없습니다'));
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final l = list[i];
              final hot = (l.temperature ?? 0) >= AppConfig.defaultTempThreshold;
              final ts = DateTime.tryParse(l.timestamp);
              return ListTile(
                leading: Icon(Icons.thermostat,
                    color: hot ? Colors.red : Colors.blueGrey),
                title: Text([
                  if (l.temperature != null) '체온 ${l.temperature}℃',
                  if (l.feedingMl != null) '수유 ${l.feedingMl}ml',
                ].join('  ·  ')),
                subtitle: Text([
                  if (ts != null) fmt.format(ts),
                  if (l.memo.isNotEmpty) l.memo,
                ].join('  ')),
                trailing: l.isSynced == 0
                    ? const Icon(Icons.cloud_off, size: 18, color: Colors.grey)
                    : const Icon(Icons.cloud_done, size: 18, color: Colors.green),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _addLog(BuildContext context, WidgetRef ref) async {
    final temp = TextEditingController();
    final feed = TextEditingController();
    final memo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('건강 기록'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: temp,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: '체온(℃)', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(
                controller: feed,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: '수유량(ml)', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(
                controller: memo,
                decoration: const InputDecoration(
                    labelText: '특이사항', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('저장')),
        ],
      ),
    );
    if (ok == true) {
      final session = ref.read(sessionProvider);
      await ref.read(localRepoProvider).insertLog(HealthLog(
            id: const Uuid().v4(),
            babyId: baby.id,
            temperature: double.tryParse(temp.text.trim()),
            feedingMl: int.tryParse(feed.text.trim()),
            memo: memo.text.trim(),
            timestamp: DateTime.now().toIso8601String(),
            workerId: session?.memberId,
          ));
      ref.invalidate(logsForBabyProvider(baby.id));
      ref.read(syncServiceProvider).syncNow();
    }
    temp.dispose();
    feed.dispose();
    memo.dispose();
  }
}
