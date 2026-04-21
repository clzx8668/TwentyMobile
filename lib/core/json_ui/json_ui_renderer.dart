import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pocketcrm/core/di/providers.dart';
import 'package:pocketcrm/core/json_ui/json_ui_node.dart';
import 'package:pocketcrm/core/view_mode/view_mode.dart';
import 'package:pocketcrm/core/view_mode/view_mode_provider.dart';
import 'package:pocketcrm/domain/models/company.dart';
import 'package:pocketcrm/domain/models/contact.dart';
import 'package:pocketcrm/domain/models/task.dart';
import 'package:pocketcrm/presentation/home/today_provider.dart';
import 'package:pocketcrm/presentation/home/widgets/recent_contacts_row.dart';
import 'package:pocketcrm/presentation/home/widgets/section_header.dart';
import 'package:pocketcrm/presentation/home/widgets/task_today_card.dart';
import 'package:pocketcrm/presentation/shared/error_state_widget.dart';
import 'package:pocketcrm/presentation/shared/empty_state_widget.dart';
import 'package:pocketcrm/presentation/shared/linked_contacts_widget.dart';
import 'package:pocketcrm/presentation/shared/snackbar_helper.dart';
import 'package:pocketcrm/presentation/shared/swipe_action_wrapper.dart';
import 'package:pocketcrm/presentation/shared/table/entity_table_columns.dart';
import 'package:pocketcrm/presentation/shared/table/table_columns_button.dart';
import 'package:pocketcrm/presentation/shared/table/table_view.dart';
import 'package:pocketcrm/presentation/shared/view_mode_toggle_button.dart';
import 'package:pocketcrm/presentation/tasks/task_sheets.dart';
import 'package:pocketcrm/presentation/shared/dynamic_fields/dynamic_field_descriptor.dart';
import 'package:pocketcrm/presentation/shared/dynamic_fields/dynamic_field_renderer.dart';
import 'package:pocketcrm/presentation/shared/dynamic_fields/entity_field_metadata.dart';
import 'package:pocketcrm/core/utils/demo_utils.dart';
import 'package:pocketcrm/core/table_columns/table_columns_override_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';

class JsonUiBuildContext {
  JsonUiBuildContext({
    required this.pageKey,
    this.scrollController,
  });

  final String pageKey;
  final ScrollController? scrollController;
}

typedef JsonUiWidgetBuilder = Widget Function(
  BuildContext context,
  WidgetRef ref,
  JsonUiNode node,
  JsonUiBuildContext ui,
);

class JsonUiRenderer {
  JsonUiRenderer({Map<String, JsonUiWidgetBuilder>? registry})
      : _registry = registry ?? _defaultRegistry;

  final Map<String, JsonUiWidgetBuilder> _registry;

  Widget render(
    BuildContext context,
    WidgetRef ref,
    JsonUiNode node,
    JsonUiBuildContext ui,
  ) {
    final builder = _registry[node.type];
    if (builder == null) {
      return Center(child: Text('Unknown component: ${node.type}'));
    }
    return builder(context, ref, node, ui);
  }
}

List<String> _stringList(dynamic v) {
  if (v is List) {
    return v.whereType<String>().toList(growable: false);
  }
  return const [];
}

List<String> _effectiveKeys(
  List<String> keys,
  List<String> availableKeys, {
  required int minCount,
  required List<String> fallback,
}) {
  final filtered = keys.where(availableKeys.contains).toList(growable: false);
  if (filtered.length >= minCount) return filtered;
  final fallbackFiltered =
      fallback.where(availableKeys.contains).toList(growable: false);
  if (fallbackFiltered.length >= minCount) return fallbackFiltered;
  return availableKeys.take(minCount).toList(growable: false);
}

final List<DynamicFieldDescriptor<Task>> _taskPreviewFields =
    EntityFieldMetadata.taskList
        .where((f) => f.key != 'dueAt')
        .toList(growable: false);

final Map<String, JsonUiWidgetBuilder> _defaultRegistry = {
  'entity_list': (context, ref, node, ui) {
    final entity = (node.props['entity'] as String?) ?? '';
    final columns = _stringList(node.props['tableColumns']);
    final overrideColumns = ref.watch(tableColumnsOverrideProvider(ui.pageKey));
    final availableKeys =
        tableColumnInfosForEntity(entity).map((e) => e.key).toList(growable: false);
    final mode = ref.watch(viewModeProvider(ui.pageKey));

    switch (entity) {
      case 'contacts':
        final async = ref.watch(contactsProvider);
        return async.when(
          data: (items) {
            final notifier = ref.read(contactsProvider.notifier);
            if (mode == ViewMode.table) {
              final effectiveKeys = _effectiveKeys(
                overrideColumns ?? (columns.isEmpty
                    ? const [
                        'name',
                        'company',
                        'jobTitle',
                        'city',
                        'email',
                        'phone',
                        'updatedAt',
                      ]
                    : columns),
                availableKeys,
                minCount: 2,
                fallback: columns.isEmpty
                    ? const [
                        'name',
                        'company',
                        'jobTitle',
                        'city',
                        'email',
                        'phone',
                        'updatedAt',
                      ]
                    : columns,
              );
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(contactsProvider);
                  await ref.read(contactsProvider.future);
                },
                child: Column(
                  children: [
                    Expanded(
                      child: TableView<Contact>(
                        columns: contactColumnsByKeys(
                          effectiveKeys,
                        ),
                        rows: items,
                        frozenColumnCount: 1,
                        enableSelection: true,
                        rowKeyGetter: (c) => c.id,
                        rowLeadingBuilder: (context, c) {
                          final full = '${c.firstName} ${c.lastName}'.trim();
                          final initials = full.isEmpty
                              ? ''
                              : full
                                  .split(RegExp(r'\s+'))
                                  .where((p) => p.isNotEmpty)
                                  .take(2)
                                  .map((p) => p[0].toUpperCase())
                                  .join();
                          if (initials.isNotEmpty) {
                            return CircleAvatar(
                              radius: 10,
                              child: Text(
                                initials,
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          }
                          return const Icon(Icons.person, size: 18);
                        },
                        onRowTap: (c) => context.push('/contacts/${c.id}'),
                        emptyMessage: 'No contacts',
                        minVisibleColumnCount: 2,
                        onColumnKeysChanged: (keys) => ref
                            .read(tableColumnsOverrideProvider(ui.pageKey).notifier)
                            .setOverride(keys),
                      ),
                    ),
                    if (notifier.hasNextPage)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: OutlinedButton.icon(
                          onPressed: () => notifier.loadMore(),
                          icon: const Icon(Icons.expand_more),
                          label: const Text('Load more'),
                        ),
                      ),
                  ],
                ),
              );
            }

            if (items.isEmpty) {
              return const EmptyStateWidget(
                icon: Icons.people_outline,
                title: 'No contacts',
                message: 'No results match your search.',
              );
            }

            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(contactsProvider);
                await ref.read(contactsProvider.future);
              },
              child: ListView.separated(
                controller: ui.scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: items.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemBuilder: (_, i) {
                  if (i == items.length) {
                    if (!notifier.hasNextPage) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: OutlinedButton.icon(
                          onPressed: () => notifier.loadMore(),
                          icon: const Icon(Icons.expand_more),
                          label: const Text('Load more'),
                        ),
                      ),
                    );
                  }
                  final c = items[i];
                  return ListTile(
                    title: Text('${c.firstName} ${c.lastName}'.trim()),
                    subtitle: Text(
                      [c.companyName, c.email]
                          .whereType<String>()
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                    ),
                    onTap: () => context.push('/contacts/${c.id}'),
                  );
                },
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorStateWidget(
            title: 'Loading error',
            message: e.toString().replaceAll('Exception: ', ''),
            onRetry: () => ref.invalidate(contactsProvider),
          ),
        );

      case 'companies':
        final async = ref.watch(companiesProvider);
        return async.when(
          data: (items) {
            if (mode == ViewMode.table) {
              final effectiveKeys = _effectiveKeys(
                overrideColumns ?? (columns.isEmpty
                    ? const [
                        'name',
                        'domain',
                        'industry',
                        'employees',
                        'linkedin',
                        'x',
                        'createdAt',
                      ]
                    : columns),
                availableKeys,
                minCount: 2,
                fallback: columns.isEmpty
                    ? const [
                        'name',
                        'domain',
                        'industry',
                        'employees',
                        'linkedin',
                        'x',
                        'createdAt',
                      ]
                    : columns,
              );
              return TableView<Company>(
                columns: companyColumnsByKeys(
                  effectiveKeys,
                ),
                rows: items,
                frozenColumnCount: 1,
                enableSelection: true,
                rowKeyGetter: (c) => c.id,
                rowLeadingBuilder: (context, c) {
                  final name = c.name.trim();
                  final initials = name.isEmpty
                      ? ''
                      : name
                          .split(RegExp(r'\s+'))
                          .where((p) => p.isNotEmpty)
                          .take(2)
                          .map((p) => p[0].toUpperCase())
                          .join();
                  if (initials.isNotEmpty) {
                    return CircleAvatar(
                      radius: 10,
                      child: Text(
                        initials,
                        style: const TextStyle(fontSize: 10),
                      ),
                    );
                  }
                  return const Icon(Icons.business, size: 18);
                },
                onRowTap: (c) => context.push('/companies/${c.id}'),
                emptyMessage: 'No companies',
                minVisibleColumnCount: 2,
                onColumnKeysChanged: (keys) => ref
                    .read(tableColumnsOverrideProvider(ui.pageKey).notifier)
                    .setOverride(keys),
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemBuilder: (_, i) {
                final c = items[i];
                return ListTile(
                  title: Text(c.name),
                  subtitle: Text([c.domainName, c.industry].whereType<String>().where((s) => s.isNotEmpty).join(' · ')),
                  onTap: () => context.push('/companies/${c.id}'),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorStateWidget(
            title: 'Loading error',
            message: e.toString().replaceAll('Exception: ', ''),
            onRetry: () => ref.invalidate(companiesProvider),
          ),
        );

      case 'tasks':
        final async = ref.watch(tasksProvider);
        final isShowingCompleted = ref.watch(taskFilterProvider);

        Future<void> refresh() async {
          ref.invalidate(tasksProvider);
          await ref.read(tasksProvider.future);
        }

        return async.when(
          data: (items) {
            if (mode == ViewMode.table) {
              final effectiveKeys = _effectiveKeys(
                overrideColumns ?? (columns.isEmpty
                    ? const ['title', 'status', 'dueAt', 'contact', 'createdAt']
                    : columns),
                availableKeys,
                minCount: 2,
                fallback: columns.isEmpty
                    ? const ['title', 'status', 'dueAt', 'contact', 'createdAt']
                    : columns,
              );
              if (items.isEmpty) {
                return RefreshIndicator(
                  onRefresh: refresh,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.7,
                      child: EmptyStateWidget(
                        icon: isShowingCompleted
                            ? Icons.task_alt
                            : Icons.checklist,
                        title:
                            isShowingCompleted ? 'No completed tasks' : 'All clear!',
                        message: isShowingCompleted
                            ? "You haven't checked any tasks yet."
                            : 'You have no pending tasks at the moment.',
                      ),
                    ),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: refresh,
                child: TableView<Task>(
                  columns: taskColumnsByKeys(
                    effectiveKeys,
                  ),
                  rows: items,
                  frozenColumnCount: 1,
                  enableSelection: true,
                  rowKeyGetter: (t) => t.id,
                  rowLeadingBuilder: (context, t) {
                    final title = t.title.trim();
                    final initials = title.isEmpty ? '' : title[0].toUpperCase();
                    if (initials.isNotEmpty) {
                      return CircleAvatar(
                        radius: 10,
                        child: Text(
                          initials,
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    }
                    return const Icon(Icons.checklist, size: 18);
                  },
                  onRowTap: (t) => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (_) => EditTaskSheet(task: t),
                  ),
                  emptyMessage: 'No tasks',
                  minVisibleColumnCount: 2,
                  onColumnKeysChanged: (keys) => ref
                      .read(tableColumnsOverrideProvider(ui.pageKey).notifier)
                      .setOverride(keys),
                ),
              );
            }

            if (items.isEmpty) {
              return RefreshIndicator(
                onRefresh: refresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: EmptyStateWidget(
                      icon: isShowingCompleted
                          ? Icons.task_alt
                          : Icons.checklist,
                      title: isShowingCompleted
                          ? 'No completed tasks'
                          : 'All clear!',
                      message: isShowingCompleted
                          ? "You haven't checked any tasks yet."
                          : 'You have no pending tasks at the moment.',
                    ),
                  ),
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: refresh,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemBuilder: (_, i) {
                  final task = items[i];
                  return SwipeActionWrapper(
                    itemKey: ValueKey('task_${task.id}'),
                    confirmTitle: 'Delete task',
                    confirmMessage: 'Do you want to delete \'${task.title}\'?',
                    onDelete: () async {
                      if (!await DemoUtils.checkDemoAction(context, ref)) return;
                      try {
                        await ref
                            .read(tasksProvider.notifier)
                            .deleteTask(task.id);
                        ref.invalidate(todayNotifierProvider);
                        if (context.mounted) {
                          SnackbarHelper.showSuccess(context, 'Task deleted');
                        }
                      } catch (_) {
                        if (context.mounted) {
                          SnackbarHelper.showError(
                              context, 'Error during deletion');
                        }
                      }
                    },
                    onEdit: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        builder: (_) => EditTaskSheet(task: task),
                      );
                    },
                    child: Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        leading: Transform.scale(
                          scale: 1.2,
                          child: Checkbox(
                            value: task.completed,
                            onChanged: (val) async {
                              if (!await DemoUtils.checkDemoAction(
                                  context, ref)) {
                                return;
                              }
                              if (val == null) return;
                              await ref
                                  .read(tasksProvider.notifier)
                                  .updateTask(task.id, completed: val);
                              if (context.mounted) {
                                SnackbarHelper.showSuccess(
                                  context,
                                  val ? 'Task completed' : 'Task restored',
                                );
                              }
                            },
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                        title: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 300),
                          style:
                              Theme.of(context).textTheme.titleMedium!.copyWith(
                                    decoration: task.completed == true
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: task.completed == true
                                        ? Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.color
                                        : Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.color,
                                  ),
                          child: Text(task.title),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Builder(
                                builder: (context) {
                                  if (task.dueAt == null) {
                                    return Text(
                                      'No deadline',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    );
                                  }

                                  var dateColor = Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.color;
                                  var dateWeight = FontWeight.w400;

                                  final now = DateTime.now();
                                  final today =
                                      DateTime(now.year, now.month, now.day);
                                  final dueDate = task.dueAt!.toLocal();
                                  final dueDay = DateTime(
                                      dueDate.year, dueDate.month, dueDate.day);
                                  final hasTime =
                                      dueDate.hour != 0 || dueDate.minute != 0;

                                  if (task.completed != true) {
                                    final difference =
                                        dueDay.difference(today).inDays;
                                    if (difference < 0 ||
                                        (difference == 0 &&
                                            hasTime &&
                                            dueDate.isBefore(now))) {
                                      dateColor = Theme.of(context)
                                          .colorScheme
                                          .error;
                                      dateWeight = FontWeight.w600;
                                    } else if (difference == 0 && !hasTime) {
                                      dateColor = Theme.of(context)
                                          .colorScheme
                                          .error;
                                      dateWeight = FontWeight.w600;
                                    } else if (difference <= 3) {
                                      dateColor = Colors.orange.shade700;
                                    }
                                  }

                                  final diffDays =
                                      dueDay.difference(today).inDays;
                                  String dateStr;
                                  if (diffDays == 0) {
                                    dateStr = 'Today';
                                  } else if (diffDays == 1) {
                                    dateStr = 'Tomorrow';
                                  } else {
                                    dateStr =
                                        '${dueDate.day.toString().padLeft(2, '0')}/${dueDate.month.toString().padLeft(2, '0')}';
                                  }

                                  final timeStr = hasTime
                                      ? ' · ${dueDate.hour.toString().padLeft(2, '0')}:${dueDate.minute.toString().padLeft(2, '0')}'
                                      : '';

                                  return FutureBuilder<SharedPreferences>(
                                    future: SharedPreferences.getInstance(),
                                    builder: (context, snapshot) {
                                      var hasNotification = false;
                                      if (snapshot.hasData) {
                                        hasNotification =
                                            snapshot.data!.getBool(
                                                    'task_notif_${task.id}') ??
                                                true;
                                      }

                                      return Row(
                                        children: [
                                          Icon(Icons.calendar_today,
                                              size: 14,
                                              color: task.completed == true
                                                  ? Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.color
                                                  : dateColor),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$dateStr$timeStr',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: task.completed == true
                                                      ? Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.color
                                                      : dateColor,
                                                  fontWeight: task.completed ==
                                                          true
                                                      ? FontWeight.w400
                                                      : dateWeight,
                                                ),
                                          ),
                                          if (hasTime && hasNotification) ...[
                                            const SizedBox(width: 4),
                                            Icon(
                                              Icons.notifications_active,
                                              size: 12,
                                              color: task.completed == true
                                                  ? Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.color
                                                  : dateColor,
                                            ),
                                          ],
                                        ],
                                      );
                                    },
                                  );
                                },
                              ),
                              const SizedBox(height: 6),
                              DynamicFieldRenderer(
                                entity: task,
                                descriptors: _taskPreviewFields,
                                maxLines: 2,
                                textStyle:
                                    Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 6),
                              LinkedContactsWidget(
                                entityId: task.id,
                                type: LinkedContactType.task,
                                isCompact: true,
                              ),
                            ],
                          ),
                        ),
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            shape: const RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.vertical(top: Radius.circular(20)),
                            ),
                            builder: (_) => EditTaskSheet(task: task),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorStateWidget(
            title: 'Loading error',
            message: e.toString().replaceAll('Exception: ', ''),
            onRetry: () => ref.invalidate(tasksProvider),
          ),
        );
    }

    return Center(child: Text('Unsupported entity: $entity'));
  },
  'home_today': (context, ref, node, ui) {
    final columns = _stringList(node.props['tableColumns']);
    final mode = ref.watch(viewModeProvider(ui.pageKey));
    final overrideColumns = ref.watch(tableColumnsOverrideProvider(ui.pageKey));
    final availableKeys = taskTableColumnInfos.map((e) => e.key).toList(growable: false);
    final todayState = ref.watch(todayNotifierProvider);

    return todayState.when(
      data: (data) {
        final hasOverdue = data.overdueTasks.isNotEmpty;
        final hasToday = data.todayTasks.isNotEmpty;
        final hasTomorrow = data.tomorrowTasks.isNotEmpty;
        final hasRecent = data.recentContacts.isNotEmpty;

        return RefreshIndicator(
          onRefresh: () => ref.read(todayNotifierProvider.notifier).refresh(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                floating: true,
                pinned: true,
                expandedHeight: 110.0,
                actions: [
                  ViewModeToggleButton(pageKey: ui.pageKey),
                  TableColumnsButton(
                    pageKey: ui.pageKey,
                    entity: 'tasks',
                    fallbackColumns: const ['title', 'status', 'dueAt', 'contact'],
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: () => context.push('/settings'),
                    tooltip: 'Settings',
                  ),
                ],
                flexibleSpace: LayoutBuilder(
                  builder: (context, constraints) {
                    final top = constraints.biggest.height;
                    final statusBarHeight = MediaQuery.of(context).padding.top;
                    final minHeight = kToolbarHeight + statusBarHeight;
                    final maxHeight = 110.0 + statusBarHeight;
                    final t =
                        ((top - minHeight) / (maxHeight - minHeight)).clamp(0.0, 1.0);

                    final userNameAsync = ref.watch(currentUserNameProvider);
                    final userName = userNameAsync.valueOrNull ?? 'User';

                    final now = DateTime.now();
                    final hour = now.hour;
                    var greeting = 'Good morning 👋  ';
                    if (hour >= 12 && hour < 18) {
                      greeting = 'Good afternoon 👋  ';
                    } else if (hour >= 18 && hour < 24) {
                      greeting = 'Good evening 👋  ';
                    } else if (hour >= 0 && hour < 5) {
                      greeting = 'Still awake? 👋  ';
                    }

                    final dateFormat = DateFormat('EEEE, d MMMM y', 'en_US');
                    final dateString = dateFormat.format(now);
                    final formattedDate = dateString.replaceFirst(
                        dateString[0], dateString[0].toUpperCase());

                    return Stack(
                      children: [
                        Positioned(
                          left: 20,
                          right: 20,
                          bottom: 16,
                          child: Stack(
                            alignment: Alignment.bottomLeft,
                            children: [
                              Opacity(
                                opacity: t,
                                child: Transform.translate(
                                  offset: Offset(0, 10 * (1 - t)),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        greeting,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        formattedDate,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withOpacity(0.6),
                                            ),
                                      ),
                                      if (userName.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          userName,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withOpacity(0.45),
                                              ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              Opacity(
                                opacity: 1 - t,
                                child: Transform.translate(
                                  offset: Offset(0, -10 * t),
                                  child: Text(
                                    formattedDate,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              if (mode == ViewMode.table)
                SliverList(
                  delegate: SliverChildListDelegate([
                    const SectionHeader(title: 'Tasks'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        height: 420,
                        child: TableView<Task>(
                          columns: taskColumnsByKeys(
                            _effectiveKeys(
                              overrideColumns ?? (columns.isEmpty
                                  ? const ['title', 'status', 'dueAt', 'contact']
                                  : columns),
                              availableKeys,
                              minCount: 2,
                              fallback: columns.isEmpty
                                  ? const ['title', 'status', 'dueAt', 'contact']
                                  : columns,
                            ),
                          ),
                          rows: <Task>[
                            ...data.overdueTasks,
                            ...data.todayTasks,
                            ...data.tomorrowTasks,
                          ],
                          frozenColumnCount: 1,
                          enableSelection: true,
                          rowKeyGetter: (t) => t.id,
                          rowLeadingBuilder: (context, t) {
                            final title = t.title.trim();
                            final initials =
                                title.isEmpty ? '' : title[0].toUpperCase();
                            if (initials.isNotEmpty) {
                              return CircleAvatar(
                                radius: 10,
                                child: Text(
                                  initials,
                                  style: const TextStyle(fontSize: 10),
                                ),
                              );
                            }
                            return const Icon(Icons.checklist, size: 18);
                          },
                          emptyMessage: 'No tasks',
                          minVisibleColumnCount: 2,
                          onColumnKeysChanged: (keys) => ref
                              .read(
                                tableColumnsOverrideProvider(ui.pageKey).notifier,
                              )
                              .setOverride(keys),
                          onRowTap: (t) => showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            shape: const RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.vertical(top: Radius.circular(20)),
                            ),
                            builder: (_) => EditTaskSheet(task: t),
                          ),
                        ),
                      ),
                    ),
                    if (hasRecent) ...[
                      const SectionHeader(title: 'Recent'),
                      RecentContactsRow(contacts: data.recentContacts),
                    ],
                    const SizedBox(height: 80),
                  ]),
                )
              else if (!hasOverdue && !hasToday && !hasTomorrow)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (hasRecent) ...[
                        const SectionHeader(title: 'Recent'),
                        RecentContactsRow(contacts: data.recentContacts),
                        const Spacer(),
                      ],
                      const Text('🎉', style: TextStyle(fontSize: 64)),
                      const SizedBox(height: 16),
                      Text(
                        'Everything is in order!',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No tasks due today',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          shape: const RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.vertical(top: Radius.circular(20)),
                          ),
                          builder: (_) => const AddTaskSheet(),
                        ),
                        child: const Text('Add task'),
                      ),
                      if (hasRecent) const Spacer(flex: 2),
                    ],
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildListDelegate([
                    if (hasOverdue) ...[
                      SectionHeader(
                        title: 'Overdue',
                        count: data.overdueTasks.length,
                        countColor: Theme.of(context).colorScheme.error,
                      ),
                      ...data.overdueTasks
                          .map((t) => TaskTodayCard(task: t, isOverdue: true)),
                    ],
                    SectionHeader(
                      title: 'Today',
                      count: data.todayTasks.length,
                    ),
                    if (hasToday)
                      ...data.todayTasks.map((t) => TaskTodayCard(task: t))
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Text('No tasks for today 🎉',
                            style: Theme.of(context).textTheme.bodyMedium),
                      ),
                    if (hasTomorrow) ...[
                      const SectionHeader(title: 'Tomorrow'),
                      ...data.tomorrowTasks.take(3).map(
                            (t) => Opacity(
                              opacity: 0.7,
                              child: TaskTodayCard(task: t),
                            ),
                          ),
                      if (data.tomorrowTasks.length > 3)
                        Padding(
                          padding: const EdgeInsets.only(left: 16, top: 8),
                          child: Text(
                            'and ${data.tomorrowTasks.length - 3} more...',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                    if (hasRecent) ...[
                      const SectionHeader(title: 'Recent'),
                      RecentContactsRow(contacts: data.recentContacts),
                    ],
                    const SizedBox(height: 80),
                  ]),
                ),
            ],
          ),
        );
      },
      loading: () => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Shimmer.fromColors(
          baseColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          highlightColor: Theme.of(context).colorScheme.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                  width: 100,
                  height: 20,
                  color: Colors.white,
                  margin: const EdgeInsets.only(top: 20, bottom: 8)),
              Container(
                  height: 70,
                  width: double.infinity,
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.symmetric(vertical: 4)),
              Container(
                  height: 70,
                  width: double.infinity,
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.symmetric(vertical: 4)),
              Container(
                  width: 100,
                  height: 20,
                  color: Colors.white,
                  margin: const EdgeInsets.only(top: 30, bottom: 8)),
              Row(
                children: List.generate(
                  4,
                  (index) => Container(
                    margin: const EdgeInsets.only(right: 12),
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      error: (e, _) => ErrorStateWidget(
        title: 'Loading error',
        message: e.toString().replaceAll('Exception: ', ''),
        onRetry: () => ref.read(todayNotifierProvider.notifier).refresh(),
      ),
    );
  },
  'home_dashboard': (context, ref, node, ui) {
    final columns = _stringList(node.props['tableColumns']);
    final mode = ref.watch(viewModeProvider(ui.pageKey));
    final overrideColumns = ref.watch(tableColumnsOverrideProvider(ui.pageKey));
    final availableKeys = taskTableColumnInfos.map((e) => e.key).toList(growable: false);
    final todayState = ref.watch(todayNotifierProvider);
    return todayState.when(
      data: (data) {
        final all = <Task>[...data.overdueTasks, ...data.todayTasks, ...data.tomorrowTasks];
        if (mode == ViewMode.table) {
          return TableView<Task>(
            columns: taskColumnsByKeys(
              _effectiveKeys(
                overrideColumns ??
                    (columns.isEmpty
                        ? const ['title', 'status', 'dueAt', 'contact']
                        : columns),
                availableKeys,
                minCount: 2,
                fallback: columns.isEmpty
                    ? const ['title', 'status', 'dueAt', 'contact']
                    : columns,
              ),
            ),
            rows: all,
            frozenColumnCount: 1,
            enableSelection: true,
            rowKeyGetter: (t) => t.id,
            rowLeadingBuilder: (context, t) {
              final title = t.title.trim();
              final initials = title.isEmpty ? '' : title[0].toUpperCase();
              if (initials.isNotEmpty) {
                return CircleAvatar(
                  radius: 10,
                  child: Text(
                    initials,
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              }
              return const Icon(Icons.checklist, size: 18);
            },
            emptyMessage: 'No tasks',
            minVisibleColumnCount: 2,
            onColumnKeysChanged: (keys) => ref
                .read(tableColumnsOverrideProvider(ui.pageKey).notifier)
                .setOverride(keys),
            onRowTap: (t) => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) => EditTaskSheet(task: t),
            ),
          );
        }

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (data.overdueTasks.isNotEmpty) ...[
              SectionHeader(title: 'Overdue', count: data.overdueTasks.length),
              ...data.overdueTasks.map((t) => TaskTodayCard(task: t, isOverdue: true)),
            ],
            SectionHeader(title: 'Today', count: data.todayTasks.length),
            ...data.todayTasks.map((t) => TaskTodayCard(task: t)),
            if (data.tomorrowTasks.isNotEmpty) ...[
              SectionHeader(title: 'Tomorrow', count: data.tomorrowTasks.length),
              ...data.tomorrowTasks.map((t) => TaskTodayCard(task: t)),
            ],
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorStateWidget(
        title: 'Loading error',
        message: e.toString().replaceAll('Exception: ', ''),
        onRetry: () => ref.read(todayNotifierProvider.notifier).refresh(),
      ),
    );
  },
};
