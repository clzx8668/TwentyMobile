import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:pocketcrm/core/json_ui/json_ui_node.dart';
import 'package:pocketcrm/core/json_ui/json_ui_renderer.dart';
import 'package:pocketcrm/core/utils/platform_utils.dart';
import 'package:pocketcrm/presentation/contacts/contacts_screen.dart';
import 'package:pocketcrm/presentation/scan/scan_card_screen.dart';
import 'package:pocketcrm/presentation/shared/json_ui_host.dart';
import 'package:pocketcrm/presentation/tasks/task_sheets.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      floatingActionButton: SpeedDial(
        icon: Icons.add,
        activeIcon: Icons.close,
        spacing: 3,
        childPadding: const EdgeInsets.all(5),
        spaceBetweenChildren: 4,
        tooltip: 'Add',
        heroTag: 'speed-dial-hero-tag',
        elevation: 8.0,
        animationCurve: Curves.easeOutCubic,
        isOpenOnStart: false,
        label: const Text('New'),
        children: [
          SpeedDialChild(
            child: const Icon(Icons.document_scanner),
            backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onTertiaryContainer,
            label: 'Scan business card',
            onTap: () {
              if (!PlatformUtils.supportsScan) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('📱 Only available on iPhone and Android'),
                  ),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScanCardScreen()),
              );
            },
          ),
          SpeedDialChild(
            child: const Icon(Icons.person_add),
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
            label: 'New contact',
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) => const AddContactSheet(),
            ),
          ),
          SpeedDialChild(
            child: const Icon(Icons.add_task),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            label: 'New quick task',
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) => const AddTaskSheet(),
            ),
          ),
        ],
      ),
      body: JsonUiHost(
        pageKey: 'home',
        ui: JsonUiBuildContext(pageKey: 'home'),
        fallbackNode: JsonUiNode(
          type: 'home_today',
          props: {
            'tableColumns': const ['title', 'status', 'dueAt', 'contact'],
          },
        ),
      ),
    );
  }
}

