import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketcrm/core/router/navigator_key.dart';
import 'package:pocketcrm/presentation/shared/table/table_view.dart';

class _Row {
  const _Row(this.name);
  final String name;
}

void main() {
  testWidgets('TableView filter sheet opens from header menu and can apply/clear', (tester) async {
    final columns = <TableColumnDef<_Row>>[
      TableColumnDef<_Row>(
        key: 'name',
        label: 'Name',
        width: 160,
        cellBuilder: (_, row) => Text(row.name),
        filterValueGetter: (row) => row.name,
        sortValueGetter: (row) => row.name,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: TableView<_Row>(
            columns: columns,
            rows: const [_Row('Alice'), _Row('Bob')],
            frozenColumnCount: 0,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.filter_alt_outlined), findsNothing);

    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('过滤'));
    await tester.pumpAndSettle();

    expect(find.text('Filter: Name'), findsOneWidget);
    expect(find.text('Contains'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);

    final filterField = find.byWidgetPredicate(
      (w) => w is TextField && w.keyboardType != TextInputType.number,
    );
    await tester.enterText(filterField, 'ali');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsNothing);
    expect(find.byIcon(Icons.filter_alt_outlined), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints?.minWidth == 6 &&
            w.constraints?.maxWidth == 6 &&
            w.constraints?.minHeight == 6 &&
            w.constraints?.maxHeight == 6 &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle,
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('过滤'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.byIcon(Icons.filter_alt_outlined), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints?.minWidth == 6 &&
            w.constraints?.maxWidth == 6 &&
            w.constraints?.minHeight == 6 &&
            w.constraints?.maxHeight == 6 &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle,
      ),
      findsNothing,
    );
  });
}
