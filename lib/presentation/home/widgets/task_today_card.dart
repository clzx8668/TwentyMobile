import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketcrm/domain/models/task.dart';
import 'package:pocketcrm/presentation/home/today_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocketcrm/presentation/shared/swipe_action_wrapper.dart';
import 'package:pocketcrm/presentation/tasks/task_sheets.dart';
import 'package:pocketcrm/presentation/shared/snackbar_helper.dart';
import 'package:pocketcrm/core/di/providers.dart';
import 'package:pocketcrm/core/utils/demo_utils.dart';

class TaskTodayCard extends ConsumerWidget {
  final Task task;
  final bool isOverdue;

  const TaskTodayCard({super.key, required this.task, this.isOverdue = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwipeActionWrapper(
      itemKey: ValueKey('today_task_${task.id}'),
      confirmTitle: 'Delete task',
      confirmMessage: 'Do you want to delete \'${task.title}\'?',
      onEdit: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (context) => EditTaskSheet(task: task),
        );
      },
      onDelete: () async {
        if (!await DemoUtils.checkDemoAction(context, ref)) return;
        try {
          await ref.read(tasksProvider.notifier).deleteTask(task.id);
          ref.invalidate(todayNotifierProvider);
          if (context.mounted) {
            SnackbarHelper.showSuccess(context, 'Task deleted');
          }
        } catch (e) {
          if (context.mounted) {
            SnackbarHelper.showError(context, 'Error during deletion');
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: BoxDecoration(
          color: isOverdue
            ? Theme.of(context).colorScheme.error.withOpacity(0.08)
            : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isOverdue
              ? Theme.of(context).colorScheme.error.withOpacity(0.3)
              : Theme.of(context).dividerColor,
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Transform.scale(
            scale: 1.2,
            child: Checkbox(
              value: task.completed ?? false,
              onChanged: (_) async {
                if (!await DemoUtils.checkDemoAction(context, ref)) return;
                ref.read(todayNotifierProvider.notifier).completeTask(task.id);
              },
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
          title: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            style: Theme.of(context).textTheme.titleMedium!.copyWith(
              decoration: (task.completed ?? false)
                ? TextDecoration.lineThrough
                : null,
              color: (task.completed ?? false)
                ? Theme.of(context).textTheme.bodySmall?.color
                : Theme.of(context).textTheme.titleMedium?.color,
            ),
            child: Text(task.title),
          ),
          subtitle: task.contactName != null ? Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Row(
              children: [
                Icon(Icons.person_outline, size: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                const SizedBox(width: 4),
                Text(task.contactName!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)
                  )),
              ],
            ),
          ) : null,
          trailing: task.dueAt != null ? _buildTrailing(context, task.dueAt!) : null,
        ),
      ),
    );
  }

  Widget _buildTrailing(BuildContext context, DateTime date) {
    final hasTime = date.hour != 0 || date.minute != 0;

    return FutureBuilder<SharedPreferences>(
      future: SharedPreferences.getInstance(),
      builder: (context, snapshot) {
        bool hasNotification = false;
        if (snapshot.hasData) {
          hasNotification = snapshot.data!.getBool('task_notif_${task.id}') ?? true;
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasTime && hasNotification) ...[
              Icon(
                Icons.notifications_active,
                size: 14,
                color: isOverdue ? Theme.of(context).colorScheme.error : null,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              _formatTime(date),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isOverdue ? Theme.of(context).colorScheme.error : null,
                fontWeight: isOverdue ? FontWeight.w600 : null,
              ),
            ),
          ],
        );
      }
    );
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final hasTime = date.hour != 0 || date.minute != 0;
    final diff = now.difference(date);

    if (isOverdue) {
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays > 1) return '${diff.inDays}d ago';
    }

    if (!hasTime) return 'Today';

    return '${date.hour.toString().padLeft(2,'0')}:${date.minute.toString().padLeft(2,'0')}';
  }
}
