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

  Future<void> toggleTaskDone(RoutineTask t, {required String workerId}) async {
    final now = DateTime.now().toIso8601String();
    final db = await _db;
    await db.update(
      'routine_tasks',
      {
        'completed_time': t.isCompleted ? null : now,
        'completed_by': t.isCompleted ? null : workerId,
        'is_synced': 0,
      },
      where: 'id = ?',
      whereArgs: [t.id],
    );
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
