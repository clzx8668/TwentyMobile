import 'package:flutter/material.dart';

typedef TableCellBuilder<T> = Widget Function(BuildContext context, T row);

class TableColumnDef<T> {
  TableColumnDef({
    required this.key,
    required this.label,
    required this.cellBuilder,
    this.numeric = false,
  });

  final String key;
  final String label;
  final TableCellBuilder<T> cellBuilder;
  final bool numeric;
}

class TableView<T> extends StatelessWidget {
  const TableView({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.emptyMessage = 'No data',
  });

  final List<TableColumnDef<T>> columns;
  final List<T> rows;
  final void Function(T row)? onRowTap;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              columns: columns
                  .map(
                    (c) => DataColumn(
                      label: Text(
                        c.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      numeric: c.numeric,
                    ),
                  )
                  .toList(growable: false),
              rows: rows
                  .map(
                    (row) => DataRow(
                      onSelectChanged: onRowTap == null
                          ? null
                          : (_) => onRowTap!.call(row),
                      cells: columns
                          .map(
                            (c) => DataCell(c.cellBuilder(context, row)),
                          )
                          .toList(growable: false),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        );
      },
    );
  }
}

