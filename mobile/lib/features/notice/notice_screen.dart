import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/session.dart';
import '../../data/providers.dart';
import '../../data/sync_service.dart';
import '../../models/models.dart';

/// 조리원 공지 — owner/admin 작성, 전 직원 조회. 고정(pinned) 공지가 상단.
class NoticeScreen extends ConsumerWidget {
  const NoticeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(noticesProvider);
    final session = ref.watch(sessionProvider);
    final canWrite = session?.isAdmin ?? false;
    final fmt = DateFormat('MM/dd HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('조리원 공지')),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _compose(context, ref),
              icon: const Icon(Icons.campaign),
              label: const Text('공지 작성'),
            )
          : null,
      body: notices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('등록된 공지가 없습니다'));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final n = list[i];
              final created =
                  n.createdAt != null ? DateTime.tryParse(n.createdAt!) : null;
              return ListTile(
                leading: Icon(n.pinned ? Icons.push_pin : Icons.campaign,
                    color: n.pinned ? Colors.redAccent : Colors.blueGrey),
                title: Text(n.title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (n.body.isNotEmpty) Text(n.body),
                    if (created != null)
                      Text(fmt.format(created),
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                isThreeLine: n.body.isNotEmpty,
                trailing: canWrite
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await ref.read(localRepoProvider).deleteNotice(n);
                          ref.invalidate(noticesProvider);
                          ref.read(syncServiceProvider).syncNow();
                        },
                      )
                    : (n.isSynced == 0
                        ? const Icon(Icons.cloud_off, size: 18, color: Colors.grey)
                        : null),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _compose(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final body = TextEditingController();
    bool pinned = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('공지 작성'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: title,
                  decoration: const InputDecoration(
                      labelText: '제목', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(
                  controller: body,
                  maxLines: 4,
                  decoration: const InputDecoration(
                      labelText: '내용', border: OutlineInputBorder())),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: pinned,
                title: const Text('상단 고정'),
                onChanged: (v) => setState(() => pinned = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('게시')),
          ],
        ),
      ),
    );
    if (ok == true && title.text.trim().isNotEmpty) {
      final session = ref.read(sessionProvider);
      await ref.read(localRepoProvider).upsertNotice(Notice(
            id: const Uuid().v4(),
            title: title.text.trim(),
            body: body.text.trim(),
            pinned: pinned,
            createdBy: session?.memberId,
            createdAt: DateTime.now().toIso8601String(),
          ));
      ref.invalidate(noticesProvider);
      ref.read(syncServiceProvider).syncNow();
    }
    title.dispose();
    body.dispose();
  }
}
