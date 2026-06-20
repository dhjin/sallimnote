/// 도메인 모델. 로컬 sqflite 컬럼명은 서버 API(snake_case)와 동일하게 맞춰
/// 동기화 시 변환 비용을 없앤다. is_synced 는 로컬 전용(서버로 보내지 않음).

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
        'memo': memo,
        'timestamp': timestamp,
        'worker_id': workerId,
        'deleted': deleted,
      };
}

class RoutineTask {
  final String id;
  final String? roomId;
  final String taskName;
  final String? scheduledTime; // ISO8601
  final String? completedTime; // ISO8601, null = 미완료
  final String? completedBy;
  final bool deleted;
  final int isSynced;

  RoutineTask({
    required this.id,
    this.roomId,
    required this.taskName,
    this.scheduledTime,
    this.completedTime,
    this.completedBy,
    this.deleted = false,
    this.isSynced = 0,
  });

  bool get isCompleted => completedTime != null;

  RoutineTask copyWith({String? completedTime, String? completedBy, int? isSynced}) =>
      RoutineTask(
        id: id,
        roomId: roomId,
        taskName: taskName,
        scheduledTime: scheduledTime,
        completedTime: completedTime ?? this.completedTime,
        completedBy: completedBy ?? this.completedBy,
        deleted: deleted,
        isSynced: isSynced ?? this.isSynced,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'room_id': roomId,
        'task_name': taskName,
        'scheduled_time': scheduledTime,
        'completed_time': completedTime,
        'completed_by': completedBy,
        'deleted': deleted ? 1 : 0,
        'is_synced': isSynced,
      };

  factory RoutineTask.fromMap(Map<String, dynamic> m) => RoutineTask(
        id: m['id'] as String,
        roomId: m['room_id'] as String?,
        taskName: m['task_name'] as String? ?? '',
        scheduledTime: m['scheduled_time'] as String?,
        completedTime: m['completed_time'] as String?,
        completedBy: m['completed_by'] as String?,
        deleted: (m['deleted'] ?? 0) == 1,
        isSynced: (m['is_synced'] ?? 0) as int,
      );

  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'room_id': roomId,
        'task_name': taskName,
        'scheduled_time': scheduledTime,
        'completed_time': completedTime,
        'completed_by': completedBy,
        'deleted': deleted,
      };
}
