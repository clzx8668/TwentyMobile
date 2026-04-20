import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketcrm/core/json_ui/json_ui_node.dart';
import 'package:pocketcrm/core/table_columns/table_columns_override_provider.dart';
import 'package:pocketcrm/core/ui_config/ui_config_providers.dart';
import 'package:pocketcrm/core/view_mode/view_mode.dart';
import 'package:pocketcrm/core/view_mode/view_mode_provider.dart';
import 'package:pocketcrm/presentation/shared/table/entity_table_columns.dart';

class TableColumnsButton extends ConsumerWidget {
  const TableColumnsButton({
    super.key,
    required this.pageKey,
    required this.entity,
    required this.fallbackColumns,
  });

  final String pageKey;
  final String entity;
  final List<String> fallbackColumns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(viewModeProvider(pageKey));
    if (mode != ViewMode.table) return const SizedBox.shrink();

    final availableInfos = tableColumnInfosForEntity(entity);
    final availableKeys = availableInfos
        .map((e) => e.key)
        .toList(growable: false);

    final uiNode = ref
        .watch(pageUiNodeProvider(pageKey))
        .maybeWhen(data: (n) => n, orElse: () => null);

    final defaultKeys = _defaultTableColumns(uiNode) ?? fallbackColumns;
    final overrideKeys = ref.watch(tableColumnsOverrideProvider(pageKey));
    final effectiveKeys = _effectiveKeys(
      overrideKeys ?? defaultKeys,
      availableKeys,
      minCount: 2,
      fallback: defaultKeys,
    );

    return IconButton(
      tooltip: 'Columns',
      icon: const Icon(Icons.view_column_outlined),
      onPressed: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (_) => _TableColumnsSheet(
            pageKey: pageKey,
            title: 'Columns',
            infos: availableInfos,
            selectedKeys: effectiveKeys,
            defaultKeys: defaultKeys,
          ),
        );
      },
    );
  }
}

List<String>? _defaultTableColumns(JsonUiNode? node) {
  if (node == null) return null;
  final v = node.props['tableColumns'];
  if (v is List) {
    return v.whereType<String>().toList(growable: false);
  }
  return null;
}

List<String> _effectiveKeys(
  List<String> keys,
  List<String> availableKeys, {
  required int minCount,
  required List<String> fallback,
}) {
  final filtered = keys.where(availableKeys.contains).toList(growable: false);
  if (filtered.length >= minCount) return filtered;
  final fallbackFiltered = fallback
      .where(availableKeys.contains)
      .toList(growable: false);
  if (fallbackFiltered.length >= minCount) return fallbackFiltered;
  return availableKeys.take(minCount).toList(growable: false);
}

class _TableColumnsSheet extends ConsumerStatefulWidget {
  const _TableColumnsSheet({
    required this.pageKey,
    required this.title,
    required this.infos,
    required this.selectedKeys,
    required this.defaultKeys,
  });

  final String pageKey;
  final String title;
  final List<TableColumnInfo> infos;
  final List<String> selectedKeys;
  final List<String> defaultKeys;

  @override
  ConsumerState<_TableColumnsSheet> createState() => _TableColumnsSheetState();
}

class _TableColumnsSheetState extends ConsumerState<_TableColumnsSheet> {
  late final Set<String> _selected;
  late final List<String> _orderedKeys;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedKeys.toSet();
    final availableKeys = widget.infos.map((e) => e.key).toSet();
    _orderedKeys = [
      ...widget.selectedKeys.where(availableKeys.contains),
      ...widget.infos.map((e) => e.key).where((k) => !_selected.contains(k)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final canApply = _selected.length >= 2;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await ref
                        .read(
                          tableColumnsOverrideProvider(widget.pageKey).notifier,
                        )
                        .clearOverride();
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                  },
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                itemCount: _orderedKeys.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final moved = _orderedKeys.removeAt(oldIndex);
                    _orderedKeys.insert(newIndex, moved);
                  });
                },
                itemBuilder: (_, i) {
                  final key = _orderedKeys[i];
                  final info = widget.infos.firstWhere((e) => e.key == key);
                  final checked = _selected.contains(info.key);
                  final isProtected = checked && _selected.length <= 2;
                  return ListTile(
                    key: ValueKey(info.key),
                    leading: Checkbox(
                      value: checked,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          if (v) {
                            _selected.add(info.key);
                          } else {
                            if (isProtected) return;
                            _selected.remove(info.key);
                          }
                        });
                      },
                    ),
                    title: Text(info.label),
                    subtitle: Text(info.key),
                    trailing: ReorderableDragStartListener(
                      index: i,
                      child: const Icon(Icons.drag_handle),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: !canApply
                  ? null
                  : () async {
                      final ordered = widget.infos
                          .map((e) => e.key)
                          .where(_selected.contains)
                          .toList(growable: false);
                      final orderedFromCurrent = _orderedKeys
                          .where(_selected.contains)
                          .toList(growable: false);
                      final effectiveOrdered =
                          orderedFromCurrent.length == ordered.length
                          ? orderedFromCurrent
                          : ordered;
                      await ref
                          .read(
                            tableColumnsOverrideProvider(
                              widget.pageKey,
                            ).notifier,
                          )
                          .setOverride(effectiveOrdered);
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                    },
              child: const Text('Apply'),
            ),
            if (!canApply)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'At least 2 columns are required.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
