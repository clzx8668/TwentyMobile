import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketcrm/core/di/providers.dart';
import 'package:pocketcrm/core/utils/storage_service.dart';
import 'package:pocketcrm/core/view_mode/view_mode.dart';

class ViewModeNotifier extends StateNotifier<ViewMode> {
  ViewModeNotifier({
    required StorageService storage,
    required String pageKey,
  })  : _storage = storage,
        _pageKey = pageKey,
        super(ViewMode.list) {
    _init();
  }

  final StorageService _storage;
  final String _pageKey;

  String get _storageKey => 'view_mode:$_pageKey';

  Future<void> _init() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      state = ViewModeStorage.fromStorageValue(raw);
    } catch (_) {}
  }

  Future<void> setMode(ViewMode mode) async {
    state = mode;
    try {
      await _storage.write(key: _storageKey, value: mode.storageValue);
    } catch (_) {}
  }

  Future<void> toggle() async {
    await setMode(state == ViewMode.list ? ViewMode.table : ViewMode.list);
  }
}

final viewModeProvider =
    StateNotifierProvider.family<ViewModeNotifier, ViewMode, String>((ref, pageKey) {
  final storage = ref.watch(storageServiceProvider);
  return ViewModeNotifier(storage: storage, pageKey: pageKey);
});

