import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketcrm/core/offline/outbox_item.dart';
import 'package:pocketcrm/core/offline/outbox_queue.dart';
import 'package:pocketcrm/core/di/auth_state.dart';
import 'package:pocketcrm/core/theme/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocketcrm/core/notifications/notification_service.dart';
import 'package:pocketcrm/core/di/providers.dart';
import 'package:pocketcrm/data/repositories/offline_first_crm_repository.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _notificationsEnabled = true;
  int _reminderAdvanceMinutes = 30;
  bool _syncing = false;
  String? _syncError;
  int _outboxPending = 0;
  int _outboxFailed = 0;
  int _outboxConflicts = 0;
  List<OutboxItem> _conflicts = const [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    unawaited(_loadOutboxStats());
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      _reminderAdvanceMinutes = prefs.getInt('reminder_advance_minutes') ?? 30;
    });
  }

  Future<void> _saveNotificationEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', value);
    setState(() {
      _notificationsEnabled = value;
    });

    if (value) {
      await NotificationService().requestPermission();
      final tasks = ref.read(tasksProvider).value;
      if (tasks != null) {
        await NotificationService().syncTaskNotifications(tasks);
      }
    } else {
      await NotificationService().cancelAll();
    }
  }

  Future<void> _saveReminderAdvance(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reminder_advance_minutes', value);
    setState(() {
      _reminderAdvanceMinutes = value;
    });

    if (_notificationsEnabled) {
      final tasks = ref.read(tasksProvider).value;
      if (tasks != null) {
        await NotificationService().syncTaskNotifications(tasks);
      }
    }
  }

  Future<void> _loadOutboxStats() async {
    try {
      final box = ref.read(hiveStorageBoxProvider);
      final queue = OutboxQueue(box);
      final items = await queue.listAll();
      final pending = items.where((i) => i.status == OutboxStatus.pending).length;
      final failed = items.where((i) => i.status == OutboxStatus.failed).length;
      final conflicts = items.where((i) => i.status == OutboxStatus.conflict).toList(growable: false);
      if (!mounted) return;
      setState(() {
        _outboxPending = pending;
        _outboxFailed = failed;
        _outboxConflicts = conflicts.length;
        _conflicts = conflicts;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _outboxPending = 0;
        _outboxFailed = 0;
        _outboxConflicts = 0;
        _conflicts = const [];
      });
    }
  }

  Future<void> _syncNow() async {
    setState(() {
      _syncing = true;
      _syncError = null;
    });
    try {
      final repo = await ref.read(crmRepositoryProvider.future);
      if (repo is OfflineFirstCRMRepository) {
        await repo.flushOutbox();
      }
      if (!mounted) return;
      setState(() {
        _syncing = false;
      });
      await _loadOutboxStats();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _syncError = e.toString();
      });
      await _loadOutboxStats();
    }
  }

  Future<void> _resolveConflictKeepLocal(OutboxItem item) async {
    try {
      final box = ref.read(hiveStorageBoxProvider);
      final queue = OutboxQueue(box);
      await queue.upsert(
        item.copyWith(
          status: OutboxStatus.pending,
          retryCount: 0,
          lastAttemptAt: null,
          lastError: null,
          payload: {
            ...item.payload,
            '_force': true,
          },
        ),
      );
      await _syncNow();
    } catch (_) {
      await _loadOutboxStats();
    }
  }

  Future<void> _resolveConflictUseRemote(OutboxItem item) async {
    try {
      final box = ref.read(hiveStorageBoxProvider);
      final queue = OutboxQueue(box);
      await queue.remove(item.operationId);
      switch (item.entityType) {
        case OutboxEntityType.contact:
          ref.invalidate(contactsProvider);
          break;
        case OutboxEntityType.company:
          ref.invalidate(companiesProvider);
          break;
        case OutboxEntityType.task:
          ref.invalidate(tasksProvider);
          break;
        case OutboxEntityType.note:
          break;
      }
      await _loadOutboxStats();
    } catch (_) {
      await _loadOutboxStats();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'Application Theme',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto),
                label: Text('System'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode),
                label: Text('Dark'),
              ),
            ],
            selected: {themeMode},
            onSelectionChanged: (Set<ThemeMode> newSelection) {
              ref.read(themeModeProvider.notifier).setTheme(newSelection.first);
            },
          ),
          const SizedBox(height: 32),
          const Text(
            'Notifications',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            title: const Text('Task reminders'),
            subtitle: const Text('Receive notification before due date'),
            trailing: Switch(
              value: _notificationsEnabled,
              onChanged: _saveNotificationEnabled,
            ),
          ),
          ListTile(
            title: const Text('Reminder advance'),
            trailing: DropdownButton<int>(
              value: _reminderAdvanceMinutes,
              items: const [
                DropdownMenuItem(value: 15, child: Text('15 minutes before')),
                DropdownMenuItem(value: 30, child: Text('30 minutes before')),
                DropdownMenuItem(value: 60, child: Text('1 hour before')),
              ],
              onChanged: _notificationsEnabled
                  ? (value) {
                      if (value != null) _saveReminderAdvance(value);
                    }
                  : null,
            ),
          ),
          const SizedBox(height: 48),
          const Divider(),
          const SizedBox(height: 16),
          const Text(
            'Sync',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Sync now'),
            subtitle: Text(
              'Outbox: pending=$_outboxPending failed=$_outboxFailed conflicts=$_outboxConflicts',
            ),
            trailing: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: _syncNow,
                  ),
          ),
          if (_syncError != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _syncError!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_conflicts.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Conflicts',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final item in _conflicts)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item.entityType.name}.${item.operation.name} id=${item.entityId ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (item.lastError != null && item.lastError!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(item.lastError!),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => _resolveConflictKeepLocal(item),
                            child: const Text('Keep local'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => _resolveConflictUseRemote(item),
                            child: const Text('Use remote'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 48),
          const Divider(),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              'Logout / Reset Token',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () {
              ref.read(authStateProvider.notifier).logout();
            },
          ),
          const SizedBox(height: 32),
          const Text(
            'Privacy & Terms',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.open_in_new, size: 20),
            onTap: () => launchUrl(Uri.parse('https://privacy.luciosoft.it/twentymobilecrm/')),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms of Use (EULA)'),
            trailing: const Icon(Icons.open_in_new, size: 20),
            onTap: () => launchUrl(Uri.parse('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/')),
          ),
        ],
      ),
    );
  }
}
