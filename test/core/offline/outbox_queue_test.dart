import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pocketcrm/core/offline/outbox_item.dart';
import 'package:pocketcrm/core/offline/outbox_queue.dart';

void main() {
  late Directory dir;
  late Box<String> box;
  late OutboxQueue queue;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('pocketcrm_outbox_');
    try {
      Hive.init(dir.path);
    } catch (_) {}
  });

  setUp(() async {
    box = await Hive.openBox<String>('outbox_queue_test_box');
    await box.clear();
    queue = OutboxQueue(box);
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk('outbox_queue_test_box');
  });

  tearDownAll(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('coalesce update merges into create', () async {
    await queue.enqueue(
      OutboxItem(
        operationId: 'op1',
        entityType: OutboxEntityType.contact,
        operation: OutboxOperation.create,
        entityId: 'tmp_1',
        payload: {'firstName': 'A'},
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    await queue.enqueue(
      OutboxItem(
        operationId: 'op2',
        entityType: OutboxEntityType.contact,
        operation: OutboxOperation.update,
        entityId: 'tmp_1',
        payload: {'lastName': 'B'},
        createdAt: DateTime(2026, 1, 1),
      ),
    );

    final all = await queue.listAll();
    expect(all.length, 1);
    expect(all.single.operation, OutboxOperation.create);
    expect(all.single.payload['firstName'], 'A');
    expect(all.single.payload['lastName'], 'B');
  });

  test('coalesce delete after create removes entry', () async {
    await queue.enqueue(
      OutboxItem(
        operationId: 'op1',
        entityType: OutboxEntityType.company,
        operation: OutboxOperation.create,
        entityId: 'tmp_2',
        payload: {'name': 'X'},
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    await queue.enqueue(
      OutboxItem(
        operationId: 'op2',
        entityType: OutboxEntityType.company,
        operation: OutboxOperation.delete,
        entityId: 'tmp_2',
        payload: const {},
        createdAt: DateTime(2026, 1, 1),
      ),
    );

    final all = await queue.listAll();
    expect(all, isEmpty);
  });

  test('coalesce delete after update replaces update', () async {
    await queue.enqueue(
      OutboxItem(
        operationId: 'op1',
        entityType: OutboxEntityType.task,
        operation: OutboxOperation.update,
        entityId: 't1',
        payload: {'title': 'A'},
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    await queue.enqueue(
      OutboxItem(
        operationId: 'op2',
        entityType: OutboxEntityType.task,
        operation: OutboxOperation.delete,
        entityId: 't1',
        payload: const {},
        createdAt: DateTime(2026, 1, 1),
      ),
    );

    final all = await queue.listAll();
    expect(all.length, 1);
    expect(all.single.operation, OutboxOperation.delete);
  });

  test('listConflicts returns only conflict items', () async {
    await queue.upsert(
      OutboxItem(
        operationId: 'op1',
        entityType: OutboxEntityType.contact,
        operation: OutboxOperation.update,
        entityId: 'c1',
        payload: {'firstName': 'A'},
        createdAt: DateTime(2026, 1, 1),
        status: OutboxStatus.conflict,
        lastError: 'conflict',
      ),
    );
    await queue.upsert(
      OutboxItem(
        operationId: 'op2',
        entityType: OutboxEntityType.contact,
        operation: OutboxOperation.update,
        entityId: 'c2',
        payload: {'firstName': 'B'},
        createdAt: DateTime(2026, 1, 1),
        status: OutboxStatus.pending,
      ),
    );

    final conflicts = await queue.listConflicts();
    expect(conflicts.length, 1);
    expect(conflicts.single.operationId, 'op1');
  });

  test('OutboxItem.fromJson handles unknown status', () {
    final item = OutboxItem.fromJson({
      'operationId': 'op1',
      'entityType': 'contact',
      'operation': 'update',
      'entityId': 'c1',
      'payload': {'a': 1},
      'status': 'unknown',
      'retryCount': 0,
      'createdAt': DateTime(2026, 1, 1).toIso8601String(),
    });
    expect(item.status, OutboxStatus.pending);
  });
}
