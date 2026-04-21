import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:pocketcrm/core/offline/outbox_item.dart';
import 'package:pocketcrm/core/offline/outbox_queue.dart';
import 'package:pocketcrm/core/utils/entity_cache.dart';
import 'package:pocketcrm/domain/models/company.dart';
import 'package:pocketcrm/domain/models/contact.dart';
import 'package:pocketcrm/domain/models/note.dart';
import 'package:pocketcrm/domain/models/task.dart';
import 'package:pocketcrm/domain/repositories/crm_repository.dart';

class _OutboxConflict implements Exception {
  _OutboxConflict(this.message);

  final String message;

  @override
  String toString() => message;
}

class OfflineFirstCRMRepository implements CRMRepository {
  OfflineFirstCRMRepository({
    required CRMRepository remote,
    required OutboxQueue outbox,
    required EntityCache cache,
  })  : _remote = remote,
        _outbox = outbox,
        _cache = cache;

  final CRMRepository _remote;
  final OutboxQueue _outbox;
  final EntityCache _cache;

  final Random _random = Random();
  Future<void>? _flushFuture;

  bool _isOfflineError(Object e) {
    if (e is SocketException || e is TimeoutException) return true;
    final msg = e.toString();
    return msg.contains('SocketException') ||
        msg.contains('TimeoutException') ||
        msg.contains('NetworkError') ||
        msg.contains('no internet connection') ||
        msg.contains('Connection closed');
  }

  String _newTempId(String prefix) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rnd = _random.nextInt(1 << 32);
    return 'tmp_${prefix}_${now}_$rnd';
  }

  void _kickFlush() {
    unawaited(flushOutbox());
  }

  Future<void> flushOutbox() async {
    final existing = _flushFuture;
    if (existing != null) return existing;

    final future = _flushInternal();
    _flushFuture = future;
    try {
      await future;
    } finally {
      if (identical(_flushFuture, future)) {
        _flushFuture = null;
      }
    }
  }

  Future<void> _flushInternal() async {
    while (true) {
      final pending = await _outbox.listPending();
      if (pending.isEmpty) return;

      developer.log('[outbox.flush] pending=${pending.length}', name: 'outbox');
      var progressed = false;
      for (final item in pending) {
        final processing = item.copyWith(
          status: OutboxStatus.processing,
          lastAttemptAt: DateTime.now(),
          lastError: null,
        );
        await _outbox.upsert(processing);

        try {
          await _executeOutboxItem(processing);
          await _outbox.remove(processing.operationId);
          progressed = true;
          developer.log(
            '[outbox.ok] ${processing.entityType.name}.${processing.operation.name} id=${processing.entityId ?? ''} op=${processing.operationId}',
            name: 'outbox',
          );
        } catch (e) {
          final error = e.toString();
          final next = processing.copyWith(
            status: e is _OutboxConflict
                ? OutboxStatus.conflict
                : (_isOfflineError(e) ? OutboxStatus.pending : OutboxStatus.failed),
            retryCount: processing.retryCount + 1,
            lastError: error,
          );
          await _outbox.upsert(next);
          developer.log(
            '[outbox.err] status=${next.status.name} ${processing.entityType.name}.${processing.operation.name} id=${processing.entityId ?? ''} op=${processing.operationId} err=$error',
            name: 'outbox',
          );
          if (_isOfflineError(e)) {
            return;
          }
        }
      }

      if (!progressed) return;
    }
  }

  Map<String, dynamic> _snapshotContact(Contact c) => {
        'firstName': c.firstName,
        'lastName': c.lastName,
        'email': c.email,
        'phone': c.phone,
        'companyId': c.companyId,
        'jobTitle': c.jobTitle,
        'city': c.city,
        'linkedinUrl': c.linkedinUrl,
        'xUrl': c.xUrl,
      };

  Map<String, dynamic> _snapshotCompany(Company c) => {
        'name': c.name,
        'domainName': c.domainName,
      };

  Map<String, dynamic> _snapshotTask(Task t) => {
        'title': t.title,
        'body': t.body,
        'dueAt': t.dueAt?.toIso8601String(),
        'completed': t.completed,
      };

  Map<String, dynamic> _snapshotNote(Note n) => {
        'body': n.body,
        'dueAt': n.dueAt?.toIso8601String(),
      };

  bool _sameSnapshot(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  Future<void> _executeOutboxItem(OutboxItem item) async {
    switch (item.entityType) {
      case OutboxEntityType.contact:
        await _executeContact(item);
        break;
      case OutboxEntityType.company:
        await _executeCompany(item);
        break;
      case OutboxEntityType.note:
        await _executeNote(item);
        break;
      case OutboxEntityType.task:
        await _executeTask(item);
        break;
    }
  }

  Future<void> _executeContact(OutboxItem item) async {
    switch (item.operation) {
      case OutboxOperation.create:
        final tempId = item.entityId!;
        final created = await _remote.createContact(
          firstName: item.payload['firstName'] as String,
          lastName: item.payload['lastName'] as String,
          email: item.payload['email'] as String?,
          phone: item.payload['phone'] as String?,
          jobTitle: item.payload['jobTitle'] as String?,
          city: item.payload['city'] as String?,
          linkedinUrl: item.payload['linkedinUrl'] as String?,
          xUrl: item.payload['xUrl'] as String?,
        );
        await _cache.replaceIdEverywhere(oldId: tempId, newId: created.id);
        await _outbox.replaceIdsInPending(oldId: tempId, newId: created.id);
        break;
      case OutboxOperation.update:
        final force = item.payload['_force'] == true;
        final baseRaw = item.payload['_base'];
        if (!force && baseRaw is Map) {
          final base = Map<String, dynamic>.from(baseRaw);
          final remote = await _remote.getContactById(item.entityId!);
          final remoteSnap = _snapshotContact(remote);
          if (!_sameSnapshot(base, remoteSnap)) {
            throw _OutboxConflict('contact conflict id=${item.entityId}');
          }
        }
        await _remote.updateContact(
          item.entityId!,
          firstName: item.payload['firstName'] as String?,
          lastName: item.payload['lastName'] as String?,
          email: item.payload['email'] as String?,
          phone: item.payload['phone'] as String?,
          companyId: item.payload['companyId'] as String?,
          jobTitle: item.payload['jobTitle'] as String?,
          city: item.payload['city'] as String?,
          linkedinUrl: item.payload['linkedinUrl'] as String?,
          xUrl: item.payload['xUrl'] as String?,
          clearCompany: item.payload['clearCompany'] as bool? ?? false,
        );
        break;
      case OutboxOperation.delete:
        final force = item.payload['_force'] == true;
        final baseRaw = item.payload['_base'];
        if (!force && baseRaw is Map) {
          try {
            final base = Map<String, dynamic>.from(baseRaw);
            final remote = await _remote.getContactById(item.entityId!);
            final remoteSnap = _snapshotContact(remote);
            if (!_sameSnapshot(base, remoteSnap)) {
              throw _OutboxConflict('contact conflict id=${item.entityId}');
            }
          } catch (_) {}
        }
        await _remote.deleteContact(item.entityId!);
        break;
    }
  }

  Future<void> _executeCompany(OutboxItem item) async {
    switch (item.operation) {
      case OutboxOperation.create:
        final tempId = item.entityId!;
        final created = await _remote.createCompany(
          name: item.payload['name'] as String,
          domainName: item.payload['domainName'] as String?,
        );
        await _cache.replaceIdEverywhere(oldId: tempId, newId: created.id);
        await _outbox.replaceIdsInPending(oldId: tempId, newId: created.id);
        break;
      case OutboxOperation.update:
        final force = item.payload['_force'] == true;
        final baseRaw = item.payload['_base'];
        if (!force && baseRaw is Map) {
          final base = Map<String, dynamic>.from(baseRaw);
          final remote = await _remote.getCompanyById(item.entityId!);
          final remoteSnap = _snapshotCompany(remote);
          if (!_sameSnapshot(base, remoteSnap)) {
            throw _OutboxConflict('company conflict id=${item.entityId}');
          }
        }
        await _remote.updateCompany(
          item.entityId!,
          name: item.payload['name'] as String?,
          domainName: item.payload['domainName'] as String?,
        );
        break;
      case OutboxOperation.delete:
        final force = item.payload['_force'] == true;
        final baseRaw = item.payload['_base'];
        if (!force && baseRaw is Map) {
          try {
            final base = Map<String, dynamic>.from(baseRaw);
            final remote = await _remote.getCompanyById(item.entityId!);
            final remoteSnap = _snapshotCompany(remote);
            if (!_sameSnapshot(base, remoteSnap)) {
              throw _OutboxConflict('company conflict id=${item.entityId}');
            }
          } catch (_) {}
        }
        await _remote.deleteCompany(item.entityId!);
        break;
    }
  }

  Future<void> _executeNote(OutboxItem item) async {
    switch (item.operation) {
      case OutboxOperation.create:
        final tempId = item.entityId!;
        final created = await _remote.createNote(
          contactId: item.payload['contactId'] as String?,
          companyId: item.payload['companyId'] as String?,
          body: item.payload['body'] as String,
          dueAt: item.payload['dueAt'] != null
              ? DateTime.parse(item.payload['dueAt'] as String)
              : null,
        );
        await _cache.replaceIdEverywhere(oldId: tempId, newId: created.id);
        await _outbox.replaceIdsInPending(oldId: tempId, newId: created.id);
        break;
      case OutboxOperation.update:
        final force = item.payload['_force'] == true;
        final baseRaw = item.payload['_base'];
        if (!force && baseRaw is Map) {
          final base = Map<String, dynamic>.from(baseRaw);
          final contactId = item.payload['contactId'] as String?;
          final companyId = item.payload['companyId'] as String?;
          List<Note> remoteNotes = const [];
          if (contactId != null && contactId.isNotEmpty) {
            remoteNotes = await _remote.getNotesByContact(contactId);
          } else if (companyId != null && companyId.isNotEmpty) {
            remoteNotes = await _remote.getNotesByCompany(companyId);
          }
          final remote = remoteNotes.where((n) => n.id == item.entityId).toList();
          if (remote.isNotEmpty) {
            final remoteSnap = _snapshotNote(remote.first);
            if (!_sameSnapshot(base, remoteSnap)) {
              throw _OutboxConflict('note conflict id=${item.entityId}');
            }
          }
        }
        await _remote.updateNote(
          item.entityId!,
          body: item.payload['body'] as String,
          dueAt: item.payload['dueAt'] != null
              ? DateTime.parse(item.payload['dueAt'] as String)
              : null,
        );
        break;
      case OutboxOperation.delete:
        final force = item.payload['_force'] == true;
        final baseRaw = item.payload['_base'];
        if (!force && baseRaw is Map) {
          try {
            final base = Map<String, dynamic>.from(baseRaw);
            final contactId = item.payload['contactId'] as String?;
            final companyId = item.payload['companyId'] as String?;
            List<Note> remoteNotes = const [];
            if (contactId != null && contactId.isNotEmpty) {
              remoteNotes = await _remote.getNotesByContact(contactId);
            } else if (companyId != null && companyId.isNotEmpty) {
              remoteNotes = await _remote.getNotesByCompany(companyId);
            }
            final remote = remoteNotes.where((n) => n.id == item.entityId).toList();
            if (remote.isNotEmpty) {
              final remoteSnap = _snapshotNote(remote.first);
              if (!_sameSnapshot(base, remoteSnap)) {
                throw _OutboxConflict('note conflict id=${item.entityId}');
              }
            }
          } catch (_) {}
        }
        await _remote.deleteNote(item.entityId!);
        break;
    }
  }

  Future<void> _executeTask(OutboxItem item) async {
    switch (item.operation) {
      case OutboxOperation.create:
        final tempId = item.entityId!;
        final created = await _remote.createTask(
          title: item.payload['title'] as String,
          body: item.payload['body'] as String?,
          dueAt: item.payload['dueAt'] != null
              ? DateTime.parse(item.payload['dueAt'] as String)
              : null,
          contactId: item.payload['contactId'] as String?,
        );
        await _cache.replaceIdEverywhere(oldId: tempId, newId: created.id);
        await _outbox.replaceIdsInPending(oldId: tempId, newId: created.id);
        break;
      case OutboxOperation.update:
        final force = item.payload['_force'] == true;
        final baseRaw = item.payload['_base'];
        if (!force && baseRaw is Map) {
          final base = Map<String, dynamic>.from(baseRaw);
          final todo = await _remote.getTasks(completed: false);
          final done = await _remote.getTasks(completed: true);
          final remote = <Task>[...todo, ...done].where((t) => t.id == item.entityId).toList();
          if (remote.isNotEmpty) {
            final remoteSnap = _snapshotTask(remote.first);
            if (!_sameSnapshot(base, remoteSnap)) {
              throw _OutboxConflict('task conflict id=${item.entityId}');
            }
          }
        }
        await _remote.updateTask(
          item.entityId!,
          title: item.payload['title'] as String?,
          body: item.payload['body'] as String?,
          dueAt: item.payload['dueAt'] != null
              ? DateTime.parse(item.payload['dueAt'] as String)
              : null,
          clearDueDate: item.payload['clearDueDate'] as bool? ?? false,
          completed: item.payload['completed'] as bool?,
        );
        break;
      case OutboxOperation.delete:
        final force = item.payload['_force'] == true;
        final baseRaw = item.payload['_base'];
        if (!force && baseRaw is Map) {
          try {
            final base = Map<String, dynamic>.from(baseRaw);
            final todo = await _remote.getTasks(completed: false);
            final done = await _remote.getTasks(completed: true);
            final remote = <Task>[...todo, ...done].where((t) => t.id == item.entityId).toList();
            if (remote.isNotEmpty) {
              final remoteSnap = _snapshotTask(remote.first);
              if (!_sameSnapshot(base, remoteSnap)) {
                throw _OutboxConflict('task conflict id=${item.entityId}');
              }
            }
          } catch (_) {}
        }
        await _remote.deleteTask(item.entityId!);
        break;
    }
  }

  Contact? _readContactFromCache(String id) {
    final detail = _cache.readContactDetail(id);
    if (detail != null) return detail;
    final list = _cache.readContactsList();
    if (list == null) return null;
    return list.firstWhere((c) => c.id == id, orElse: () => Contact(id: id, firstName: '', lastName: ''));
  }

  Company? _readCompanyFromCache(String id) {
    final detail = _cache.readCompanyDetail(id);
    if (detail != null) return detail;
    final list = _cache.readCompaniesList();
    if (list == null) return null;
    return list.firstWhere((c) => c.id == id, orElse: () => Company(id: id, name: ''));
  }

  Task? _readTaskFromCache(String id) {
    final detail = _cache.readTaskDetail(id);
    if (detail != null) return detail;
    final todo = _cache.readTasksList(completed: false);
    final done = _cache.readTasksList(completed: true);
    final all = <Task>[...?todo, ...?done];
    if (all.isEmpty) return null;
    return all.firstWhere((t) => t.id == id, orElse: () => Task(id: id, title: ''));
  }

  Note? _readNoteFromCache(String id) => _cache.readNoteDetail(id);

  @override
  Future<bool> testConnection(String baseUrl, String apiToken) =>
      _remote.testConnection(baseUrl, apiToken);

  @override
  Future<String> getCurrentUserName() => _remote.getCurrentUserName();

  @override
  Future<({List<Contact> contacts, String? endCursor, bool hasNextPage})> getContacts({
    String? search,
    int pageSize = 20,
    String? after,
  }) async {
    final result = await _remote.getContacts(search: search, pageSize: pageSize, after: after);
    _kickFlush();
    return result;
  }

  @override
  Future<List<Contact>> getContactsByCompany(String companyId) async {
    final result = await _remote.getContactsByCompany(companyId);
    _kickFlush();
    return result;
  }

  @override
  Future<List<Contact>> getContactsByTask(String taskId) async {
    final result = await _remote.getContactsByTask(taskId);
    _kickFlush();
    return result;
  }

  @override
  Future<Contact> getContactById(String id) async {
    final result = await _remote.getContactById(id);
    _kickFlush();
    return result;
  }

  @override
  Future<Contact> createContact({
    required String firstName,
    required String lastName,
    String? email,
    String? phone,
    String? jobTitle,
    String? city,
    String? linkedinUrl,
    String? xUrl,
  }) async {
    try {
      final created = await _remote.createContact(
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        jobTitle: jobTitle,
        city: city,
        linkedinUrl: linkedinUrl,
        xUrl: xUrl,
      );
      _kickFlush();
      return created;
    } catch (e) {
      if (!_isOfflineError(e)) rethrow;
      final tempId = _newTempId('contact');
      final optimistic = Contact(
        id: tempId,
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        jobTitle: jobTitle,
        city: city,
        linkedinUrl: linkedinUrl,
        xUrl: xUrl,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _outbox.enqueue(
        OutboxItem(
          operationId: _newTempId('op'),
          entityType: OutboxEntityType.contact,
          operation: OutboxOperation.create,
          entityId: tempId,
          payload: {
            'firstName': firstName,
            'lastName': lastName,
            'email': email,
            'phone': phone,
            'jobTitle': jobTitle,
            'city': city,
            'linkedinUrl': linkedinUrl,
            'xUrl': xUrl,
          },
          createdAt: DateTime.now(),
        ),
      );
      return optimistic;
    }
  }

  @override
  Future<Contact> updateContact(
    String id, {
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
    String? companyId,
    String? jobTitle,
    String? city,
    String? linkedinUrl,
    String? xUrl,
    bool clearCompany = false,
  }) async {
    try {
      final updated = await _remote.updateContact(
        id,
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        companyId: companyId,
        jobTitle: jobTitle,
        city: city,
        linkedinUrl: linkedinUrl,
        xUrl: xUrl,
        clearCompany: clearCompany,
      );
      _kickFlush();
      return updated;
    } catch (e) {
      if (!_isOfflineError(e)) rethrow;
      final base = _readContactFromCache(id);
      final optimistic = (base ?? Contact(id: id, firstName: '', lastName: '')).copyWith(
        firstName: firstName ?? '',
        lastName: lastName ?? '',
        email: email,
        phone: phone,
        companyId: clearCompany ? null : companyId,
        jobTitle: jobTitle ?? base?.jobTitle,
        city: city ?? base?.city,
        linkedinUrl: linkedinUrl ?? base?.linkedinUrl,
        xUrl: xUrl ?? base?.xUrl,
      );
      await _outbox.enqueue(
        OutboxItem(
          operationId: _newTempId('op'),
          entityType: OutboxEntityType.contact,
          operation: OutboxOperation.update,
          entityId: id,
          payload: {
            if (base != null) '_base': _snapshotContact(base),
            'firstName': ?firstName,
            'lastName': ?lastName,
            'email': ?email,
            'phone': ?phone,
            'companyId': ?companyId,
            'jobTitle': ?jobTitle,
            'city': ?city,
            'linkedinUrl': ?linkedinUrl,
            'xUrl': ?xUrl,
            'clearCompany': clearCompany,
          },
          createdAt: DateTime.now(),
        ),
      );
      return optimistic;
    }
  }

  @override
  Future<void> deleteContact(String id) async {
    try {
      await _remote.deleteContact(id);
      _kickFlush();
    } catch (e) {
      if (!_isOfflineError(e)) rethrow;
      final base = _readContactFromCache(id);
      await _outbox.enqueue(
        OutboxItem(
          operationId: _newTempId('op'),
          entityType: OutboxEntityType.contact,
          operation: OutboxOperation.delete,
          entityId: id,
          payload: {
            if (base != null) '_base': _snapshotContact(base),
          },
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  @override
  Future<List<Company>> getCompanies({String? search, int page = 1}) async {
    final result = await _remote.getCompanies(search: search, page: page);
    _kickFlush();
    return result;
  }

  @override
  Future<Company> getCompanyById(String id) async {
    final result = await _remote.getCompanyById(id);
    _kickFlush();
    return result;
  }

  @override
  Future<Company> createCompany({required String name, String? domainName}) async {
    try {
      final created = await _remote.createCompany(name: name, domainName: domainName);
      _kickFlush();
      return created;
    } catch (e) {
      if (!_isOfflineError(e)) rethrow;
      final tempId = _newTempId('company');
      final optimistic = Company(
        id: tempId,
        name: name,
        domainName: domainName,
        createdAt: DateTime.now(),
      );
      await _outbox.enqueue(
        OutboxItem(
          operationId: _newTempId('op'),
          entityType: OutboxEntityType.company,
          operation: OutboxOperation.create,
          entityId: tempId,
          payload: {
            'name': name,
            'domainName': domainName,
          },
          createdAt: DateTime.now(),
        ),
      );
      return optimistic;
    }
  }

  @override
  Future<Company> updateCompany(String id, {String? name, String? domainName}) async {
    try {
      final updated = await _remote.updateCompany(id, name: name, domainName: domainName);
      _kickFlush();
      return updated;
    } catch (e) {
      if (!_isOfflineError(e)) rethrow;
      final base = _readCompanyFromCache(id);
      final optimistic = (base ?? Company(id: id, name: name ?? '')).copyWith(
        name: name ?? (base?.name ?? ''),
        domainName: domainName ?? base?.domainName,
      );
      await _outbox.enqueue(
        OutboxItem(
          operationId: _newTempId('op'),
          entityType: OutboxEntityType.company,
          operation: OutboxOperation.update,
          entityId: id,
          payload: {
            if (base != null) '_base': _snapshotCompany(base),
            'name': ?name,
            'domainName': ?domainName,
          },
          createdAt: DateTime.now(),
        ),
      );
      return optimistic;
    }
  }

  @override
  Future<void> deleteCompany(String id) async {
    try {
      await _remote.deleteCompany(id);
      _kickFlush();
    } catch (e) {
      if (!_isOfflineError(e)) rethrow;
      final base = _readCompanyFromCache(id);
      await _outbox.enqueue(
        OutboxItem(
          operationId: _newTempId('op'),
          entityType: OutboxEntityType.company,
          operation: OutboxOperation.delete,
          entityId: id,
          payload: {
            if (base != null) '_base': _snapshotCompany(base),
          },
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  @override
  Future<List<Note>> getNotesByContact(String contactId) async {
    final result = await _remote.getNotesByContact(contactId);
    _kickFlush();
    return result;
  }

  @override
  Future<List<Note>> getNotesByCompany(String companyId) async {
    final result = await _remote.getNotesByCompany(companyId);
    _kickFlush();
    return result;
  }

  @override
  Future<Note> createNote({
    String? contactId,
    String? companyId,
    required String body,
    DateTime? dueAt,
  }) async {
    try {
      final created = await _remote.createNote(
        contactId: contactId,
        companyId: companyId,
        body: body,
        dueAt: dueAt,
      );
      _kickFlush();
      return created;
    } catch (e) {
      if (!_isOfflineError(e)) rethrow;
      final tempId = _newTempId('note');
      final optimistic = Note(
        id: tempId,
        body: body,
        contactId: contactId,
        companyId: companyId,
        dueAt: dueAt,
        createdAt: DateTime.now(),
      );
      await _outbox.enqueue(
        OutboxItem(
          operationId: _newTempId('op'),
          entityType: OutboxEntityType.note,
          operation: OutboxOperation.create,
          entityId: tempId,
          payload: {
            'contactId': contactId,
            'companyId': companyId,
            'body': body,
            'dueAt': dueAt?.toIso8601String(),
          },
          createdAt: DateTime.now(),
        ),
      );
      return optimistic;
    }
  }

  @override
  Future<Note> updateNote(String id, {required String body, DateTime? dueAt}) async {
    try {
      final updated = await _remote.updateNote(id, body: body, dueAt: dueAt);
      _kickFlush();
      return updated;
    } catch (e) {
      if (!_isOfflineError(e)) rethrow;
      final base = _readNoteFromCache(id);
      final optimistic = (base ?? Note(id: id, body: body)).copyWith(
        body: body,
        dueAt: dueAt ?? base?.dueAt,
      );
      await _outbox.enqueue(
        OutboxItem(
          operationId: _newTempId('op'),
          entityType: OutboxEntityType.note,
          operation: OutboxOperation.update,
          entityId: id,
          payload: {
            if (base != null) '_base': _snapshotNote(base),
            'body': body,
            'dueAt': dueAt?.toIso8601String(),
          },
          createdAt: DateTime.now(),
        ),
      );
      return optimistic;
    }
  }

  @override
  Future<void> deleteNote(String id) async {
    try {
      await _remote.deleteNote(id);
      _kickFlush();
    } catch (e) {
      if (!_isOfflineError(e)) rethrow;
      final base = _readNoteFromCache(id);
      await _outbox.enqueue(
        OutboxItem(
          operationId: _newTempId('op'),
          entityType: OutboxEntityType.note,
          operation: OutboxOperation.delete,
          entityId: id,
          payload: {
            if (base != null) '_base': _snapshotNote(base),
          },
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  @override
  Future<List<Task>> getTasks({bool? completed}) async {
    final result = await _remote.getTasks(completed: completed);
    _kickFlush();
    return result;
  }

  @override
  Future<List<Task>> getOverdueTasks() async {
    final result = await _remote.getOverdueTasks();
    _kickFlush();
    return result;
  }

  @override
  Future<List<Task>> getTodayTasks() async {
    final result = await _remote.getTodayTasks();
    _kickFlush();
    return result;
  }

  @override
  Future<List<Task>> getTomorrowTasks() async {
    final result = await _remote.getTomorrowTasks();
    _kickFlush();
    return result;
  }

  @override
  Future<Task> createTask({
    required String title,
    String? body,
    DateTime? dueAt,
    String? contactId,
  }) async {
    try {
      final created = await _remote.createTask(
        title: title,
        body: body,
        dueAt: dueAt,
        contactId: contactId,
      );
      _kickFlush();
      return created;
    } catch (e) {
      if (!_isOfflineError(e)) rethrow;
      final tempId = _newTempId('task');
      final optimistic = Task(
        id: tempId,
        title: title,
        body: body,
        completed: false,
        dueAt: dueAt,
        contactId: contactId,
        createdAt: DateTime.now(),
      );
      await _outbox.enqueue(
        OutboxItem(
          operationId: _newTempId('op'),
          entityType: OutboxEntityType.task,
          operation: OutboxOperation.create,
          entityId: tempId,
          payload: {
            'title': title,
            'body': body,
            'dueAt': dueAt?.toIso8601String(),
            'contactId': contactId,
          },
          createdAt: DateTime.now(),
        ),
      );
      return optimistic;
    }
  }

  @override
  Future<Task> updateTask(
    String id, {
    String? title,
    String? body,
    DateTime? dueAt,
    bool clearDueDate = false,
    bool? completed,
  }) async {
    try {
      final updated = await _remote.updateTask(
        id,
        title: title,
        body: body,
        dueAt: dueAt,
        clearDueDate: clearDueDate,
        completed: completed,
      );
      _kickFlush();
      return updated;
    } catch (e) {
      if (!_isOfflineError(e)) rethrow;
      final base = _readTaskFromCache(id);
      final optimistic = (base ?? Task(id: id, title: title ?? '')).copyWith(
        title: title ?? (base?.title ?? ''),
        body: body ?? base?.body,
        dueAt: clearDueDate ? null : (dueAt ?? base?.dueAt),
        completed: completed ?? base?.completed,
      );
      await _outbox.enqueue(
        OutboxItem(
          operationId: _newTempId('op'),
          entityType: OutboxEntityType.task,
          operation: OutboxOperation.update,
          entityId: id,
          payload: {
            if (base != null) '_base': _snapshotTask(base),
            'title': ?title,
            'body': ?body,
            'dueAt': dueAt?.toIso8601String(),
            'clearDueDate': clearDueDate,
            'completed': ?completed,
          },
          createdAt: DateTime.now(),
        ),
      );
      return optimistic;
    }
  }

  @override
  Future<void> deleteTask(String id) async {
    try {
      await _remote.deleteTask(id);
      _kickFlush();
    } catch (e) {
      if (!_isOfflineError(e)) rethrow;
      final base = _readTaskFromCache(id);
      await _outbox.enqueue(
        OutboxItem(
          operationId: _newTempId('op'),
          entityType: OutboxEntityType.task,
          operation: OutboxOperation.delete,
          entityId: id,
          payload: {
            if (base != null) '_base': _snapshotTask(base),
          },
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  @override
  Future<List<Contact>> getRecentContacts({int limit = 5}) async {
    final result = await _remote.getRecentContacts(limit: limit);
    _kickFlush();
    return result;
  }
}
