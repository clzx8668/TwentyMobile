import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketcrm/core/router/navigator_key.dart';
import 'package:pocketcrm/presentation/shared/table/table_view.dart';

class _Row {
  const _Row(this.name);
  final String name;
}

void main() {
  testWidgets('TableView filter sheet shows on filter icon tap', (tester) async {
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
            rows: const [_Row('Alice')],
            frozenColumnCount: 0,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.filter_alt_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.filter_alt_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Filter: Name'), findsOneWidget);
    expect(find.text('Contains'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);
  });
}

