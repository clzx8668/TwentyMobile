import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:pocketcrm/core/di/providers.dart';
import 'package:pocketcrm/domain/models/task.dart';
import 'package:pocketcrm/domain/models/contact.dart';

part 'today_provider.freezed.dart';
part 'today_provider.g.dart';

@riverpod
class TodayNotifier extends _$TodayNotifier {
  @override
  Future<TodayData> build() async {
    return _loadTodayData();
  }

  Future<TodayData> _loadTodayData() async {
    final repo = await ref.read(crmRepositoryProvider.future);

    // Load sections independently: a single backend/query failure should not
    // make the whole Home page fail.
    final overdueTasksFuture =
        _safeLoad(() => repo.getOverdueTasks(), <Task>[]);
    final todayTasksFuture = _safeLoad(() => repo.getTodayTasks(), <Task>[]);
    final tomorrowTasksFuture =
        _safeLoad(() => repo.getTomorrowTasks(), <Task>[]);
    final recentContactsFuture =
        _safeLoad(() => repo.getRecentContacts(limit: 5), <Contact>[]);

    final overdueTasks = await overdueTasksFuture;
    final todayTasks = await todayTasksFuture;
    final tomorrowTasks = await tomorrowTasksFuture;
    final recentContacts = await recentContactsFuture;

    return TodayData(
      overdueTasks: overdueTasks,
      todayTasks: todayTasks,
      tomorrowTasks: tomorrowTasks,
      recentContacts: recentContacts,
    );
  }

  Future<List<T>> _safeLoad<T>(
    Future<List<T>> Function() loader,
    List<T> fallback,
  ) async {
    try {
      return await loader();
    } catch (_) {
      return fallback;
    }
  }

  Future<void> completeTask(String taskId) async {
    // Aggiorniamo lo status passando completed: true al metodo esistente
    final repo = await ref.read(crmRepositoryProvider.future);
    await repo.updateTask(taskId, completed: true);
    ref.invalidateSelf(); // ricarica tutto
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

@freezed
class TodayData with _$TodayData {
  factory TodayData({
    required List<Task> overdueTasks,
    required List<Task> todayTasks,
    required List<Task> tomorrowTasks,
    required List<Contact> recentContacts,
  }) = _TodayData;
}
