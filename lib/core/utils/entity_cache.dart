import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:pocketcrm/domain/models/company.dart';
import 'package:pocketcrm/domain/models/contact.dart';
import 'package:pocketcrm/domain/models/note.dart';
import 'package:pocketcrm/domain/models/task.dart';

class EntityCache {
  EntityCache(this._box);

  final Box<String> _box;

  static const String _prefix = 'cache:';

  static String _k(String key) => '$_prefix$key';

  static String contactsListKey() => _k('contacts:list');
  static String contactDetailKey(String id) => _k('contacts:detail:$id');

  static String companiesListKey() => _k('companies:list');
  static String companyDetailKey(String id) => _k('companies:detail:$id');

  static String tasksListKey({required bool completed}) =>
      _k('tasks:list:${completed ? 'done' : 'todo'}');
  static String taskDetailKey(String id) => _k('tasks:detail:$id');

  static String contactNotesKey(String contactId) =>
      _k('contacts:notes:$contactId');
  static String companyNotesKey(String companyId) =>
      _k('companies:notes:$companyId');
  static String noteDetailKey(String id) => _k('notes:detail:$id');

  List<T>? _readList<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final raw = _box.get(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map>()
          .map((m) => fromJson(Map<String, dynamic>.from(m)))
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  T? _readObject<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final raw = _box.get(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeList<T>(
    String key,
    List<T> items,
    Map<String, dynamic> Function(T) toJson,
  ) async {
    final encoded = jsonEncode(items.map(toJson).toList(growable: false));
    await _box.put(key, encoded);
  }

  Future<void> _writeObject<T>(
    String key,
    T item,
    Map<String, dynamic> Function(T) toJson,
  ) async {
    await _box.put(key, jsonEncode(toJson(item)));
  }

  List<Contact>? readContactsList() =>
      _readList(contactsListKey(), Contact.fromJson);

  Contact? readContactDetail(String id) =>
      _readObject(contactDetailKey(id), Contact.fromJson);

  Future<void> writeContactsList(List<Contact> contacts) async {
    await _writeList(contactsListKey(), contacts, (c) => c.toJson());
    for (final c in contacts) {
      await _writeObject(contactDetailKey(c.id), c, (x) => x.toJson());
    }
  }

  Future<void> writeContactDetail(Contact contact) =>
      _writeObject(contactDetailKey(contact.id), contact, (c) => c.toJson());

  Future<void> deleteContactDetail(String id) async {
    await _box.delete(contactDetailKey(id));
  }

  List<Company>? readCompaniesList() =>
      _readList(companiesListKey(), Company.fromJson);

  Company? readCompanyDetail(String id) =>
      _readObject(companyDetailKey(id), Company.fromJson);

  Future<void> writeCompaniesList(List<Company> companies) async {
    await _writeList(companiesListKey(), companies, (c) => c.toJson());
    for (final c in companies) {
      await _writeObject(companyDetailKey(c.id), c, (x) => x.toJson());
    }
  }

  Future<void> writeCompanyDetail(Company company) =>
      _writeObject(companyDetailKey(company.id), company, (c) => c.toJson());

  Future<void> deleteCompanyDetail(String id) async {
    await _box.delete(companyDetailKey(id));
  }

  List<Task>? readTasksList({required bool completed}) =>
      _readList(tasksListKey(completed: completed), Task.fromJson);

  Task? readTaskDetail(String id) =>
      _readObject(taskDetailKey(id), Task.fromJson);

  Future<void> writeTasksList({
    required bool completed,
    required List<Task> tasks,
  }) async {
    await _writeList(
      tasksListKey(completed: completed),
      tasks,
      (t) => t.toJson(),
    );
    for (final t in tasks) {
      await _writeObject(taskDetailKey(t.id), t, (x) => x.toJson());
    }
  }

  Future<void> writeTaskDetail(Task task) =>
      _writeObject(taskDetailKey(task.id), task, (t) => t.toJson());

  Future<void> deleteTaskDetail(String id) async {
    await _box.delete(taskDetailKey(id));
  }

  List<Note>? readContactNotes(String contactId) =>
      _readList(contactNotesKey(contactId), Note.fromJson);

  List<Note>? readCompanyNotes(String companyId) =>
      _readList(companyNotesKey(companyId), Note.fromJson);

  Note? readNoteDetail(String id) => _readObject(noteDetailKey(id), Note.fromJson);

  Future<void> writeContactNotes(String contactId, List<Note> notes) async {
    await _writeList(contactNotesKey(contactId), notes, (n) => n.toJson());
    for (final n in notes) {
      await _writeObject(noteDetailKey(n.id), n, (x) => x.toJson());
    }
  }

  Future<void> writeCompanyNotes(String companyId, List<Note> notes) async {
    await _writeList(companyNotesKey(companyId), notes, (n) => n.toJson());
    for (final n in notes) {
      await _writeObject(noteDetailKey(n.id), n, (x) => x.toJson());
    }
  }

  Future<void> writeNoteDetail(Note note) =>
      _writeObject(noteDetailKey(note.id), note, (n) => n.toJson());

  Future<void> deleteNoteDetail(String id) async {
    await _box.delete(noteDetailKey(id));
  }

  Future<void> replaceIdEverywhere({
    required String oldId,
    required String newId,
  }) async {
    final keys = _box.keys.whereType<String>().where((k) => k.startsWith(_prefix)).toList();
    for (final key in keys) {
      final raw = _box.get(key);
      if (raw == null || raw.isEmpty) continue;
      if (!raw.contains(oldId) && !key.endsWith(oldId)) continue;

      final replacement = _replaceIdsInJson(raw, oldId: oldId, newId: newId);
      final nextKey = key.endsWith(oldId)
          ? '${key.substring(0, key.length - oldId.length)}$newId'
          : key;

      if (nextKey != key) {
        await _box.put(nextKey, replacement);
        await _box.delete(key);
      } else if (replacement != raw) {
        await _box.put(key, replacement);
      }
    }
  }

  String _replaceIdsInJson(
    String raw, {
    required String oldId,
    required String newId,
  }) {
    try {
      final decoded = jsonDecode(raw);
      bool changed = false;

      dynamic visit(dynamic value) {
        if (value is String) {
          if (value == oldId) {
            changed = true;
            return newId;
          }
          return value;
        }
        if (value is List) {
          final out = <dynamic>[];
          for (final e in value) {
            out.add(visit(e));
          }
          return changed ? out : value;
        }
        if (value is Map) {
          final out = <String, dynamic>{};
          for (final entry in value.entries) {
            final k = entry.key.toString();
            final v = entry.value;
            if ((k == 'id' || k == 'contactId' || k == 'companyId') && v == oldId) {
              changed = true;
              out[k] = newId;
              continue;
            }
            out[k] = visit(v);
          }
          return changed ? out : value;
        }
        return value;
      }

      final updated = visit(decoded);
      if (!changed) return raw;
      return jsonEncode(updated);
    } catch (_) {
      return raw;
    }
  }
}
