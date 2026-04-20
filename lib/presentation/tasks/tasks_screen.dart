import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketcrm/core/di/providers.dart';
import 'package:pocketcrm/core/json_ui/json_ui_node.dart';
import 'package:pocketcrm/core/json_ui/json_ui_renderer.dart';
import 'package:pocketcrm/core/notifications/notification_service.dart';
import 'package:pocketcrm/core/utils/demo_utils.dart';
import 'package:pocketcrm/presentation/shared/json_ui_host.dart';
import 'package:pocketcrm/presentation/shared/table/table_columns_button.dart';
import 'package:pocketcrm/presentation/shared/view_mode_toggle_button.dart';
import 'package:pocketcrm/presentation/tasks/task_sheets.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  @override
  Widget build(BuildContext context) {
    ref.listen(tasksProvider, (previous, next) {
      next.whenData((tasks) {
        NotificationService().syncTaskNotifications(tasks);

        final now = DateTime.now();
        final overdueCount = tasks
            .where((t) =>
                t.dueAt != null && t.dueAt!.isBefore(now) && t.completed != true)
            .length;
        if (overdueCount > 0) {
          NotificationService().scheduleOvernightSummary(overdueCount);
        }
      });
    });

    final isShowingCompleted = ref.watch(taskFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isShowingCompleted ? Icons.task_alt : Icons.history,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              isShowingCompleted ? 'Completed Tasks' : 'Recent Tasks',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              isShowingCompleted
                  ? Icons.check_box
                  : Icons.check_box_outline_blank,
            ),
            onPressed: () {
              ref.read(taskFilterProvider.notifier).toggle();
            },
            tooltip: 'Filter completed',
          ),
          const ViewModeToggleButton(pageKey: 'tasks'),
          const TableColumnsButton(
            pageKey: 'tasks',
            entity: 'tasks',
            fallbackColumns: [
              'title',
              'status',
              'dueAt',
              'contact',
              'createdAt',
            ],
          ),
        ],
      ),
      body: JsonUiHost(
        pageKey: 'tasks',
        ui: JsonUiBuildContext(pageKey: 'tasks'),
        fallbackNode: JsonUiNode(
          type: 'entity_list',
          props: {
            'entity': 'tasks',
            'tableColumns': const [
              'title',
              'status',
              'dueAt',
              'contact',
              'createdAt',
            ],
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          if (!await DemoUtils.checkDemoAction(context, ref)) return;
          if (!context.mounted) return;
          _showAddTaskDialog(context);
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddTaskDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const AddTaskSheet(),
    );
  }
}

