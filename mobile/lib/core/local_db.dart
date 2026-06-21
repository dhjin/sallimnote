import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// 로컬 SQLite — 오프라인 입력 버퍼. 신뢰원본은 서버(PostgreSQL).
/// 서버 스키마와 동일한 컬럼 + 로컬 전용 is_synced(0=미동기화,1=동기화됨).
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'postpartum_care.db');
    _db = await openDatabase(path, version: 4,
        onCreate: _onCreate, onUpgrade: _onUpgrade);
    return _db!;
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(_noticesDdl);
    }
    if (oldVersion < 3) {
      await db.execute(_routineDefsDdl);
      await db.execute('ALTER TABLE neonatal_health_log ADD COLUMN stool_count INTEGER');
      await db.execute('ALTER TABLE routine_tasks ADD COLUMN definition_id TEXT');
      await db.execute('ALTER TABLE routine_tasks ADD COLUMN completed_by_name TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE neonatal_health_log ADD COLUMN worker_name TEXT');
    }
  }

  static const String _noticesDdl = '''
      CREATE TABLE notices (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        body TEXT DEFAULT '',
        pinned INTEGER DEFAULT 0,
        created_by TEXT,
        created_at TEXT,
        deleted INTEGER DEFAULT 0,
        is_synced INTEGER DEFAULT 0
      )''';

  static const String _routineDefsDdl = '''
      CREATE TABLE routine_definitions (
        id TEXT PRIMARY KEY,
        room_id TEXT,
        task_name TEXT NOT NULL,
        interval_hours INTEGER DEFAULT 8,
        anchor_hour INTEGER DEFAULT 0,
        is_active INTEGER DEFAULT 1,
        deleted INTEGER DEFAULT 0,
        is_synced INTEGER DEFAULT 0
      )''';

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE rooms (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        deleted INTEGER DEFAULT 0,
        is_synced INTEGER DEFAULT 0
      )''');

    await db.execute('''
      CREATE TABLE babies (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        room_id TEXT,
        birth_date TEXT,
        guardian_name TEXT DEFAULT '',
        is_active INTEGER DEFAULT 1,
        deleted INTEGER DEFAULT 0,
        is_synced INTEGER DEFAULT 0
      )''');

    await db.execute('''
      CREATE TABLE neonatal_health_log (
        id TEXT PRIMARY KEY,
        baby_id TEXT NOT NULL,
        temperature REAL,
        feeding_ml INTEGER,
        stool_count INTEGER,
        memo TEXT DEFAULT '',
        timestamp TEXT,
        worker_id TEXT,
        worker_name TEXT,
        deleted INTEGER DEFAULT 0,
        is_synced INTEGER DEFAULT 0
      )''');

    await db.execute('''
      CREATE TABLE routine_tasks (
        id TEXT PRIMARY KEY,
        definition_id TEXT,
        room_id TEXT,
        task_name TEXT NOT NULL,
        scheduled_time TEXT,
        completed_time TEXT,
        completed_by TEXT,
        completed_by_name TEXT,
        deleted INTEGER DEFAULT 0,
        is_synced INTEGER DEFAULT 0
      )''');

    await db.execute(_routineDefsDdl);
    await db.execute(_noticesDdl);

    await db.execute('CREATE INDEX idx_log_baby ON neonatal_health_log(baby_id)');
    await db.execute('CREATE INDEX idx_log_unsynced ON neonatal_health_log(is_synced)');
    await db.execute('CREATE INDEX idx_task_unsynced ON routine_tasks(is_synced)');
  }

  /// 테넌트 전환/로그아웃 시 로컬 캐시 비우기(다른 조리원 데이터 잔존 방지).
  Future<void> clearAll() async {
    final db = await database;
    await db.transaction((txn) async {
      for (final t in ['rooms', 'babies', 'neonatal_health_log', 'routine_tasks',
                       'routine_definitions', 'notices']) {
        await txn.delete(t);
      }
    });
  }
}
