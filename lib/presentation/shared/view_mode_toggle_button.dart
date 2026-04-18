import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketcrm/core/view_mode/view_mode.dart';
import 'package:pocketcrm/core/view_mode/view_mode_provider.dart';

class ViewModeToggleButton extends ConsumerWidget {
  const ViewModeToggleButton({
    super.key,
    required this.pageKey,
  });

  final String pageKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(viewModeProvider(pageKey));
    final isTable = mode == ViewMode.table;
    return IconButton(
      tooltip: isTable ? 'Switch to list' : 'Switch to table',
      icon: Icon(isTable ? Icons.view_agenda_outlined : Icons.table_chart_outlined),
      onPressed: () => ref.read(viewModeProvider(pageKey).notifier).toggle(),
    );
  }
}

