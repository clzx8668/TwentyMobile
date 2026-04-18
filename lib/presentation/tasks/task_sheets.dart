import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketcrm/core/di/providers.dart';
import 'package:pocketcrm/core/notifications/notification_service.dart';
import 'package:pocketcrm/core/utils/demo_utils.dart';
import 'package:pocketcrm/domain/models/contact.dart';
import 'package:pocketcrm/domain/models/task.dart';
import 'package:pocketcrm/presentation/home/today_provider.dart';
import 'package:pocketcrm/presentation/shared/dialog_helper.dart';
import 'package:pocketcrm/presentation/shared/due_date_picker.dart';
import 'package:pocketcrm/presentation/shared/snackbar_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AddTaskSheet extends ConsumerStatefulWidget {
  const AddTaskSheet({super.key});

  @override
  ConsumerState<AddTaskSheet> createState() => AddTaskSheetState();
}

class AddTaskSheetState extends ConsumerState<AddTaskSheet> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _selectedContactId;
  DateTime? _selectedDueDate;

  bool _notifyReminder = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactsProvider);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'New Task',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'What needs to be done?',
                ),
                autofocus: true,
                enabled: !_isLoading,
                validator: (v) =>
                    v?.trim().isEmpty == true ? 'Please enter a title' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bodyController,
                decoration: const InputDecoration(
                  labelText: 'Details (optional)',
                  hintText: 'Add more context...',
                ),
                maxLines: 3,
                minLines: 1,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              contactsAsync.when(
                data: (contacts) => Autocomplete<Contact>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return const Iterable<Contact>.empty();
                    }
                    return contacts.where((Contact contact) {
                      final fullName =
                          '${contact.firstName} ${contact.lastName}'.toLowerCase();
                      return fullName
                          .contains(textEditingValue.text.toLowerCase());
                    });
                  },
                  displayStringForOption: (Contact option) =>
                      '${option.firstName} ${option.lastName}',
                  onSelected: (Contact selection) {
                    setState(() {
                      _selectedContactId = selection.id;
                    });
                  },
                  fieldViewBuilder:
                      (context, controller, focusNode, onEditingComplete) {
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      onEditingComplete: onEditingComplete,
                      enabled: !_isLoading,
                      decoration: const InputDecoration(
                        labelText: 'Search and link contact',
                        hintText: 'Start typing name...',
                      ),
                    );
                  },
                ),
                loading: () => const CircularProgressIndicator(),
                error: (err, stack) => Text('Contacts error: $err'),
              ),
              const SizedBox(height: 16),
              DueDatePicker(
                selectedDate: _selectedDueDate,
                onDateSelected: (date) =>
                    setState(() => _selectedDueDate = date),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: (_selectedDueDate != null &&
                        (_selectedDueDate!.hour != 0 ||
                            _selectedDueDate!.minute != 0))
                    ? SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Reminder notification'),
                        subtitle: Text(
                          _notifyReminder
                              ? '30 min before — ${_selectedDueDate!.hour.toString().padLeft(2, '0')}:${_selectedDueDate!.minute.toString().padLeft(2, '0')}'
                              : 'No notification',
                        ),
                        secondary: Icon(
                          _notifyReminder
                              ? Icons.notifications_active
                              : Icons.notifications_off,
                          color: _notifyReminder
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        value: _notifyReminder,
                        onChanged: (bool value) {
                          setState(() {
                            _notifyReminder = value;
                          });
                        },
                      )
                    : const SizedBox.shrink(),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                              color: Colors.red.shade700, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : () async {
                        setState(() {
                          _errorMessage = null;
                        });
                        if (!_formKey.currentState!.validate()) return;

                        setState(() {
                          _isLoading = true;
                        });

                        final navigator = Navigator.of(context);
                        try {
                          final newTask =
                              await ref.read(tasksProvider.notifier).addTask(
                                    _titleController.text.trim(),
                                    body: _bodyController.text.trim(),
                                    contactId: _selectedContactId,
                                    dueAt: _selectedDueDate,
                                  );

                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool(
                              'task_notif_${newTask.id}', _notifyReminder);

                          if (_selectedDueDate != null &&
                              (_selectedDueDate!.hour != 0 ||
                                  _selectedDueDate!.minute != 0) &&
                              _notifyReminder) {
                            NotificationService()
                                .scheduleTaskReminder(newTask);
                          } else {
                            NotificationService().cancelTaskReminder(newTask.id);
                          }

                          if (!context.mounted) return;
                          navigator.pop();
                          SnackbarHelper.showSuccess(
                              context, 'Task created successfully');
                        } catch (e) {
                          if (!mounted) return;
                          var errorMsg = e.toString();
                          if (errorMsg.contains('Exception:')) {
                            errorMsg =
                                errorMsg.replaceAll('Exception:', '').trim();
                          }
                          setState(() {
                            _isLoading = false;
                            _errorMessage = errorMsg;
                          });
                        }
                      },
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create Task'),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class EditTaskSheet extends ConsumerStatefulWidget {
  final Task task;
  const EditTaskSheet({super.key, required this.task});

  @override
  ConsumerState<EditTaskSheet> createState() => EditTaskSheetState();
}

class EditTaskSheetState extends ConsumerState<EditTaskSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  final _formKey = GlobalKey<FormState>();
  DateTime? _selectedDueDate;

  bool _notifyReminder = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _bodyController = TextEditingController(text: widget.task.bodyPlainText);
    _selectedDueDate = widget.task.dueAt?.toLocal();
    _loadNotificationPreference();
  }

  Future<void> _loadNotificationPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notifyReminder = prefs.getBool('task_notif_${widget.task.id}') ?? true;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Edit Task',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () async {
                      if (!await DemoUtils.checkDemoAction(context, ref)) {
                        return;
                      }
                      if (!context.mounted) return;

                      final confirm =
                          await DialogHelper.showDeleteConfirmDialog(
                        context: context,
                        title: 'Delete task',
                        message: 'Do you want to delete \'${widget.task.title}\'?',
                      );

                      if (!confirm || !context.mounted) return;
                      try {
                        await ref
                            .read(tasksProvider.notifier)
                            .deleteTask(widget.task.id);
                        ref.invalidate(todayNotifierProvider);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                          SnackbarHelper.showSuccess(context, 'Task deleted');
                        }
                      } catch (_) {
                        if (context.mounted) {
                          SnackbarHelper.showError(
                              context, 'Error during deletion');
                        }
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                ),
                autofocus: true,
                enabled: !_isLoading,
                validator: (v) =>
                    v?.trim().isEmpty == true ? 'Please enter a title' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bodyController,
                decoration: const InputDecoration(
                  labelText: 'Details (optional)',
                ),
                maxLines: 3,
                minLines: 1,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              DueDatePicker(
                selectedDate: _selectedDueDate,
                onDateSelected: (date) =>
                    setState(() => _selectedDueDate = date),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: (_selectedDueDate != null &&
                        (_selectedDueDate!.hour != 0 ||
                            _selectedDueDate!.minute != 0))
                    ? SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Reminder notification'),
                        subtitle: Text(
                          _notifyReminder
                              ? '30 min before — ${_selectedDueDate!.hour.toString().padLeft(2, '0')}:${_selectedDueDate!.minute.toString().padLeft(2, '0')}'
                              : 'No notification',
                        ),
                        secondary: Icon(
                          _notifyReminder
                              ? Icons.notifications_active
                              : Icons.notifications_off,
                          color: _notifyReminder
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        value: _notifyReminder,
                        onChanged: (bool value) {
                          setState(() {
                            _notifyReminder = value;
                          });
                        },
                      )
                    : const SizedBox.shrink(),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                              color: Colors.red.shade700, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : () async {
                        if (!await DemoUtils.checkDemoAction(context, ref)) {
                          return;
                        }
                        if (!context.mounted) return;
                        setState(() {
                          _errorMessage = null;
                        });
                        if (!_formKey.currentState!.validate()) return;

                        setState(() {
                          _isLoading = true;
                        });

                        final navigator = Navigator.of(context);

                        try {
                          final updatedTask =
                              await ref.read(tasksProvider.notifier).updateTask(
                                    widget.task.id,
                                    title: _titleController.text.trim(),
                                    body: _bodyController.text.trim(),
                                    dueAt: _selectedDueDate,
                                    clearDueDate: _selectedDueDate == null,
                                  );

                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('task_notif_${updatedTask.id}',
                              _notifyReminder);

                          if (updatedTask.dueAt != null &&
                              (updatedTask.dueAt!.hour != 0 ||
                                  updatedTask.dueAt!.minute != 0) &&
                              _notifyReminder) {
                            NotificationService()
                                .scheduleTaskReminder(updatedTask);
                          } else {
                            NotificationService()
                                .cancelTaskReminder(updatedTask.id);
                          }

                          if (!context.mounted) return;
                          navigator.pop();
                          SnackbarHelper.showSuccess(
                              context, 'Task updated successfully');
                        } catch (e) {
                          if (!mounted) return;
                          var errorMsg = e.toString();
                          if (errorMsg.contains('Exception:')) {
                            errorMsg =
                                errorMsg.replaceAll('Exception:', '').trim();
                          }
                          setState(() {
                            _isLoading = false;
                            _errorMessage = errorMsg;
                          });
                        }
                      },
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Changes'),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

