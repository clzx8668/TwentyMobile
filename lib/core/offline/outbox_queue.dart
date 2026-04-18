import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:pocketcrm/core/offline/outbox_item.dart';

class OutboxQueue {
  OutboxQueue(this._box);

  final Box<String> _box;

  static const String _prefix = 'outbox:';
  static const String _orderKey = '${_prefix}order';

  static String _itemKey(String id) => '${_prefix}item:$id';

  Future<List<String>> _readOrder() async {
    final raw = _box.get(_orderKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map((e) => e.toString()).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeOrder(List<String> ids) async {
    await _box.put(_orderKey, jsonEncode(ids));
  }

  Future<OutboxItem?> getById(String id) async {
    final raw = _box.get(_itemKey(id));
    if (raw == null || raw.isEmpty) return null;
    try {
      return OutboxItem.fromJsonString(raw);
    } catch (_) {
      return null;
    }
  }

  Future<List<OutboxItem>> listAll() async {
    final order = await _readOrder();
    final items = <OutboxItem>[];
    for (final id in order) {
      final item = await getById(id);
      if (item != null) items.add(item);
    }
    return items;
  }

  Future<List<OutboxItem>> listPending() async {
    final all = await listAll();
    return all
        .where((i) => i.status == OutboxStatus.pending || i.status == OutboxStatus.failed)
        .toList(growable: false);
  }

  Future<List<OutboxItem>> listConflicts() async {
    final all = await listAll();
    return all.where((i) => i.status == OutboxStatus.conflict).toList(growable: false);
  }

  Future<void> upsert(OutboxItem item) async {
    await _box.put(_itemKey(item.operationId), item.toJsonString());
    final order = (await _readOrder()).toList(growable: true);
    if (!order.contains(item.operationId)) {
      order.add(item.operationId);
      await _writeOrder(order);
    }
  }

  Future<void> remove(String operationId) async {
    await _box.delete(_itemKey(operationId));
    final order = (await _readOrder()).toList(growable: true);
    order.remove(operationId);
    await _writeOrder(order);
  }

  Future<void> enqueue(OutboxItem item, {bool coalesce = true}) async {
    if (!coalesce) {
      await upsert(item);
      return;
    }

    final order = (await _readOrder()).toList(growable: true);
    for (int idx = order.length - 1; idx >= 0; idx--) {
      final existingId = order[idx];
      final existing = await getById(existingId);
      if (existing == null) continue;
      if (existing.entityType != item.entityType) continue;
      if (existing.entityId == null || item.entityId == null) continue;
      if (existing.entityId != item.entityId) continue;
      if (existing.status == OutboxStatus.processing) break;

      final merged = _tryCoalesce(existing, item);
      if (merged == null) {
        continue;
      }
      if (merged.isEmpty) {
        await remove(existing.operationId);
        return;
      }
      await upsert(merged.single);
      return;
    }

    await upsert(item);
  }

  List<OutboxItem>? _tryCoalesce(OutboxItem existing, OutboxItem incoming) {
    if (incoming.operation == OutboxOperation.update) {
      if (existing.operation == OutboxOperation.update) {
        return [
          existing.copyWith(
            payload: {...existing.payload, ...incoming.payload},
            retryCount: 0,
            status: OutboxStatus.pending,
            lastAttemptAt: null,
            lastError: null,
          ),
        ];
      }
      if (existing.operation == OutboxOperation.create) {
        return [
          existing.copyWith(
            payload: {...existing.payload, ...incoming.payload},
            retryCount: 0,
            status: OutboxStatus.pending,
            lastAttemptAt: null,
            lastError: null,
          ),
        ];
      }
    }

    if (incoming.operation == OutboxOperation.delete) {
      if (existing.operation == OutboxOperation.create) {
        return const [];
      }
      if (existing.operation == OutboxOperation.update) {
        return [
          existing.copyWith(
            operation: OutboxOperation.delete,
            payload: {...existing.payload, ...incoming.payload},
            retryCount: 0,
            status: OutboxStatus.pending,
            lastAttemptAt: null,
            lastError: null,
          ),
        ];
      }
    }

    return null;
  }

  Future<void> replaceIdsInPending({required String oldId, required String newId}) async {
    final order = (await _readOrder()).toList(growable: true);
    for (final opId in order) {
      final item = await getById(opId);
      if (item == null) continue;
      if (item.status == OutboxStatus.processing) continue;

      final updatedEntityId = item.entityId == oldId ? newId : item.entityId;
      final updatedPayload = _replaceIdsInObject(item.payload, oldId, newId);
      if (updatedEntityId == item.entityId && identical(updatedPayload, item.payload)) {
        continue;
      }

      await upsert(
        item.copyWith(
          entityId: updatedEntityId,
          payload: updatedPayload,
        ),
      );
    }
  }

  Map<String, dynamic> _replaceIdsInObject(
    Map<String, dynamic> input,
    String oldId,
    String newId,
  ) {
    bool changed = false;

    dynamic visit(dynamic value) {
      if (value is String) {
        if (value == oldId) {
          changed = true;
          return newId;
        }
        return value;
      }
      if (value is List) {
        final out = <dynamic>[];
        for (final e in value) {
          out.add(visit(e));
        }
        if (!changed) return value;
        return out;
      }
      if (value is Map) {
        final map = <String, dynamic>{};
        for (final entry in value.entries) {
          final k = entry.key.toString();
          final v = entry.value;
          if ((k == 'id' || k == 'contactId' || k == 'companyId') && v == oldId) {
            changed = true;
            map[k] = newId;
            continue;
          }
          map[k] = visit(v);
        }
        if (!changed) return value;
        return map;
      }
      return value;
    }

    final result = visit(input);
    if (!changed) return input;
    return Map<String, dynamic>.from(result as Map);
  }
}
