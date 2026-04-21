import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketcrm/core/router/navigator_key.dart';
import 'package:pocketcrm/presentation/shared/table/table_view.dart';

class _Row {
  const _Row(this.a, this.b, this.c);
  final String a;
  final String b;
  final String c;
}

void main() {
  Finder popupItemText(String text) {
    return find.byWidgetPredicate(
      (w) =>
          w is PopupMenuItem &&
          w.child is Text &&
          (w.child as Text).data == text,
    );
  }

  testWidgets('TableView header menu moveLeft persists one-step reorder', (tester) async {
    List<String>? received;

    final columns = <TableColumnDef<_Row>>[
      TableColumnDef<_Row>(
        key: 'a',
        label: 'A',
        width: 120,
        cellBuilder: (_, row) => Text(row.a),
      ),
      TableColumnDef<_Row>(
        key: 'b',
        label: 'B',
        width: 120,
        cellBuilder: (_, row) => Text(row.b),
      ),
      TableColumnDef<_Row>(
        key: 'c',
        label: 'C',
        width: 120,
        cellBuilder: (_, row) => Text(row.c),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: TableView<_Row>(
            columns: columns,
            rows: const [_Row('a1', 'b1', 'c1')],
            onColumnKeysChanged: (keys) async {
              received = keys;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    await tester.tap(popupItemText('左移'));
    await tester.pumpAndSettle();

    expect(received, ['b', 'a', 'c']);
  });

  testWidgets('TableView header menu moveRight persists one-step reorder', (tester) async {
    List<String>? received;

    final columns = <TableColumnDef<_Row>>[
      TableColumnDef<_Row>(
        key: 'a',
        label: 'A',
        width: 120,
        cellBuilder: (_, row) => Text(row.a),
      ),
      TableColumnDef<_Row>(
        key: 'b',
        label: 'B',
        width: 120,
        cellBuilder: (_, row) => Text(row.b),
      ),
      TableColumnDef<_Row>(
        key: 'c',
        label: 'C',
        width: 120,
        cellBuilder: (_, row) => Text(row.c),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: TableView<_Row>(
            columns: columns,
            rows: const [_Row('a1', 'b1', 'c1')],
            onColumnKeysChanged: (keys) async {
              received = keys;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    await tester.tap(popupItemText('右移'));
    await tester.pumpAndSettle();

    expect(received, ['a', 'c', 'b']);
  });

  testWidgets('TableView header menu hide persists when above minVisibleColumnCount', (tester) async {
    List<String>? received;

    final columns = <TableColumnDef<_Row>>[
      TableColumnDef<_Row>(
        key: 'a',
        label: 'A',
        width: 120,
        cellBuilder: (_, row) => Text(row.a),
      ),
      TableColumnDef<_Row>(
        key: 'b',
        label: 'B',
        width: 120,
        cellBuilder: (_, row) => Text(row.b),
      ),
      TableColumnDef<_Row>(
        key: 'c',
        label: 'C',
        width: 120,
        cellBuilder: (_, row) => Text(row.c),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: TableView<_Row>(
            columns: columns,
            rows: const [_Row('a1', 'b1', 'c1')],
            minVisibleColumnCount: 2,
            onColumnKeysChanged: (keys) async {
              received = keys;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    await tester.tap(popupItemText('隐藏'));
    await tester.pumpAndSettle();

    expect(received, ['a', 'c']);
    expect(find.textContaining('至少需要保留'), findsNothing);
  });

  testWidgets('TableView header menu hide is blocked at minVisibleColumnCount and shows info', (tester) async {
    var called = false;

    final columns = <TableColumnDef<_Row>>[
      TableColumnDef<_Row>(
        key: 'a',
        label: 'A',
        width: 120,
        cellBuilder: (_, row) => Text(row.a),
      ),
      TableColumnDef<_Row>(
        key: 'b',
        label: 'B',
        width: 120,
        cellBuilder: (_, row) => Text(row.b),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: TableView<_Row>(
            columns: columns,
            rows: const [_Row('a1', 'b1', 'c1')],
            minVisibleColumnCount: 2,
            onColumnKeysChanged: (_) async {
              called = true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    await tester.tap(popupItemText('隐藏'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.text('至少需要保留 2 列'), findsOneWidget);
  });
}

