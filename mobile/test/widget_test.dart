// 모델 직렬화 단위 테스트.
// (flutter create 가 생성하는 기본 widget_test.dart 를 대체 — 기본 파일은
//  존재하지 않는 MyApp 을 참조해 analyze 가 실패한다.)

import 'package:flutter_test/flutter_test.dart';
import 'package:postpartum_care/models/models.dart';

void main() {
  test('Baby toMap/fromMap 라운드트립', () {
    final b = Baby(
      id: 'b1',
      name: '아기A',
      roomId: 'r1',
      guardianName: '산모',
      isActive: true,
    );
    final restored = Baby.fromMap(b.toMap());
    expect(restored.id, 'b1');
    expect(restored.name, '아기A');
    expect(restored.roomId, 'r1');
    expect(restored.guardianName, '산모');
    expect(restored.isActive, true);
  });

  test('HealthLog toSyncJson 은 is_synced 를 포함하지 않는다(로컬 전용)', () {
    final log = HealthLog(
      id: 'l1',
      babyId: 'b1',
      temperature: 38.1,
      feedingMl: 60,
      timestamp: '2026-06-20T10:00:00.000',
      isSynced: 0,
    );
    final json = log.toSyncJson();
    expect(json.containsKey('is_synced'), false);
    expect(json['temperature'], 38.1);
    expect(json['baby_id'], 'b1');
  });

  test('RoutineTask 완료 여부는 completedTime 으로 판정', () {
    final pending = RoutineTask(id: 't1', taskName: '소독');
    expect(pending.isCompleted, false);

    final done = RoutineTask(
        id: 't1', taskName: '소독', completedTime: '2026-06-20T11:00:00.000');
    expect(done.isCompleted, true);
  });

  test('RoutineDefinition 현재 주기 계산 (4시간 주기)', () {
    final def = RoutineDefinition(
        id: 'd1', taskName: '환기', intervalHours: 4, anchorHour: 0);
    final ws = def.currentWindowStart(DateTime(2026, 6, 21, 9, 30));
    // anchor 0시 기준 4시간 주기 → 09:30 이 속한 주기 시작은 08:00
    expect(ws, DateTime(2026, 6, 21, 8));
  });
}
