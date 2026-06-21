// 도메인 모델. 로컬 sqflite 컬럼명은 서버 API(snake_case)와 동일하게 맞춰
// 동기화 시 변환 비용을 없앤다. is_synced 는 로컬 전용(서버로 보내지 않음).

class Room {
  final String id;
  final String name;
  final bool deleted;
  final int isSynced;

  Room({required this.id, required this.name, this.deleted = false, this.isSynced = 0});

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'deleted': deleted ? 1 : 0,
        'is_synced': isSynced,
      };

  factory Room.fromMap(Map<String, dynamic> m) => Room(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        deleted: (m['deleted'] ?? 0) == 1,
        isSynced: (m['is_synced'] ?? 0) as int,
      );

  /// 서버 /sync 업로드용 (is_synced 제외).
  Map<String, dynamic> toSyncJson() =>
      {'id': id, 'name': name, 'deleted': deleted};
}

class Baby {
  final String id;
  final String name;
  final String? roomId;
  final String? birthDate; // "YYYY-MM-DD"
  final String guardianName;
  final bool isActive;
  final bool deleted;
  final int isSynced;

  Baby({
    required this.id,
    required this.name,
    this.roomId,
    this.birthDate,
    this.guardianName = '',
    this.isActive = true,
    this.deleted = false,
    this.isSynced = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'room_id': roomId,
        'birth_date': birthDate,
        'guardian_name': guardianName,
        'is_active': isActive ? 1 : 0,
        'deleted': deleted ? 1 : 0,
        'is_synced': isSynced,
      };

  factory Baby.fromMap(Map<String, dynamic> m) => Baby(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        roomId: m['room_id'] as String?,
        birthDate: m['birth_date'] as String?,
        guardianName: m['guardian_name'] as String? ?? '',
        isActive: (m['is_active'] ?? 1) == 1,
        deleted: (m['deleted'] ?? 0) == 1,
        isSynced: (m['is_synced'] ?? 0) as int,
      );

  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'name': name,
        'room_id': roomId,
        'birth_date': birthDate,
        'guardian_name': guardianName,
        'is_active': isActive,
        'deleted': deleted,
      };
}

class HealthLog {
  final String id;
  final String babyId;
  final double? temperature;
  final int? feedingMl;
  final int? stoolCount; // 배변 횟수
  final String memo;
  final String timestamp; // ISO8601
  final String? workerId;
  final bool deleted;
  final int isSynced;

  HealthLog({
    required this.id,
    required this.babyId,
    this.temperature,
    this.feedingMl,
    this.stoolCount,
    this.memo = '',
    required this.timestamp,
    this.workerId,
    this.deleted = false,
    this.isSynced = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'baby_id': babyId,
        'temperature': temperature,
        'feeding_ml': feedingMl,
        'stool_count': stoolCount,
        'memo': memo,
        'timestamp': timestamp,
        'worker_id': workerId,
        'deleted': deleted ? 1 : 0,
        'is_synced': isSynced,
      };

  factory HealthLog.fromMap(Map<String, dynamic> m) => HealthLog(
        id: m['id'] as String,
        babyId: m['baby_id'] as String,
        temperature: (m['temperature'] as num?)?.toDouble(),
        feedingMl: m['feeding_ml'] as int?,
        stoolCount: m['stool_count'] as int?,
        memo: m['memo'] as String? ?? '',
        timestamp: m['timestamp'] as String? ?? '',
        workerId: m['worker_id'] as String?,
        deleted: (m['deleted'] ?? 0) == 1,
        isSynced: (m['is_synced'] ?? 0) as int,
      );

  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'baby_id': babyId,
        'temperature': temperature,
        'feeding_ml': feedingMl,
        'stool_count': stoolCount,
        'memo': memo,
        'timestamp': timestamp,
        'worker_id': workerId,
        'deleted': deleted,
      };
}

class Notice {
  final String id;
  final String title;
  final String body;
  final bool pinned;
  final String? createdBy;
  final String? createdAt; // ISO8601
  final bool deleted;
  final int isSynced;

  Notice({
    required this.id,
    required this.title,
    this.body = '',
    this.pinned = false,
    this.createdBy,
    this.createdAt,
    this.deleted = false,
    this.isSynced = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'body': body,
        'pinned': pinned ? 1 : 0,
        'created_by': createdBy,
        'created_at': createdAt,
        'deleted': deleted ? 1 : 0,
        'is_synced': isSynced,
      };

  factory Notice.fromMap(Map<String, dynamic> m) => Notice(
        id: m['id'] as String,
        title: m['title'] as String? ?? '',
        body: m['body'] as String? ?? '',
        pinned: (m['pinned'] ?? 0) == 1,
        createdBy: m['created_by'] as String?,
        createdAt: m['created_at'] as String?,
        deleted: (m['deleted'] ?? 0) == 1,
        isSynced: (m['is_synced'] ?? 0) as int,
      );

  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'title': title,
        'body': body,
        'pinned': pinned,
        'created_by': createdBy,
        'deleted': deleted,
      };
}

/// 루틴 설정 — N시간 주기로 반복되는 업무 정의.
class RoutineDefinition {
  final String id;
  final String? roomId;
  final String taskName;
  final int intervalHours; // 몇 시간 주기
  final int anchorHour;    // 하루 중 기준 시각(0-23)
  final bool isActive;
  final bool deleted;
  final int isSynced;

  RoutineDefinition({
    required this.id,
    this.roomId,
    required this.taskName,
    this.intervalHours = 8,
    this.anchorHour = 0,
    this.isActive = true,
    this.deleted = false,
    this.isSynced = 0,
  });

  int get _h => intervalHours <= 0 ? 1 : intervalHours;

  /// 현재 주기의 시작 시각(예정 시각).
  DateTime currentWindowStart([DateTime? now]) {
    now ??= DateTime.now();
    var anchor = DateTime(now.year, now.month, now.day, anchorHour);
    if (now.isBefore(anchor)) anchor = anchor.subtract(const Duration(days: 1));
    final cycles = now.difference(anchor).inMinutes ~/ (_h * 60);
    return anchor.add(Duration(hours: _h * cycles));
  }

  DateTime nextWindowStart([DateTime? now]) =>
      currentWindowStart(now).add(Duration(hours: _h));

  Map<String, dynamic> toMap() => {
        'id': id,
        'room_id': roomId,
        'task_name': taskName,
        'interval_hours': intervalHours,
        'anchor_hour': anchorHour,
        'is_active': isActive ? 1 : 0,
        'deleted': deleted ? 1 : 0,
        'is_synced': isSynced,
      };

  factory RoutineDefinition.fromMap(Map<String, dynamic> m) => RoutineDefinition(
        id: m['id'] as String,
        roomId: m['room_id'] as String?,
        taskName: m['task_name'] as String? ?? '',
        intervalHours: (m['interval_hours'] ?? 8) as int,
        anchorHour: (m['anchor_hour'] ?? 0) as int,
        isActive: (m['is_active'] ?? 1) == 1,
        deleted: (m['deleted'] ?? 0) == 1,
        isSynced: (m['is_synced'] ?? 0) as int,
      );

  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'room_id': roomId,
        'task_name': taskName,
        'interval_hours': intervalHours,
        'anchor_hour': anchorHour,
        'is_active': isActive,
        'deleted': deleted,
      };
}

/// 루틴 '발생/완료 기록' — 특정 정의의 한 주기에 대한 완료 여부.
class RoutineTask {
  final String id;
  final String? definitionId;
  final String? roomId;
  final String taskName;
  final String? scheduledTime; // ISO8601 (해당 주기 예정 시각)
  final String? completedTime; // ISO8601, null = 미완료
  final String? completedBy;
  final String? completedByName; // 마감자 이름(표시용)
  final bool deleted;
  final int isSynced;

  RoutineTask({
    required this.id,
    this.definitionId,
    this.roomId,
    required this.taskName,
    this.scheduledTime,
    this.completedTime,
    this.completedBy,
    this.completedByName,
    this.deleted = false,
    this.isSynced = 0,
  });

  bool get isCompleted => completedTime != null;

  Map<String, dynamic> toMap() => {
        'id': id,
        'definition_id': definitionId,
        'room_id': roomId,
        'task_name': taskName,
        'scheduled_time': scheduledTime,
        'completed_time': completedTime,
        'completed_by': completedBy,
        'completed_by_name': completedByName,
        'deleted': deleted ? 1 : 0,
        'is_synced': isSynced,
      };

  factory RoutineTask.fromMap(Map<String, dynamic> m) => RoutineTask(
        id: m['id'] as String,
        definitionId: m['definition_id'] as String?,
        roomId: m['room_id'] as String?,
        taskName: m['task_name'] as String? ?? '',
        scheduledTime: m['scheduled_time'] as String?,
        completedTime: m['completed_time'] as String?,
        completedBy: m['completed_by'] as String?,
        completedByName: m['completed_by_name'] as String?,
        deleted: (m['deleted'] ?? 0) == 1,
        isSynced: (m['is_synced'] ?? 0) as int,
      );

  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'definition_id': definitionId,
        'room_id': roomId,
        'task_name': taskName,
        'scheduled_time': scheduledTime,
        'completed_time': completedTime,
        'completed_by': completedBy,
        'completed_by_name': completedByName,
        'deleted': deleted,
      };
}
