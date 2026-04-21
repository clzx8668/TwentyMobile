import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketcrm/core/router/navigator_key.dart';
import 'package:pocketcrm/presentation/shared/table/table_view.dart';

class _Row {
  const _Row(this.name);
  final String name;
}

void main() {
  testWidgets('TableView header menu sort changes row order and can clear', (tester) async {
    final columns = <TableColumnDef<_Row>>[
      TableColumnDef<_Row>(
        key: 'name',
        label: 'Name',
        width: 160,
        cellBuilder: (_, row) => Text(row.name, key: ValueKey('cell-${row.name}')),
        filterValueGetter: (row) => row.name,
        sortValueGetter: (row) => row.name,
      ),
    ];

    Future<void> openSortSubmenu() async {
      await tester.tap(find.text('Name'));
      await tester.pumpAndSettle();
      final sortItem = find.byWidgetPredicate(
        (w) => w is PopupMenuItem && w.child is Row,
      );
      expect(sortItem, findsOneWidget);
      await tester.tap(sortItem);
      await tester.pumpAndSettle();
    }

    Finder popupItemText(String text) {
      return find.byWidgetPredicate(
        (w) =>
            w is PopupMenuItem &&
            w.child is Text &&
            (w.child as Text).data == text,
      );
    }

    void expectVerticalOrder(List<String> names) {
      final positions = <double>[];
      for (final name in names) {
        final finder = find.byKey(ValueKey('cell-$name'));
        expect(finder, findsOneWidget);
        positions.add(tester.getTopLeft(finder).dy);
      }
      for (var i = 1; i < positions.length; i++) {
        expect(positions[i], greaterThan(positions[i - 1]));
      }
    }

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: TableView<_Row>(
            columns: columns,
            rows: const [_Row('Charlie'), _Row('Alice'), _Row('Bob')],
            frozenColumnCount: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expectVerticalOrder(const ['Charlie', 'Alice', 'Bob']);

    await openSortSubmenu();
    expect(popupItemText('升序'), findsOneWidget);
    await tester.tap(popupItemText('升序'));
    await tester.pumpAndSettle();
    expectVerticalOrder(const ['Alice', 'Bob', 'Charlie']);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward), findsNothing);

    await openSortSubmenu();
    expect(popupItemText('降序'), findsOneWidget);
    await tester.tap(popupItemText('降序'));
    await tester.pumpAndSettle();
    expectVerticalOrder(const ['Charlie', 'Bob', 'Alice']);
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);

    await openSortSubmenu();
    expect(popupItemText('清除'), findsOneWidget);
    await tester.tap(popupItemText('清除'));
    await tester.pumpAndSettle();
    expectVerticalOrder(const ['Charlie', 'Alice', 'Bob']);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
    expect(find.byIcon(Icons.arrow_downward), findsNothing);
  });
}

