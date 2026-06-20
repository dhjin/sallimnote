import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/local_repo.dart';
import '../../data/providers.dart';
import '../../data/sync_service.dart';
import '../../models/models.dart';
import 'health_log_screen.dart';

class BabyListScreen extends ConsumerWidget {
  const BabyListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final babies = ref.watch(babiesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('신생아 건강기록')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addBaby(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('신생아 등록'),
      ),
      body: babies.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('등록된 신생아가 없습니다'));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final b = list[i];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.child_care)),
                title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(b.guardianName.isEmpty ? '' : '보호자: ${b.guardianName}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => HealthLogScreen(baby: b)),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _addBaby(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final guardian = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('신생아 등록'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(
                    labelText: '식별명(예: 김OO아기/101호)', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(
                controller: guardian,
                decoration: const InputDecoration(
                    labelText: '보호자(산모)', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('등록')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await ref.read(localRepoProvider).upsertBaby(Baby(
            id: const Uuid().v4(),
            name: name.text.trim(),
            guardianName: guardian.text.trim(),
          ));
      ref.invalidate(babiesProvider);
      ref.read(syncServiceProvider).syncNow();
    }
    name.dispose();
    guardian.dispose();
  }
}
