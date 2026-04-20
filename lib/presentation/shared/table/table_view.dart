import 'package:flutter/material.dart';

typedef TableCellBuilder<T> = Widget Function(BuildContext context, T row);
typedef TableFilterValueGetter<T> = String? Function(T row);
typedef TableSortValueGetter<T> = Comparable<dynamic>? Function(T row);
typedef TableRowKeyGetter<T> = String Function(T row);
typedef TableRowLeadingBuilder<T> = Widget Function(BuildContext context, T row);

const String _selectionColumnKey = '__select__';

enum TableFilterOp { contains, equals, startsWith }

extension on TableFilterOp {
  String get label => switch (this) {
        TableFilterOp.contains => 'Contains',
        TableFilterOp.equals => 'Equals',
        TableFilterOp.startsWith => 'Starts with',
      };

  String get hintText => switch (this) {
        TableFilterOp.contains => 'Contains…',
        TableFilterOp.equals => 'Equals…',
        TableFilterOp.startsWith => 'Starts with…',
      };
}

class TableColumnFilter {
  const TableColumnFilter({required this.op, required this.value});

  final TableFilterOp op;
  final String value;
}

class _ActiveFilter<T> {
  const _ActiveFilter({required this.column, required this.filter});

  final TableColumnDef<T> column;
  final TableColumnFilter filter;
}

enum _FilterSheetAction { apply, clear }

class _FilterSheetResult {
  const _FilterSheetResult.apply(this.filter) : action = _FilterSheetAction.apply;
  const _FilterSheetResult.clear()
      : action = _FilterSheetAction.clear,
        filter = null;

  final _FilterSheetAction action;
  final TableColumnFilter? filter;
}

class TableColumnDef<T> {
  TableColumnDef({
    required this.key,
    required this.label,
    required this.cellBuilder,
    this.numeric = false,
    this.width,
    this.filterValueGetter,
    this.sortValueGetter,
  });

  final String key;
  final String label;
  final TableCellBuilder<T> cellBuilder;
  final bool numeric;
  final double? width;
  final TableFilterValueGetter<T>? filterValueGetter;
  final TableSortValueGetter<T>? sortValueGetter;
}

class TableView<T> extends StatefulWidget {
  const TableView({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.emptyMessage = 'No data',
    this.frozenColumnCount = 0,
    this.enableSelection = false,
    this.rowKeyGetter,
    this.rowLeadingBuilder,
  });

  final List<TableColumnDef<T>> columns;
  final List<T> rows;
  final void Function(T row)? onRowTap;
  final String emptyMessage;
  final int frozenColumnCount;
  final bool enableSelection;
  final TableRowKeyGetter<T>? rowKeyGetter;
  final TableRowLeadingBuilder<T>? rowLeadingBuilder;

  @override
  State<TableView<T>> createState() => _TableViewState<T>();
}

class _TableViewState<T> extends State<TableView<T>> {
  static const _rowsPerPageOptions = <int>[10, 20, 50, 100];

  final _jumpController = TextEditingController();
  String? _sortColumnKey;
  bool _sortAscending = true;
  int _rowsPerPage = 20;
  int _pageIndex = 0;
  final Map<String, TableColumnFilter> _columnFilters = {};
  final Set<String> _selectedRowKeys = {};
  bool _filterSheetOpening = false;

  @override
  void dispose() {
    _jumpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cs = Theme.of(context).colorScheme;
        final effectiveColumns = _withSelectionColumn(widget.columns);
        final filteredSortedRows = _applyFilterAndSort(effectiveColumns, widget.rows);
        final total = filteredSortedRows.length;
        final pageCount = total == 0 ? 1 : ((total - 1) ~/ _rowsPerPage) + 1;
        final clampedPageIndex = _pageIndex.clamp(0, pageCount - 1).toInt();
        if (clampedPageIndex != _pageIndex) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _pageIndex = clampedPageIndex);
          });
        }

        final start = total == 0 ? 0 : (clampedPageIndex * _rowsPerPage) + 1;
        final end = total == 0
            ? 0
            : (start + _rowsPerPage - 1).clamp(1, total).toInt();
        final pagedRows = total == 0
            ? <T>[]
            : filteredSortedRows
                  .skip(clampedPageIndex * _rowsPerPage)
                  .take(_rowsPerPage)
                  .toList(growable: false);

        final effectiveFrozenCount = widget.frozenColumnCount.clamp(
          0,
          effectiveColumns.length,
        );

        Widget headerCell(TableColumnDef<T> c) => _buildHeaderCell(
              context,
              column: c,
              rowsOnPage: pagedRows,
            );

        final tableWidget = total == 0
            ? Center(
                child: Text(
                  widget.rows.isEmpty
                      ? widget.emptyMessage
                      : 'No matching rows',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              )
            : (effectiveFrozenCount > 0
                  ? _FrozenTableView<T>(
                      columns: effectiveColumns,
                      rows: pagedRows,
                      frozenColumnCount: effectiveFrozenCount,
                      onRowTap: widget.onRowTap,
                      headerCellBuilder: headerCell,
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                        ),
                        child: DataTableTheme(
                          data: DataTableThemeData(
                            dataTextStyle: TextStyle(color: cs.onSurface),
                            headingTextStyle: TextStyle(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: DataTable(
                            columns: effectiveColumns
                                .map(
                                  (c) => DataColumn(
                                    label: headerCell(c),
                                    numeric: c.numeric,
                                  ),
                                )
                                .toList(growable: false),
                            rows: pagedRows
                                .map(
                                  (row) => DataRow(
                                    onSelectChanged: widget.onRowTap == null
                                        ? null
                                        : (_) => widget.onRowTap!.call(row),
                                    cells: effectiveColumns
                                        .map(
                                          (c) => DataCell(
                                            DefaultTextStyle.merge(
                                              style: TextStyle(
                                                color: cs.onSurface,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              child: c.cellBuilder(
                                                context,
                                                row,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(growable: false),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        ),
                      ),
                    ));

        final hasAnyFilter = _columnFilters.values
            .any((f) => f.value.trim().isNotEmpty);

        return Column(
          children: [
            if (hasAnyFilter) ...[
              _buildActiveFiltersBar(context, effectiveColumns),
              const SizedBox(height: 8),
            ],
            Expanded(child: tableWidget),
            const SizedBox(height: 8),
            _buildFooter(
              context,
              total: total,
              start: start,
              end: end,
              pageCount: pageCount,
            ),
          ],
        );
      },
    );
  }

  List<T> _applyFilterAndSort(List<TableColumnDef<T>> columns, List<T> rows) {
    final Map<String, TableColumnDef<T>> columnMap = {
      for (final c in columns) c.key: c,
    };

    var result = rows
        .where((row) {
          bool matchesColumn(TableColumnDef<T> c, TableColumnFilter filter) {
            final raw = c.filterValueGetter?.call(row);
            if (raw == null) return false;
            final left = raw.trim().toLowerCase();
            final right = filter.value.trim().toLowerCase();
            if (right.isEmpty) return true;
            return switch (filter.op) {
              TableFilterOp.contains => left.contains(right),
              TableFilterOp.equals => left == right,
              TableFilterOp.startsWith => left.startsWith(right),
            };
          }

          for (final entry in _columnFilters.entries) {
            final key = entry.key;
            final filter = entry.value;
            if (filter.value.trim().isEmpty) continue;
            final col = columnMap[key];
            if (col == null || col.filterValueGetter == null) continue;
            if (!matchesColumn(col, filter)) return false;
          }
          return true;
        })
        .toList(growable: false);

    final sortColumn = _sortColumnKey == null
        ? null
        : columnMap[_sortColumnKey!];
    if (sortColumn != null) {
      result.sort((a, b) {
        final left = _extractSortValue(sortColumn, a);
        final right = _extractSortValue(sortColumn, b);
        final cmp = _compareValues(left, right);
        return _sortAscending ? cmp : -cmp;
      });
    }
    return result;
  }

  dynamic _extractSortValue(TableColumnDef<T> column, T row) {
    final value = column.sortValueGetter?.call(row);
    if (value != null) return value;
    final asFilterText = column.filterValueGetter?.call(row);
    if (asFilterText != null) return asFilterText.toLowerCase();
    return null;
  }

  int _compareValues(dynamic a, dynamic b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    if (a is Comparable && b is Comparable) {
      try {
        return a.compareTo(b);
      } catch (_) {}
    }
    return a.toString().compareTo(b.toString());
  }

  bool _hasFilter(String key) => (_columnFilters[key]?.value.trim().isNotEmpty ?? false);

  Widget _buildActiveFiltersBar(
    BuildContext context,
    List<TableColumnDef<T>> columns,
  ) {
    final cs = Theme.of(context).colorScheme;
    final active = <_ActiveFilter<T>>[];
    for (final c in columns) {
      if (c.key == _selectionColumnKey) continue;
      final f = _columnFilters[c.key];
      if (f == null) continue;
      if (f.value.trim().isEmpty) continue;
      active.add(_ActiveFilter<T>(column: c, filter: f));
    }
    if (active.isEmpty) return const SizedBox.shrink();

    String opLabel(TableFilterOp op) {
      return switch (op) {
        TableFilterOp.contains => 'contains',
        TableFilterOp.equals => '=',
        TableFilterOp.startsWith => 'starts',
      };
    }

    return Material(
      color: cs.surface,
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            const SizedBox(width: 12),
            const Icon(Icons.filter_alt_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: active.map((pair) {
                    final column = pair.column;
                    final filter = pair.filter;
                    final label =
                        '${column.label} ${opLabel(filter.op)} "${filter.value.trim()}"';
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InputChip(
                        label: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onPressed: () => _openFilterSheet(column),
                        onDeleted: () {
                          setState(() {
                            _columnFilters.remove(column.key);
                            _pageIndex = 0;
                          });
                        },
                      ),
                    );
                  }).toList(growable: false),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Clear all filters',
              onPressed: () {
                setState(() {
                  _columnFilters.clear();
                  _pageIndex = 0;
                });
              },
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  List<TableColumnDef<T>> _withSelectionColumn(List<TableColumnDef<T>> cols) {
    if (!widget.enableSelection || widget.rowKeyGetter == null) return cols;
    final leadingBuilder = widget.rowLeadingBuilder;
    return [
      TableColumnDef<T>(
        key: _selectionColumnKey,
        label: '',
        width: 46,
        cellBuilder: (context, row) {
          final key = widget.rowKeyGetter!(row);
          final selected = _selectedRowKeys.contains(key);
          final leading = leadingBuilder == null
              ? const Icon(Icons.circle, size: 16)
              : SizedBox(
                  width: 18,
                  height: 18,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: leadingBuilder(context, row),
                  ),
                );
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: selected,
                  visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedRowKeys.add(key);
                      } else {
                        _selectedRowKeys.remove(key);
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 2),
              leading,
            ],
          );
        },
      ),
      ...cols,
    ];
  }

  void _toggleSelectAllOnPage(List<T> rowsOnPage, bool selected) {
    if (!widget.enableSelection || widget.rowKeyGetter == null) return;
    setState(() {
      for (final row in rowsOnPage) {
        final key = widget.rowKeyGetter!(row);
        if (selected) {
          _selectedRowKeys.add(key);
        } else {
          _selectedRowKeys.remove(key);
        }
      }
    });
  }

  Future<void> _openFilterSheet(TableColumnDef<T> column) async {
    if (_filterSheetOpening) return;
    _filterSheetOpening = true;
    try {
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted) return;
      final result = await showModalBottomSheet<_FilterSheetResult?>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => _ColumnFilterSheet(
          title: 'Filter: ${column.label}',
          initialFilter: _columnFilters[column.key] ??
              const TableColumnFilter(
                op: TableFilterOp.contains,
                value: '',
              ),
        ),
      );
      if (!mounted) return;
      if (result == null) return;
      setState(() {
        switch (result.action) {
          case _FilterSheetAction.clear:
            _columnFilters.remove(column.key);
          case _FilterSheetAction.apply:
            final filter = result.filter!;
            if (filter.value.trim().isEmpty) {
              _columnFilters.remove(column.key);
            } else {
              _columnFilters[column.key] = filter;
            }
        }
        _pageIndex = 0;
      });
    } finally {
      _filterSheetOpening = false;
    }
  }

  Widget _buildHeaderCell(
    BuildContext context, {
    required TableColumnDef<T> column,
    required List<T> rowsOnPage,
  }) {
    final cs = Theme.of(context).colorScheme;
    if (column.key == _selectionColumnKey) {
      final enabled = widget.enableSelection && widget.rowKeyGetter != null;
      if (!enabled) return const SizedBox.shrink();
      final keysOnPage = rowsOnPage.map(widget.rowKeyGetter!).toList(growable: false);
      final selectedOnPage = keysOnPage.where(_selectedRowKeys.contains).length;
      final allSelected = keysOnPage.isNotEmpty && selectedOnPage == keysOnPage.length;
      final anySelected = selectedOnPage > 0;
      return SizedBox(
        width: 22,
        height: 22,
        child: Checkbox(
          value: allSelected ? true : (anySelected ? null : false),
          tristate: true,
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: (v) {
            _toggleSelectAllOnPage(rowsOnPage, v == true);
          },
        ),
      );
    }
    final isSorted = _sortColumnKey == column.key;
    final sortEnabled =
        column.sortValueGetter != null || column.filterValueGetter != null;
    final filterEnabled = column.filterValueGetter != null;
    final hasFilter = _hasFilter(column.key);

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 40),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              column.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
            ),
          ),
          const SizedBox(width: 4),
          if (filterEnabled)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              tooltip: hasFilter ? 'Filter (active)' : 'Filter',
              onPressed: () => _openFilterSheet(column),
              icon: Icon(
                hasFilter ? Icons.filter_alt : Icons.filter_alt_outlined,
                size: 16,
                color: hasFilter ? cs.primary : cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
          if (sortEnabled)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              tooltip: !isSorted
                  ? 'Sort'
                  : (_sortAscending ? 'Sort: ascending' : 'Sort: descending'),
              onPressed: () {
                setState(() {
                  if (!isSorted) {
                    _sortColumnKey = column.key;
                    _sortAscending = true;
                  } else if (_sortAscending) {
                    _sortAscending = false;
                  } else {
                    _sortColumnKey = null;
                    _sortAscending = true;
                  }
                  _pageIndex = 0;
                });
              },
              icon: Icon(
                !isSorted
                    ? Icons.unfold_more
                    : (_sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
                size: 16,
                color: isSorted ? cs.primary : cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFooter(
    BuildContext context, {
    required int total,
    required int start,
    required int end,
    required int pageCount,
  }) {
    final cs = Theme.of(context).colorScheme;
    final canPrev = _pageIndex > 0;
    final canNext = _pageIndex < pageCount - 1;

    void goToPage(int targetIndex) {
      final next = targetIndex.clamp(0, pageCount - 1);
      setState(() {
        _pageIndex = next;
      });
    }

    return Material(
      color: cs.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text('$start–$end of $total'),
            const SizedBox(width: 12),
            Text('${_pageIndex + 1} / $pageCount'),
            const SizedBox(width: 12),
            SizedBox(
              width: 92,
              height: 40,
              child: DropdownButtonFormField<int>(
                isDense: true,
                initialValue: _rowsPerPageOptions.contains(_rowsPerPage)
                    ? _rowsPerPage
                    : 20,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.view_list_outlined, size: 18),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                items: _rowsPerPageOptions
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                    .toList(growable: false),
                onChanged: (v) => setState(() {
                  _rowsPerPage = v ?? 20;
                  _pageIndex = 0;
                }),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'First page',
              onPressed: canPrev ? () => goToPage(0) : null,
              icon: const Icon(Icons.first_page),
            ),
            IconButton(
              tooltip: 'Previous page',
              onPressed: canPrev ? () => goToPage(_pageIndex - 1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Next page',
              onPressed: canNext ? () => goToPage(_pageIndex + 1) : null,
              icon: const Icon(Icons.chevron_right),
            ),
            IconButton(
              tooltip: 'Last page',
              onPressed: canNext ? () => goToPage(pageCount - 1) : null,
              icon: const Icon(Icons.last_page),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 84,
              height: 40,
              child: TextField(
                controller: _jumpController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: const OutlineInputBorder(),
                  hintText: 'Page',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                onSubmitted: (_) {
                  final target = int.tryParse(_jumpController.text.trim());
                  if (target == null) return;
                  goToPage(target - 1);
                },
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: 'Go',
              onPressed: () {
                final target = int.tryParse(_jumpController.text.trim());
                if (target == null) return;
                goToPage(target - 1);
              },
              icon: const Icon(Icons.arrow_forward, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColumnFilterSheet extends StatefulWidget {
  const _ColumnFilterSheet({
    required this.title,
    required this.initialFilter,
  });

  final String title;
  final TableColumnFilter initialFilter;

  @override
  State<_ColumnFilterSheet> createState() => _ColumnFilterSheetState();
}

class _ColumnFilterSheetState extends State<_ColumnFilterSheet> {
  late TableFilterOp _op;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _op = widget.initialFilter.op;
    _controller = TextEditingController(text: widget.initialFilter.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Material(
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 220),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: TableFilterOp.values
                        .map(
                          (op) => ChoiceChip(
                            label: Text(op.label),
                            selected: _op == op,
                            onSelected: (_) => setState(() => _op = op),
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _controller,
                    autofocus: false,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: cs.surfaceContainerHighest,
                      border: const OutlineInputBorder(),
                      hintText: _op.hintText,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(null),
                        child: const Text('Cancel'),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(
                          const _FilterSheetResult.clear(),
                        ),
                        child: const Text('Clear'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(
                          _FilterSheetResult.apply(
                            TableColumnFilter(
                              op: _op,
                              value: _controller.text,
                            ),
                          ),
                        ),
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FrozenTableView<T> extends StatefulWidget {
  const _FrozenTableView({
    required this.columns,
    required this.rows,
    required this.frozenColumnCount,
    required this.onRowTap,
    required this.headerCellBuilder,
  });

  final List<TableColumnDef<T>> columns;
  final List<T> rows;
  final int frozenColumnCount;
  final void Function(T row)? onRowTap;
  final Widget Function(TableColumnDef<T> column) headerCellBuilder;

  @override
  State<_FrozenTableView<T>> createState() => _FrozenTableViewState<T>();
}

class _FrozenTableViewState<T> extends State<_FrozenTableView<T>> {
  static const _rowHeight = 52.0;
  final _leftController = ScrollController();
  final _rightController = ScrollController();
  final _headerHorizontalController = ScrollController();
  final _bodyHorizontalController = ScrollController();
  bool _syncingV = false;
  bool _syncingH = false;

  @override
  void initState() {
    super.initState();
    _leftController.addListener(() => _sync(_leftController, _rightController));
    _rightController.addListener(
      () => _sync(_rightController, _leftController),
    );
    _headerHorizontalController.addListener(
      () => _syncH(_headerHorizontalController, _bodyHorizontalController),
    );
    _bodyHorizontalController.addListener(
      () => _syncH(_bodyHorizontalController, _headerHorizontalController),
    );
  }

  void _sync(ScrollController from, ScrollController to) {
    if (_syncingV) return;
    if (!from.hasClients || !to.hasClients) return;
    final offset = from.offset;
    if (offset == to.offset) return;
    _syncingV = true;
    to.jumpTo(
      offset.clamp(to.position.minScrollExtent, to.position.maxScrollExtent),
    );
    _syncingV = false;
  }

  void _syncH(ScrollController from, ScrollController to) {
    if (_syncingH) return;
    if (!from.hasClients || !to.hasClients) return;
    final offset = from.offset;
    if (offset == to.offset) return;
    _syncingH = true;
    to.jumpTo(
      offset.clamp(to.position.minScrollExtent, to.position.maxScrollExtent),
    );
    _syncingH = false;
  }

  @override
  void dispose() {
    _leftController.dispose();
    _rightController.dispose();
    _headerHorizontalController.dispose();
    _bodyHorizontalController.dispose();
    super.dispose();
  }

  double _colWidth(TableColumnDef<T> c) => c.width ?? 160;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: cs.onSurface);
    final headerStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: cs.onSurface,
      fontWeight: FontWeight.w700,
    );

    final frozen = widget.columns
        .take(widget.frozenColumnCount)
        .toList(growable: false);
    final scrollable = widget.columns
        .skip(widget.frozenColumnCount)
        .toList(growable: false);
    final leftWidth = frozen.fold<double>(0, (sum, c) => sum + _colWidth(c));
    final rightWidth = scrollable.fold<double>(
      0,
      (sum, c) => sum + _colWidth(c),
    );

    Widget headerCell(TableColumnDef<T> c) {
      final padding = c.key == _selectionColumnKey
          ? const EdgeInsets.symmetric(horizontal: 0, vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 10);
      return SizedBox(
        width: _colWidth(c),
        child: Padding(
          padding: padding,
          child: DefaultTextStyle.merge(
            style: headerStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: widget.headerCellBuilder(c),
          ),
        ),
      );
    }

    Widget dataCell(TableColumnDef<T> c, T row) {
      final padding = c.key == _selectionColumnKey
          ? const EdgeInsets.symmetric(horizontal: 0, vertical: 6)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
      return SizedBox(
        width: _colWidth(c),
        child: Padding(
          padding: padding,
          child: DefaultTextStyle.merge(
            style: textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: Align(
              alignment: Alignment.centerLeft,
              child: c.cellBuilder(context, row),
            ),
          ),
        ),
      );
    }

    Widget rowDivider() =>
        Divider(height: 1, thickness: 1, color: cs.outlineVariant);

    return Column(
      children: [
        Material(
          color: cs.surfaceContainerHighest,
          child: Row(
            children: [
              SizedBox(
                width: leftWidth,
                child: Row(
                  children: frozen.map(headerCell).toList(growable: false),
                ),
              ),
              if (scrollable.isNotEmpty)
                Expanded(
                  child: SingleChildScrollView(
                    controller: _headerHorizontalController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: rightWidth,
                      child: Row(
                        children: scrollable
                            .map(headerCell)
                            .toList(growable: false),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        rowDivider(),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: leftWidth,
                child: ListView.separated(
                  controller: _leftController,
                  itemCount: widget.rows.length,
                  separatorBuilder: (context, index) => rowDivider(),
                  itemBuilder: (context, i) {
                    final row = widget.rows[i];
                    return SizedBox(
                      height: _rowHeight,
                      child: InkWell(
                        onTap: widget.onRowTap == null
                            ? null
                            : () => widget.onRowTap!(row),
                        child: Row(
                          children: frozen
                              .map((c) => dataCell(c, row))
                              .toList(growable: false),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (scrollable.isNotEmpty)
                Expanded(
                  child: SingleChildScrollView(
                    controller: _bodyHorizontalController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: rightWidth,
                      child: ListView.separated(
                        controller: _rightController,
                        itemCount: widget.rows.length,
                        separatorBuilder: (context, index) => rowDivider(),
                        itemBuilder: (context, i) {
                          final row = widget.rows[i];
                          return SizedBox(
                            height: _rowHeight,
                            child: InkWell(
                              onTap: widget.onRowTap == null
                                  ? null
                                  : () => widget.onRowTap!(row),
                              child: Row(
                                children: scrollable
                                    .map((c) => dataCell(c, row))
                                    .toList(growable: false),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
