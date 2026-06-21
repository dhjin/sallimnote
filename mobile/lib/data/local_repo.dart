import 'package:sqflite/sqflite.dart';

import '../core/local_db.dart';
import '../models/models.dart';

/// 로컬 SQLite CRUD. 모든 쓰기는 is_synced=0 으로 저장 → 동기화 워커가 업로드.
class LocalRepo {
  Future<Database> get _db async => LocalDb.instance.database;

  // ── Babies ───────────────────────────────────────────────────────────
  Future<List<Baby>> babies() async {
    final db = await _db;
    final rows = await db.query('babies',
        where: 'deleted = 0', orderBy: 'name COLLATE NOCASE');
    return rows.map(Baby.fromMap).toList();
  }

  Future<void> upsertBaby(Baby b) async {
    final db = await _db;
    final map = b.toMap()..['is_synced'] = 0;
    await db.insert('babies', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── Health logs ──────────────────────────────────────────────────────
  Future<List<HealthLog>> logsForBaby(String babyId) async {
    final db = await _db;
    final rows = await db.query('neonatal_health_log',
        where: 'baby_id = ? AND deleted = 0',
        whereArgs: [babyId],
        orderBy: 'timestamp DESC');
    return rows.map(HealthLog.fromMap).toList();
  }

  Future<List<HealthLog>> recentLogs({int limit = 50}) async {
    final db = await _db;
    final rows = await db.query('neonatal_health_log',
        where: 'deleted = 0', orderBy: 'timestamp DESC', limit: limit);
    return rows.map(HealthLog.fromMap).toList();
  }

  Future<void> insertLog(HealthLog log) async {
    final db = await _db;
    final map = log.toMap()..['is_synced'] = 0;
    await db.insert('neonatal_health_log', map,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── Routine tasks ────────────────────────────────────────────────────
  Future<List<RoutineTask>> tasks() async {
    final db = await _db;
    final rows = await db.query('routine_tasks',
        where: 'deleted = 0', orderBy: 'scheduled_time ASC');
    return rows.map(RoutineTask.fromMap).toList();
  }

  Future<void> upsertTask(RoutineTask t) async {
    final db = await _db;
    final map = t.toMap()..['is_synced'] = 0;
    await db.insert('routine_tasks', map,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── Routine definitions (반복 설정) ──────────────────────────────────
  Future<List<RoutineDefinition>> routineDefinitions() async {
    final db = await _db;
    final rows = await db.query('routine_definitions',
        where: 'deleted = 0', orderBy: 'task_name COLLATE NOCASE');
    return rows.map(RoutineDefinition.fromMap).toList();
  }

  Future<void> upsertDefinition(RoutineDefinition d) async {
    final db = await _db;
    final map = d.toMap()..['is_synced'] = 0;
    await db.insert('routine_definitions', map,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteDefinition(RoutineDefinition d) async {
    final db = await _db;
    await db.update('routine_definitions', {'deleted': 1, 'is_synced': 0},
        where: 'id = ?', whereArgs: [d.id]);
  }

  Future<RoutineTask?> occurrenceFor(String defId, String windowIso) async {
    final db = await _db;
    final rows = await db.query('routine_tasks',
        where: 'definition_id = ? AND scheduled_time = ? AND deleted = 0',
        whereArgs: [defId, windowIso], limit: 1);
    return rows.isEmpty ? null : RoutineTask.fromMap(rows.first);
  }

  /// 현재 주기의 완료 토글. 완료 시 마감자(id/이름) 기록.
  Future<void> setRoutineDone(
    RoutineDefinition d,
    DateTime windowStart, {
    required bool done,
    required String memberId,
    required String memberName,
  }) async {
    final iso = windowStart.toIso8601String();
    final occurrenceId = '${d.id}#${windowStart.millisecondsSinceEpoch}';
    await upsertTask(RoutineTask(
      id: occurrenceId,
      definitionId: d.id,
      roomId: d.roomId,
      taskName: d.taskName,
      scheduledTime: iso,
      completedTime: done ? DateTime.now().toIso8601String() : null,
      completedBy: done ? memberId : null,
      completedByName: done ? memberName : null,
    ));
  }

  /// 활성 정의 + 현재 주기 완료기록을 묶어 반환.
  Future<List<({RoutineDefinition def, RoutineTask? occ})>> routineStatuses() async {
    final defs = await routineDefinitions();
    final result = <({RoutineDefinition def, RoutineTask? occ})>[];
    for (final d in defs.where((x) => x.isActive)) {
      final occ = await occurrenceFor(d.id, d.currentWindowStart().toIso8601String());
      result.add((def: d, occ: occ));
    }
    return result;
  }

  // ── Notices ──────────────────────────────────────────────────────────
  Future<List<Notice>> notices() async {
    final db = await _db;
    final rows = await db.query('notices',
        where: 'deleted = 0', orderBy: 'pinned DESC, created_at DESC');
    return rows.map(Notice.fromMap).toList();
  }

  Future<void> upsertNotice(Notice n) async {
    final db = await _db;
    final map = n.toMap()..['is_synced'] = 0;
    await db.insert('notices', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteNotice(Notice n) async {
    final db = await _db;
    await db.update('notices', {'deleted': 1, 'is_synced': 0},
        where: 'id = ?', whereArgs: [n.id]);
  }

  // ── Rooms ────────────────────────────────────────────────────────────
  Future<List<Room>> rooms() async {
    final db = await _db;
    final rows = await db.query('rooms', where: 'deleted = 0', orderBy: 'name');
    return rows.map(Room.fromMap).toList();
  }

  Future<void> upsertRoom(Room r) async {
    final db = await _db;
    final map = r.toMap()..['is_synced'] = 0;
    await db.insert('rooms', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
