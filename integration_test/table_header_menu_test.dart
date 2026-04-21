import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocketcrm/core/router/navigator_key.dart';
import 'package:pocketcrm/presentation/shared/table/table_view.dart';

class _Row {
  const _Row(this.a, this.b, this.c);
  final String a;
  final String b;
  final String c;
}

class _TableHarness extends StatefulWidget {
  const _TableHarness({required this.initialKeys, required this.minVisibleColumnCount});

  final List<String> initialKeys;
  final int minVisibleColumnCount;

  @override
  State<_TableHarness> createState() => _TableHarnessState();
}

class _TableHarnessState extends State<_TableHarness> {
  late List<String> _keys = List<String>.from(widget.initialKeys);

  List<TableColumnDef<_Row>> _buildColumns() {
    final defs = <String, TableColumnDef<_Row>>{
      'a': TableColumnDef<_Row>(
        key: 'a',
        label: 'ColA',
        width: 140,
        cellBuilder: (_, row) => Text(row.a, key: const ValueKey('cell-a')),
      ),
      'b': TableColumnDef<_Row>(
        key: 'b',
        label: 'ColB',
        width: 140,
        cellBuilder: (_, row) => Text(row.b, key: const ValueKey('cell-b')),
      ),
      'c': TableColumnDef<_Row>(
        key: 'c',
        label: 'ColC',
        width: 140,
        cellBuilder: (_, row) => Text(row.c, key: const ValueKey('cell-c')),
      ),
    };
    return _keys.map((k) => defs[k]!).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      home: Scaffold(
        body: SafeArea(
          child: TableView<_Row>(
            columns: _buildColumns(),
            rows: const [_Row('a1', 'b1', 'c1')],
            minVisibleColumnCount: widget.minVisibleColumnCount,
            onColumnKeysChanged: (next) async {
              setState(() {
                _keys = List<String>.from(next);
              });
            },
          ),
        ),
      ),
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder popupItemText(String text) {
    return find.byWidgetPredicate(
      (w) =>
          w is PopupMenuItem &&
          w.child is Text &&
          (w.child as Text).data == text,
    );
  }

  void expectHorizontalOrder(WidgetTester tester, List<String> labels) {
    final positions = <double>[];
    for (final label in labels) {
      final finder = find.text(label);
      expect(finder, findsOneWidget);
      positions.add(tester.getTopLeft(finder).dx);
    }
    for (var i = 1; i < positions.length; i++) {
      expect(positions[i], greaterThan(positions[i - 1]));
    }
  }

  testWidgets('Header menu can move and hide on Android without manual interaction', (tester) async {
    await tester.pumpWidget(const _TableHarness(
      initialKeys: ['a', 'b', 'c'],
      minVisibleColumnCount: 2,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ColB'));
    await tester.pumpAndSettle();
    await tester.tap(popupItemText('右移'));
    await tester.pumpAndSettle();

    expectHorizontalOrder(tester, const ['ColA', 'ColC', 'ColB']);

    await tester.tap(find.text('ColB'));
    await tester.pumpAndSettle();
    await tester.tap(popupItemText('隐藏'));
    await tester.pumpAndSettle();

    expect(find.text('ColB'), findsNothing);
    expectHorizontalOrder(tester, const ['ColA', 'ColC']);

    await tester.tap(find.text('ColC'));
    await tester.pumpAndSettle();
    await tester.tap(popupItemText('隐藏'));
    await tester.pumpAndSettle();

    expect(find.text('至少需要保留 2 列'), findsOneWidget);
    expect(find.text('ColC'), findsOneWidget);
  });
}

