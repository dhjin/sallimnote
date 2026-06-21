import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'local_repo.dart';

final localRepoProvider = Provider<LocalRepo>((ref) => LocalRepo());

/// 목록 새로고침 트리거. 쓰기 후 ref.invalidate(...) 로 갱신.
final babiesProvider = FutureProvider.autoDispose<List<Baby>>(
    (ref) => ref.read(localRepoProvider).babies());

final tasksProvider = FutureProvider.autoDispose<List<RoutineTask>>(
    (ref) => ref.read(localRepoProvider).tasks());

/// 활성 루틴 정의 + 현재 주기 완료 상태.
final routineStatusProvider = FutureProvider.autoDispose<
    List<({RoutineDefinition def, RoutineTask? occ})>>(
  (ref) => ref.read(localRepoProvider).routineStatuses());

final roomsProvider = FutureProvider.autoDispose<List<Room>>(
    (ref) => ref.read(localRepoProvider).rooms());

final noticesProvider = FutureProvider.autoDispose<List<Notice>>(
    (ref) => ref.read(localRepoProvider).notices());

final logsForBabyProvider = FutureProvider.autoDispose
    .family<List<HealthLog>, String>(
        (ref, babyId) => ref.read(localRepoProvider).logsForBaby(babyId));
