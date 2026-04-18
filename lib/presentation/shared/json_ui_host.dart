import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketcrm/core/json_ui/json_ui_node.dart';
import 'package:pocketcrm/core/json_ui/json_ui_renderer.dart';
import 'package:pocketcrm/core/ui_config/ui_config_providers.dart';
import 'package:pocketcrm/presentation/shared/error_state_widget.dart';

class JsonUiHost extends ConsumerWidget {
  const JsonUiHost({
    super.key,
    required this.pageKey,
    required this.ui,
    required this.fallbackNode,
  });

  final String pageKey;
  final JsonUiBuildContext ui;
  final JsonUiNode fallbackNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncNode = ref.watch(pageUiNodeProvider(pageKey));
    final renderer = JsonUiRenderer();

    return asyncNode.when(
      data: (node) => renderer.render(context, ref, node, ui),
      loading: () => renderer.render(context, ref, fallbackNode, ui),
      error: (e, _) => ErrorStateWidget(
        title: 'UI config error',
        message: e.toString().replaceAll('Exception: ', ''),
        onRetry: () => ref.invalidate(pageUiNodeProvider(pageKey)),
      ),
    );
  }
}

