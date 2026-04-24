import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocketcrm/core/di/providers.dart';
import 'package:pocketcrm/core/utils/storage_service.dart';
import 'package:pocketcrm/presentation/shared/draggable_fab.dart';

class FakeStorageService implements StorageService {
  final Map<String, String> _values = {};

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

Widget _app({
  required StorageService storage,
  required String pageKey,
  required ValueNotifier<int> fabTapCount,
}) {
  return ProviderScope(
    overrides: [
      storageServiceProvider.overrideWithValue(storage),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: const SizedBox.expand(),
        floatingActionButton: DraggableFab(
          pageKey: pageKey,
          snapWithSpring: false,
          snapAnimationDuration: const Duration(milliseconds: 120),
          peekDelay: const Duration(seconds: 1),
          child: SizedBox(
            key: const Key('fab'),
            width: 56,
            height: 56,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => fabTapCount.value++,
              child: const ColoredBox(color: Colors.blue),
            ),
          ),
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
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;

  testWidgets('DraggableFab drag/snap/restore smoke on device', (tester) async {
    DraggableFab.resetSessionStateForTest();
    final storage = FakeStorageService();
    final fabTapCount = ValueNotifier<int>(0);
    await storage.write(
      key: DraggableFab.storageKeyGlobal,
      value: jsonEncode(<String, dynamic>{
        'v': 2,
        'side': 'l',
        'y': 1,
        'peek': false,
      }),
    );

    await tester.pumpWidget(
      _app(storage: storage, pageKey: 'p1', fabTapCount: fabTapCount),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    final fabFinder = find.byKey(const Key('fab'));

    final media = tester.widget<MediaQuery>(find.byType(MediaQuery).first).data;
    final screen = media.size;
    final padding = media.padding;
    final viewInsets = media.viewInsets;
    final margin = 16.0;
    final widgetSize = tester.getSize(fabFinder);
    final minX = padding.left + margin;
    final minY = padding.top + margin;
    final bottomSafe = screen.height - padding.bottom - viewInsets.bottom;
    final maxY = bottomSafe - margin - widgetSize.height;
    final initialTopLeft = tester.getTopLeft(fabFinder);
    expect(initialTopLeft.dx, lessThan(screen.width / 2));

    final raw = await storage.read(key: DraggableFab.storageKeyGlobal);
    expect(raw, isNotNull);
    final map = Map<String, dynamic>.from(jsonDecode(raw!) as Map);
    expect(map['v'], 2);

    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(fabFinder, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(fabTapCount.value, 0);

    await tester.tapAt(
      Offset(
        padding.left + 2,
        initialTopLeft.dy + widgetSize.height / 2,
      ),
    );
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(fabFinder, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(fabTapCount.value, 1);

    await tester.pumpWidget(
      _app(storage: storage, pageKey: 'p2', fabTapCount: fabTapCount),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(fabFinder, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(fabTapCount.value, 2);

    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(fabFinder, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(fabTapCount.value, 2);
  });
}
