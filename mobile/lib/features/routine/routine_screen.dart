import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/session.dart';
import '../../data/local_repo.dart';
import '../../data/providers.dart';
import '../../data/sync_service.dart';
import '../../models/models.dart';

/// 루틴 업무 체크리스트 — 큰 체크박스로 완료 토글.
class RoutineScreen extends ConsumerWidget {
  const RoutineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider);
    final fmt = DateFormat('HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('루틴 업무 체크')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addTask(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('업무 추가'),
      ),
      body: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (list) {
          if (list.isEmpty) return const Center(child: Text('등록된 업무가 없습니다'));
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final t = list[i];
              final sched = t.scheduledTime != null
                  ? DateTime.tryParse(t.scheduledTime!)
                  : null;
              return CheckboxListTile(
                value: t.isCompleted,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(t.taskName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: t.isCompleted ? TextDecoration.lineThrough : null,
                    )),
                subtitle: sched != null ? Text('예정 ${fmt.format(sched)}') : null,
                secondary: t.isSynced == 0
                    ? const Icon(Icons.cloud_off, size: 18, color: Colors.grey)
                    : const Icon(Icons.cloud_done, size: 18, color: Colors.green),
                onChanged: (_) async {
                  final session = ref.read(sessionProvider);
                  await ref.read(localRepoProvider).toggleTaskDone(
                        t,
                        workerId: session?.memberId ?? '',
                      );
                  ref.invalidate(tasksProvider);
                  ref.read(syncServiceProvider).syncNow();
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _addTask(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('업무 추가'),
        content: TextField(
            controller: name,
            decoration: const InputDecoration(
                labelText: '업무명(예: 소독, 환기)', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('추가')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await ref.read(localRepoProvider).upsertTask(RoutineTask(
            id: const Uuid().v4(),
            taskName: name.text.trim(),
            scheduledTime: DateTime.now().toIso8601String(),
          ));
      ref.invalidate(tasksProvider);
      ref.read(syncServiceProvider).syncNow();
    }
    name.dispose();
  }
}
