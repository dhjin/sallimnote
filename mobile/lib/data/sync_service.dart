import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../core/api_client.dart';
import '../core/local_db.dart';
import '../core/session.dart';
import '../models/models.dart';

/// 오프라인 우선 동기화.
/// 1) is_synced=0 레코드를 /sync 로 업로드 → 성공 시 is_synced=1
/// 2) 서버 응답(전체 상태)을 로컬에 병합(이미 동기화된 행 갱신)
/// 3) 네트워크 복귀 감지 시 자동 실행
class SyncService {
  SyncService(this._api);
  final ApiClient _api;

  StreamSubscription? _connSub;
  bool _running = false;

  /// 마지막 알림(체온 임계치 등) — UI 가 ValueListenableBuilder 로 구독.
  final alerts = ValueNotifier<List<Map<String, dynamic>>>([]);

  void startAutoSync() {
    _connSub?.cancel();
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) syncNow();
    });
  }

  void dispose() {
    _connSub?.cancel();
    alerts.dispose();
  }

  Future<bool> _isOnline() async {
    final r = await Connectivity().checkConnectivity();
    return r.any((x) => x != ConnectivityResult.none);
  }

  Future<void> syncNow() async {
    if (_running) return;
    if (!await _isOnline()) return;
    _running = true;
    try {
      final db = await LocalDb.instance.database;
      final payload = await _collectUnsynced(db);
      final resp = await _api.sync(payload);
      await _applyServerState(db, resp);
      await _markSynced(db);
      final a = (resp['alerts'] as List?) ?? [];
      alerts.value = a.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      // 오프라인/일시 오류 — 다음 기회에 재시도(레코드는 is_synced=0 유지).
    } finally {
      _running = false;
    }
  }

  Future<Map<String, dynamic>> _collectUnsynced(Database db) async {
    Future<List<Map<String, dynamic>>> un(String table, dynamic Function(Map<String, dynamic>) toJson) async {
      final rows = await db.query(table, where: 'is_synced = 0');
      return rows.map((r) => toJson(r) as Map<String, dynamic>).toList();
    }

    return {
      'rooms': await un('rooms', (r) => Room.fromMap(r).toSyncJson()),
      'babies': await un('babies', (r) => Baby.fromMap(r).toSyncJson()),
      'health_logs':
          await un('neonatal_health_log', (r) => HealthLog.fromMap(r).toSyncJson()),
      'routine_tasks':
          await un('routine_tasks', (r) => RoutineTask.fromMap(r).toSyncJson()),
      'routine_definitions': await un(
          'routine_definitions', (r) => RoutineDefinition.fromMap(r).toSyncJson()),
      'notices': await un('notices', (r) => Notice.fromMap(r).toSyncJson()),
    };
  }

  /// 업로드 시도한 미동기화 행을 is_synced=1 로 표시.
  /// (서버가 last-write-wins 로 수용했으므로 안전. 충돌은 다음 pull 에서 정정.)
  Future<void> _markSynced(Database db) async {
    for (final t in ['rooms', 'babies', 'neonatal_health_log', 'routine_tasks',
                     'routine_definitions', 'notices']) {
      await db.update(t, {'is_synced': 1}, where: 'is_synced = 0');
    }
  }

  /// 서버 상태를 로컬에 반영. 서버발 행은 is_synced=1 로 저장.
  Future<void> _applyServerState(Database db, Map<String, dynamic> resp) async {
    await db.transaction((txn) async {
      Future<void> merge(String table, List? items) async {
        for (final raw in items ?? const []) {
          final m = Map<String, dynamic>.from(raw);
          final row = _serverToLocal(table, m)..['is_synced'] = 1;
          await txn.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      await merge('rooms', resp['rooms'] as List?);
      await merge('babies', resp['babies'] as List?);
      await merge('neonatal_health_log', resp['health_logs'] as List?);
      await merge('routine_tasks', resp['routine_tasks'] as List?);
      await merge('routine_definitions', resp['routine_definitions'] as List?);
      await merge('notices', resp['notices'] as List?);
    });
  }

  Map<String, dynamic> _serverToLocal(String table, Map<String, dynamic> m) {
    bool b(v) => (v == true) ? true : false;
    switch (table) {
      case 'rooms':
        return {'id': m['id'], 'name': m['name'], 'deleted': b(m['deleted']) ? 1 : 0};
      case 'babies':
        return {
          'id': m['id'], 'name': m['name'], 'room_id': m['room_id'],
          'birth_date': m['birth_date'], 'guardian_name': m['guardian_name'] ?? '',
          'is_active': b(m['is_active']) ? 1 : 0, 'deleted': b(m['deleted']) ? 1 : 0,
        };
      case 'neonatal_health_log':
        return {
          'id': m['id'], 'baby_id': m['baby_id'], 'temperature': m['temperature'],
          'feeding_ml': m['feeding_ml'], 'stool_count': m['stool_count'],
          'memo': m['memo'] ?? '',
          'timestamp': m['timestamp'], 'worker_id': m['worker_id'],
          'deleted': b(m['deleted']) ? 1 : 0,
        };
      case 'routine_tasks':
        return {
          'id': m['id'], 'definition_id': m['definition_id'], 'room_id': m['room_id'],
          'task_name': m['task_name'],
          'scheduled_time': m['scheduled_time'], 'completed_time': m['completed_time'],
          'completed_by': m['completed_by'], 'completed_by_name': m['completed_by_name'],
          'deleted': b(m['deleted']) ? 1 : 0,
        };
      case 'routine_definitions':
        return {
          'id': m['id'], 'room_id': m['room_id'], 'task_name': m['task_name'],
          'interval_hours': m['interval_hours'] ?? 8, 'anchor_hour': m['anchor_hour'] ?? 0,
          'is_active': b(m['is_active']) ? 1 : 0, 'deleted': b(m['deleted']) ? 1 : 0,
        };
      case 'notices':
        return {
          'id': m['id'], 'title': m['title'], 'body': m['body'] ?? '',
          'pinned': b(m['pinned']) ? 1 : 0, 'created_by': m['created_by'],
          'created_at': m['created_at'], 'deleted': b(m['deleted']) ? 1 : 0,
        };
      default:
        return m;
    }
  }
}

final syncServiceProvider = Provider<SyncService>((ref) {
  final svc = SyncService(ref.read(apiClientProvider));
  ref.onDispose(svc.dispose);
  return svc;
});
