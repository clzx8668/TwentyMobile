import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketcrm/core/di/providers.dart';
import 'package:pocketcrm/core/utils/storage_service.dart';

class TableColumnsOverrideNotifier extends StateNotifier<List<String>?> {
  TableColumnsOverrideNotifier({
    required StorageService storage,
    required String pageKey,
  })  : _storage = storage,
        _pageKey = pageKey,
        super(null) {
    _init();
  }

  final StorageService _storage;
  final String _pageKey;

  String get _storageKey => 'table_columns:$_pageKey';

  Future<void> _init() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      state = _decode(raw);
    } catch (_) {}
  }

  Future<void> setOverride(List<String> keys) async {
    state = List<String>.from(keys);
    try {
      await _storage.write(key: _storageKey, value: jsonEncode(state));
    } catch (_) {}
  }

  Future<void> clearOverride() async {
    state = null;
    try {
      await _storage.delete(key: _storageKey);
    } catch (_) {}
  }
}

List<String>? _decode(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      final keys = decoded.whereType<String>().toList(growable: false);
      return keys.isEmpty ? null : keys;
    }
  } catch (_) {}
  return null;
}

final tableColumnsOverrideProvider =
    StateNotifierProvider.family<TableColumnsOverrideNotifier, List<String>?, String>(
  (ref, pageKey) {
    final storage = ref.watch(storageServiceProvider);
    return TableColumnsOverrideNotifier(storage: storage, pageKey: pageKey);
  },
);

