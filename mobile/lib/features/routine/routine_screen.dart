import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/session.dart';
import '../../data/providers.dart';
import '../../data/sync_service.dart';
import '../../models/models.dart';

/// 루틴 업무 — N시간 주기 반복 정의 + 현재 주기 완료 체크(마감자 표시).
class RoutineScreen extends ConsumerWidget {
  const RoutineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statuses = ref.watch(routineStatusProvider);
    final fmt = DateFormat('MM/dd HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('루틴 업무 체크')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editDefinition(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('루틴 설정'),
      ),
      body: statuses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
                child: Text('등록된 루틴이 없습니다.\n우측 하단 "루틴 설정"으로 추가하세요',
                    textAlign: TextAlign.center));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final def = list[i].def;
              final occ = list[i].occ;
              final done = occ?.isCompleted ?? false;
              final windowStart = def.currentWindowStart();
              final completedAt =
                  occ?.completedTime != null ? DateTime.tryParse(occ!.completedTime!) : null;

              return CheckboxListTile(
                value: done,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(def.taskName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: done ? TextDecoration.lineThrough : null,
                    )),
                subtitle: Text(done
                    ? '✓ ${occ?.completedByName ?? '완료'}'
                        '${completedAt != null ? ' · ${fmt.format(completedAt)}' : ''}'
                    : '${def.intervalHours}시간 주기 · 이번 주기 ${fmt.format(windowStart)}'),
                secondary: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') _editDefinition(context, ref, def: def);
                    if (v == 'delete') _deleteDefinition(context, ref, def);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('수정')),
                    PopupMenuItem(value: 'delete', child: Text('삭제')),
                  ],
                ),
                onChanged: (v) async {
                  final session = ref.read(sessionProvider);
                  await ref.read(localRepoProvider).setRoutineDone(
                        def,
                        windowStart,
                        done: v ?? false,
                        memberId: session?.memberId ?? '',
                        memberName: session?.displayName ?? '',
                      );
                  ref.invalidate(routineStatusProvider);
                  ref.read(syncServiceProvider).syncNow();
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _deleteDefinition(
      BuildContext context, WidgetRef ref, RoutineDefinition def) async {
    await ref.read(localRepoProvider).deleteDefinition(def);
    ref.invalidate(routineStatusProvider);
    ref.read(syncServiceProvider).syncNow();
  }

  /// 루틴 정의 추가/수정 — 업무명 + 주기(시간) + 기준 시각.
  Future<void> _editDefinition(BuildContext context, WidgetRef ref,
      {RoutineDefinition? def}) async {
    final name = TextEditingController(text: def?.taskName ?? '');
    final interval = TextEditingController(text: '${def?.intervalHours ?? 8}');
    final anchor = TextEditingController(text: '${def?.anchorHour ?? 0}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(def == null ? '루틴 설정 추가' : '루틴 설정 수정'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: name,
                  decoration: const InputDecoration(
                      labelText: '업무명(예: 소독, 환기)', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(
                  controller: interval,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: '주기(시간) — 예: 4 = 4시간마다',
                      border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(
                  controller: anchor,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: '기준 시작 시각(0~23시)', border: OutlineInputBorder())),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('저장')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      final h = int.tryParse(interval.text.trim()) ?? 8;
      final a = ((int.tryParse(anchor.text.trim()) ?? 0).clamp(0, 23)).toInt();
      await ref.read(localRepoProvider).upsertDefinition(RoutineDefinition(
            id: def?.id ?? const Uuid().v4(),
            taskName: name.text.trim(),
            intervalHours: h <= 0 ? 1 : h,
            anchorHour: a,
            roomId: def?.roomId,
          ));
      ref.invalidate(routineStatusProvider);
      ref.read(syncServiceProvider).syncNow();
    }
    name.dispose();
    interval.dispose();
    anchor.dispose();
  }
}
