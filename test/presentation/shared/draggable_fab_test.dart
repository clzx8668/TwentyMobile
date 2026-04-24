import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketcrm/core/di/providers.dart';
import 'package:pocketcrm/core/utils/storage_service.dart';
import 'package:pocketcrm/presentation/shared/draggable_fab.dart';

class FakeStorageService implements StorageService {
  final Map<String, String> _values;

  FakeStorageService([Map<String, String>? initial]) : _values = {...?initial};

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      _values.remove(key);
      return;
    }
    _values[key] = value;
  }

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _values.clear();
  }

  @override
  Future<void> debugDumpSecureStorage() async {}

  @override
  void debugDumpHive() {}
}

Widget _wrap({
  required StorageService storage,
  required String pageKey,
  DraggableFabController? controller,
  Duration peekDelay = const Duration(milliseconds: 3200),
  VoidCallback? onBodyTap,
  VoidCallback? onFabTap,
}) {
  return ProviderScope(
    overrides: [
      storageServiceProvider.overrideWithValue(storage),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onBodyTap,
                child: const SizedBox.expand(),
              ),
            ),
            DraggableFab(
              pageKey: pageKey,
              controller: controller,
              snapWithSpring: false,
              snapAnimationDuration: const Duration(milliseconds: 1),
              peekDelay: peekDelay,
              child: SizedBox(
                key: const Key('fab'),
                width: 56,
                height: 56,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onFabTap,
                  child: const ColoredBox(color: Colors.blue),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _longPressDragTo({
  required WidgetTester tester,
  required Finder finder,
  required Offset targetGlobal,
}) async {
  final start = tester.getCenter(finder);
  final gesture = await tester.startGesture(start);
  await tester.pump();
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 80));
  await tester.pump(const Duration(milliseconds: 16));

  final delta = targetGlobal - start;
  const steps = 8;
  for (var i = 1; i <= steps; i++) {
    await gesture.moveBy(delta / steps.toDouble());
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(DraggableFab.resetSessionStateForTest);

  group('DraggableFab', () {
    testWidgets('命中正确：移动后点击触发 FAB，不穿透到 body', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final storage = FakeStorageService();
      await storage.write(
        key: DraggableFab.storageKeyGlobal,
        value: jsonEncode({'v': 2, 'side': 'l', 'y': 0.5, 'peek': false}),
      );
      var bodyTaps = 0;
      var fabTaps = 0;
      await tester.pumpWidget(
        _wrap(
          storage: storage,
          pageKey: 'p1',
          onBodyTap: () => bodyTaps++,
          onFabTap: () => fabTaps++,
        ),
      );
      await tester.pumpAndSettle();

      final fabFinder = find.byKey(const Key('fab'));
      expect(fabFinder, findsOneWidget);

      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 16));

      final beforeCenter = tester.getCenter(fabFinder);
      final movedTarget = Offset(beforeCenter.dx, 120);
      await _longPressDragTo(
        tester: tester,
        finder: fabFinder,
        targetGlobal: movedTarget,
      );

      final afterCenter = tester.getCenter(fabFinder);
      expect((afterCenter.dy - beforeCenter.dy).abs(), greaterThan(20));

      await tester.tapAt(afterCenter);
      await tester.pumpAndSettle();

      expect(fabTaps, 1);
      expect(bodyTaps, 0);
    });

    testWidgets('从全局 key 恢复位置并吸附到边缘', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final storage = FakeStorageService();
      await storage.write(
        key: DraggableFab.storageKeyGlobal,
        value: jsonEncode({'v': 2, 'side': 'l', 'y': 0.5, 'peek': false}),
      );
      await tester.pumpWidget(_wrap(storage: storage, pageKey: 'p1'));
      await tester.pumpAndSettle();

      final fabFinder = find.byKey(const Key('fab'));
      final topLeft = tester.getTopLeft(fabFinder);
      final overlayFinder =
          find.ancestor(of: fabFinder, matching: find.byType(Overlay)).first;
      final overlayContext = tester.element(overlayFinder);
      final screen = tester.getSize(overlayFinder);
      final padding = MediaQuery.paddingOf(overlayContext);
      const margin = 16.0;
      final widgetSize = tester.getSize(fabFinder);
      final minX = padding.left + margin;
      final minY = padding.top + margin;
      final maxY = screen.height - padding.bottom - margin - widgetSize.height;

      expect(topLeft.dx, moreOrLessEquals(minX, epsilon: 0.5));
      expect(topLeft.dy, inInclusiveRange(minY, maxY));

      final raw = await storage.read(key: DraggableFab.storageKeyGlobal);
      expect(raw, isNotNull);
      final map = Map<String, dynamic>.from(jsonDecode(raw!) as Map);
      expect(map['v'], 2);
      expect(map['side'], 'l');
      expect(map['y'], isA<num>());
      expect(map['peek'], isA<bool>());
    });

    testWidgets('恢复时忽略 peek=true，进入页面默认完全可见并迁移持久化',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final storage = FakeStorageService();
      await storage.write(
        key: DraggableFab.storageKeyGlobal,
        value: jsonEncode({'v': 2, 'side': 'l', 'y': 0.5, 'peek': true}),
      );
      await tester.pumpWidget(_wrap(storage: storage, pageKey: 'p1'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 16));

      final fabFinder = find.byKey(const Key('fab'));
      final topLeft = tester.getTopLeft(fabFinder);
      final overlayFinder =
          find.ancestor(of: fabFinder, matching: find.byType(Overlay)).first;
      final overlayContext = tester.element(overlayFinder);
      final padding = MediaQuery.paddingOf(overlayContext);
      const margin = 16.0;
      final minX = padding.left + margin;
      expect(topLeft.dx, moreOrLessEquals(minX, epsilon: 0.5));

      final raw = await storage.read(key: DraggableFab.storageKeyGlobal);
      expect(raw, isNotNull);
      final map = Map<String, dynamic>.from(jsonDecode(raw!) as Map);
      expect(map['peek'], false);
    });

    testWidgets('peekDelay 到期后进入 peek；点击可唤醒回完全可见贴边状态',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final storage = FakeStorageService();
      await storage.write(
        key: DraggableFab.storageKeyGlobal,
        value: jsonEncode({'v': 2, 'side': 'l', 'y': 0.5, 'peek': false}),
      );
      var fabTaps = 0;
      await tester.pumpWidget(
        _wrap(
          storage: storage,
          pageKey: 'p1',
          peekDelay: const Duration(milliseconds: 800),
          onFabTap: () => fabTaps++,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));

      final fabFinder = find.byKey(const Key('fab'));
      final awakeTopLeft = tester.getTopLeft(fabFinder);

      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 16));

      final overlayFinder =
          find.ancestor(of: fabFinder, matching: find.byType(Overlay)).first;
      final overlayContext = tester.element(overlayFinder);
      final screen = tester.getSize(overlayFinder);
      final padding = MediaQuery.paddingOf(overlayContext);
      final isLeft = awakeTopLeft.dx < screen.width / 2;
      final edgeX =
          isLeft ? padding.left + 2 : screen.width - padding.right - 2;

      await tester.tapAt(tester.getCenter(fabFinder));
      await tester.pumpAndSettle();
      expect(fabTaps, 0);

      await tester.tapAt(
        Offset(
          edgeX,
          awakeTopLeft.dy + tester.getSize(fabFinder).height / 2,
        ),
      );
      await tester.pump(const Duration(milliseconds: 240));

      await tester.tapAt(tester.getCenter(fabFinder));
      await tester.pumpAndSettle();
      expect(fabTaps, 1);
    });

    testWidgets('全局位置可跨 pageKey 恢复', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final storage = FakeStorageService();
      await storage.write(
        key: DraggableFab.storageKeyGlobal,
        value: jsonEncode({'v': 2, 'side': 'l', 'y': 0.6, 'peek': false}),
      );
      await tester.pumpWidget(_wrap(storage: storage, pageKey: 'p1'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 16));

      final fabFinder = find.byKey(const Key('fab'));
      const margin = 16.0;
      final widgetSize = tester.getSize(fabFinder);
      final minX = margin;
      final minY = margin;
      final beforeTopLeft = tester.getTopLeft(fabFinder);

      await _longPressDragTo(
        tester: tester,
        finder: fabFinder,
        targetGlobal: Offset(minX + widgetSize.width / 2, minY + 40),
      );

      final snappedTopLeft = tester.getTopLeft(fabFinder);
      expect(snappedTopLeft.dx, moreOrLessEquals(minX, epsilon: 0.5));
      expect((snappedTopLeft.dy - beforeTopLeft.dy).abs(), greaterThan(20));
      await tester.pump();
      expect(await storage.read(key: DraggableFab.storageKeyGlobal), isNotNull);

      await tester.pumpWidget(_wrap(storage: storage, pageKey: 'p2'));
      await tester.pumpAndSettle();

      final restoredTopLeft = tester.getTopLeft(fabFinder);
      expect(restoredTopLeft.dx, moreOrLessEquals(snappedTopLeft.dx, epsilon: 0.5));
      expect(restoredTopLeft.dy, moreOrLessEquals(snappedTopLeft.dy, epsilon: 1));
    });

    testWidgets('迁移：首次读取时从 legacy per-page key 迁移到全局 key', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final storage = FakeStorageService();
      await storage.write(
        key: DraggableFab.storageKeyLegacyForPage('legacy'),
        value: jsonEncode({'dx': -9999, 'dy': -9999}),
      );

      await tester.pumpWidget(_wrap(storage: storage, pageKey: 'legacy'));
      await tester.pumpAndSettle();

      expect(await storage.read(key: DraggableFab.storageKeyGlobal), isNotNull);
      expect(
        await storage.read(key: DraggableFab.storageKeyLegacyForPage('legacy')),
        isNull,
      );
    });

    testWidgets('controller reset clears persisted position and restores default', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = DraggableFabController();
      final storage = FakeStorageService();
      await storage.write(
        key: DraggableFab.storageKeyGlobal,
        value: jsonEncode({'v': 2, 'side': 'l', 'y': 0.6, 'peek': false}),
      );

      await tester.pumpWidget(
        _wrap(storage: storage, pageKey: 'reset', controller: controller),
      );
      await tester.pumpAndSettle();

      final fabFinder = find.byKey(const Key('fab'));
      final baseTopLeft = tester.getTopLeft(fabFinder);
      final overlayFinder =
          find.ancestor(of: fabFinder, matching: find.byType(Overlay)).first;
      final overlayContext = tester.element(overlayFinder);
      final screen = tester.getSize(overlayFinder);
      final padding = MediaQuery.paddingOf(overlayContext);
      const margin = 16.0;
      final widgetSize = tester.getSize(fabFinder);
      final minX = padding.left + margin;
      final maxX = screen.width - padding.right - margin - widgetSize.width;
      final maxY = screen.height - padding.bottom - margin - widgetSize.height;

      expect(baseTopLeft.dx, moreOrLessEquals(minX, epsilon: 0.5));

      await controller.reset(animate: false);
      await tester.pumpAndSettle();

      final resetTopLeft = tester.getTopLeft(fabFinder);
      expect(resetTopLeft.dx, moreOrLessEquals(maxX, epsilon: 0.5));
      expect(resetTopLeft.dy, moreOrLessEquals(maxY, epsilon: 0.5));

      expect(await storage.read(key: DraggableFab.storageKeyGlobal), isNull);
    });
  });
}
