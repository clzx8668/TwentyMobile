import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketcrm/core/di/providers.dart';
import 'package:pocketcrm/core/json_ui/json_ui_node.dart';
import 'package:pocketcrm/core/ui_config/ui_config_service.dart';

final uiConfigServiceProvider = Provider<UiConfigService>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return UiConfigService(storage: storage);
});

final pageUiNodeProvider = FutureProvider.family<JsonUiNode, String>((ref, pageKey) async {
  final svc = ref.watch(uiConfigServiceProvider);
  final nodeJson = await svc.getPageNodeJson(pageKey);
  return JsonUiNode.fromJson(nodeJson);
});

