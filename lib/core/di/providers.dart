import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pocketcrm/core/utils/entity_cache.dart';
import 'package:pocketcrm/core/offline/outbox_queue.dart';
import 'package:pocketcrm/core/utils/storage_service.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:pocketcrm/data/connectors/twenty_connector.dart';
import 'package:pocketcrm/data/repositories/offline_first_crm_repository.dart';
import 'package:pocketcrm/domain/models/company.dart';
import 'package:pocketcrm/domain/models/contact.dart';
import 'package:pocketcrm/domain/models/note.dart';
import 'package:pocketcrm/domain/models/task.dart';
import 'package:pocketcrm/domain/repositories/crm_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:pocketcrm/core/notifications/notification_service.dart';

part 'providers.g.dart';

String? _extractWorkspaceIdFromToken(String token) {
  try {
    final parts = token.split('.');
    if (parts.length < 2) return null;
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is Map<String, dynamic>) {
      final id = payload['workspaceId'];
      if (id is String && id.isNotEmpty) return id;
    }
  } catch (_) {
    // ignore and continue without workspace header
  }
  return null;
}

String _normalizeInstanceUrl(String rawUrl) {
  var url = rawUrl.trim();
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  if (url.endsWith('/graphql')) {
    url = url.substring(0, url.length - '/graphql'.length);
  }
  if (url.endsWith('/healthz')) {
    url = url.substring(0, url.length - '/healthz'.length);
  }
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

String _normalizeToken(String rawToken) => rawToken.replaceAll(RegExp(r'\s+'), '');

EntityCache? _tryEntityCache(dynamic ref) {
  try {
    final box = ref.read(hiveStorageBoxProvider);
    return EntityCache(box);
  } catch (_) {
    return null;
  }
}

@Riverpod(keepAlive: true)
Box<String> hiveStorageBox(HiveStorageBoxRef ref) {
  throw UnimplementedError(); // Overridden in main.dart
}

@Riverpod(keepAlive: true)
StorageService storageService(StorageServiceRef ref) {
  const secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final box = ref.watch(hiveStorageBoxProvider);
  return StorageService(secure, box);
}

@Riverpod(keepAlive: true)
Future<bool> isDemoMode(IsDemoModeRef ref) async {
  final storage = ref.watch(storageServiceProvider);
  final value = await storage.read(key: 'is_demo_mode');
  return value == 'true';
}

@Riverpod(keepAlive: true)
Future<CRMRepository> crmRepository(CrmRepositoryRef ref) async {
  final storage = ref.watch(storageServiceProvider);
  final rawBaseUrl = await storage.read(key: 'instance_url');
  final rawApiToken = await storage.read(key: 'api_token');

  if (rawBaseUrl == null || rawApiToken == null) {
    throw Exception('Not connected');
  }

  final baseUrl = _normalizeInstanceUrl(rawBaseUrl);
  final apiToken = _normalizeToken(rawApiToken);
  final workspaceId = _extractWorkspaceIdFromToken(apiToken);
  final tokenTail = apiToken.length >= 6
      ? apiToken.substring(apiToken.length - 6)
      : apiToken;
  debugPrint(
    'TwentyMobile.Debug: crmRepository init baseUrl=$baseUrl workspaceId=${workspaceId ?? 'null'} tokenLen=${apiToken.length} tokenTail=$tokenTail',
  );

  final link = HttpLink(
    '$baseUrl/graphql', // Twenty CRM graphql endpoint
    useGETForQueries: false,
    defaultHeaders: {
      'Authorization': 'Bearer $apiToken',
      if (workspaceId != null) 'x-workspace-id': workspaceId,
    },
  );

  final client = GraphQLClient(link: link, cache: GraphQLCache());

  final remote = TwentyConnector(
    client: client,
    baseUrl: baseUrl,
    apiToken: apiToken,
    workspaceId: workspaceId,
  );

  final box = ref.watch(hiveStorageBoxProvider);
  final cache = EntityCache(box);
  final outbox = OutboxQueue(box);
  final repo = OfflineFirstCRMRepository(remote: remote, outbox: outbox, cache: cache);
  unawaited(repo.flushOutbox());
  return repo;
}

@Riverpod(keepAlive: true)
class Contacts extends _$Contacts {
  String? _endCursor;
  bool _hasNextPage = false;
  bool _isLoadingMore = false;
  String? _currentSearch;
  bool _isDisposed = false;

  @override
  FutureOr<List<Contact>> build() async {
    _endCursor = null;
    _hasNextPage = false;
    _currentSearch = null;
    _isDisposed = false;
    ref.onDispose(() => _isDisposed = true);
    final cache = _tryEntityCache(ref);
    final cached = cache?.readContactsList();
    if (cached != null) {
      unawaited(_refreshContacts(cache!));
      return cached;
    }

    final repo = await ref.watch(crmRepositoryProvider.future);
    final result = await repo.getContacts();
    _endCursor = result.endCursor;
    _hasNextPage = result.hasNextPage;
    await cache?.writeContactsList(result.contacts);
    return result.contacts;
  }

  Future<void> _refreshContacts(EntityCache cache) async {
    try {
      final repo = await ref.read(crmRepositoryProvider.future);
      final result = await repo.getContacts();
      if (_isDisposed) return;
      if (_currentSearch != null) return;
      _endCursor = result.endCursor;
      _hasNextPage = result.hasNextPage;
      state = AsyncValue.data(result.contacts);
      await cache.writeContactsList(result.contacts);
    } catch (_) {}
  }

  Future<void> search(String query) async {
    _endCursor = null;
    _hasNextPage = false;
    _currentSearch = query.isEmpty ? null : query;
    if (_currentSearch == null) {
      final cache = _tryEntityCache(ref);
      final cached = cache?.readContactsList();
      if (cached != null) {
        state = AsyncValue.data(cached);
        unawaited(_refreshContacts(cache!));
        return;
      }
    }

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = await ref.read(crmRepositoryProvider.future);
      final result = await repo.getContacts(search: _currentSearch);
      _endCursor = result.endCursor;
      _hasNextPage = result.hasNextPage;
      if (_currentSearch == null) {
        final cache = _tryEntityCache(ref);
        await cache?.writeContactsList(result.contacts);
      }
      return result.contacts;
    });
  }

  bool get hasNextPage => _hasNextPage;
  bool get isLoadingMore => _isLoadingMore;

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasNextPage || _endCursor == null) return;
    final current = state.value;
    if (current == null) return;

    _isLoadingMore = true;
    try {
      final repo = await ref.read(crmRepositoryProvider.future);
      final result = await repo.getContacts(
        search: _currentSearch,
        after: _endCursor,
      );
      _endCursor = result.endCursor;
      _hasNextPage = result.hasNextPage;
      final merged = [...current, ...result.contacts];
      state = AsyncValue.data(merged);
      if (_currentSearch == null) {
        final cache = _tryEntityCache(ref);
        await cache?.writeContactsList(merged);
      }
    } finally {
      _isLoadingMore = false;
    }
  }

  Future<Contact> addContact({
    required String firstName,
    required String lastName,
    String? email,
    String? phone,
    String? jobTitle,
    String? city,
    String? linkedinUrl,
    String? xUrl,
  }) async {
    final isDemo = await ref.read(isDemoModeProvider.future);
    if (isDemo) throw Exception('Demo mode: Modification is not allowed.');

    final repo = await ref.read(crmRepositoryProvider.future);
    final newContact = await repo.createContact(
      firstName: firstName,
      lastName: lastName,
      email: email,
      phone: phone,
      jobTitle: jobTitle,
      city: city,
      linkedinUrl: linkedinUrl,
      xUrl: xUrl,
    );
    
    // Aggiorniamo ottimisticamente lo stato inserendo il nuovo contatto in cima 
    // alla lista attuale. In questo modo l'UI si aggiorna all'istante!
    final currentState = state.value;
    if (currentState != null) {
      final updated = [newContact, ...currentState];
      state = AsyncValue.data(updated);
      final cache = _tryEntityCache(ref);
      await cache?.writeContactsList(updated);
    } else {
      // Se era vuoto o in errore, forziamo il reload dal backend
      ref.invalidateSelf();
    }
    
    return newContact;
  }

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
    final isDemo = await ref.read(isDemoModeProvider.future);
    if (isDemo) throw Exception('Demo mode: Modification is not allowed.');

    final repo = await ref.read(crmRepositoryProvider.future);
    final updatedContact = await repo.updateContact(
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
    
    // Optimistic update: replace the old contact with the updated one
    final currentState = state.value;
    if (currentState != null) {
      final index = currentState.indexWhere((c) => c.id == id);
      if (index != -1) {
        final newList = [...currentState];
        // We preserve some fields like avatarUrl and company that the update 
        // mutation might not return fully, by merging with the old contact.
        // Wait, updatePerson returns the updated fields. Let's merge.
        final oldContact = newList[index];
        newList[index] = oldContact.copyWith(
          firstName: updatedContact.firstName.isNotEmpty ? updatedContact.firstName : oldContact.firstName,
          lastName: updatedContact.lastName.isNotEmpty ? updatedContact.lastName : oldContact.lastName,
          email: updatedContact.email ?? oldContact.email,
          phone: updatedContact.phone ?? oldContact.phone,
          companyId: clearCompany ? null : (updatedContact.companyId ?? oldContact.companyId),
          companyName: clearCompany ? null : (updatedContact.companyName ?? oldContact.companyName),
          jobTitle: updatedContact.jobTitle ?? oldContact.jobTitle,
          city: updatedContact.city ?? oldContact.city,
          linkedinUrl: updatedContact.linkedinUrl ?? oldContact.linkedinUrl,
          xUrl: updatedContact.xUrl ?? oldContact.xUrl,
        );
        state = AsyncValue.data(newList);
        final cache = _tryEntityCache(ref);
        await cache?.writeContactsList(newList);
      }
    }
    
    // Also invalidate the contactDetailProvider for this specific contact
    // so the detail screen gets the fresh data next time it's accessed or currently viewed.
    ref.invalidate(contactDetailProvider(id));
    
    return updatedContact;
  }

  Future<void> deleteContact(String id) async {
    final isDemo = await ref.read(isDemoModeProvider.future);
    if (isDemo) throw Exception('Demo mode: Modification is not allowed.');

    final currentState = state.value;
    List<Contact>? previousState;

    // Optimistic update
    if (currentState != null) {
      previousState = List.from(currentState);
      final newList = currentState.where((c) => c.id != id).toList();
      state = AsyncValue.data(newList);
    }

    try {
      final repo = await ref.read(crmRepositoryProvider.future);
      await repo.deleteContact(id);

      // Invalidate related providers or detail providers
      ref.invalidate(contactDetailProvider(id));
      final cache = _tryEntityCache(ref);
      if (cache != null && state.value != null) {
        await cache.writeContactsList(state.value!);
        await cache.deleteContactDetail(id);
      }
    } catch (e) {
      // Revert optimistic update on error
      if (previousState != null) {
        state = AsyncValue.data(previousState);
      } else {
        ref.invalidateSelf();
      }
      rethrow;
    }
  }
}

@riverpod
class ContactDetail extends _$ContactDetail {
  bool _isDisposed = false;

  @override
  FutureOr<Contact> build(String id) async {
    _isDisposed = false;
    ref.onDispose(() => _isDisposed = true);
    final cache = _tryEntityCache(ref);
    final cached = cache?.readContactDetail(id);
    if (cached != null) {
      unawaited(_refreshContactDetail(id, cache!));
      return cached;
    }

    final repo = await ref.watch(crmRepositoryProvider.future);
    final contact = await repo.getContactById(id);
    await cache?.writeContactDetail(contact);
    return contact;
  }

  Future<void> _refreshContactDetail(String id, EntityCache cache) async {
    try {
      final repo = await ref.read(crmRepositoryProvider.future);
      final contact = await repo.getContactById(id);
      if (_isDisposed) return;
      state = AsyncValue.data(contact);
      await cache.writeContactDetail(contact);
    } catch (_) {}
  }
}

@riverpod
class ContactNotes extends _$ContactNotes {
  bool _isDisposed = false;

  @override
  FutureOr<List<Note>> build(String id) async {
    _isDisposed = false;
    ref.onDispose(() => _isDisposed = true);
    final cache = _tryEntityCache(ref);
    final cached = cache?.readContactNotes(id);
    if (cached != null) {
      unawaited(_refreshNotes(id, cache!));
      return cached;
    }

    final repo = await ref.watch(crmRepositoryProvider.future);
    final notes = await repo.getNotesByContact(id);
    await cache?.writeContactNotes(id, notes);
    return notes;
  }

  Future<void> _refreshNotes(String contactId, EntityCache cache) async {
    try {
      final repo = await ref.read(crmRepositoryProvider.future);
      final notes = await repo.getNotesByContact(contactId);
      if (_isDisposed) return;
      state = AsyncValue.data(notes);
      await cache.writeContactNotes(contactId, notes);
    } catch (_) {}
  }

  Future<Note> updateNote(String noteId, String body, {DateTime? dueAt}) async {
    final isDemo = await ref.read(isDemoModeProvider.future);
    if (isDemo) throw Exception('Demo mode: Modification is not allowed.');

    final repo = await ref.read(crmRepositoryProvider.future);
    final updatedNote = await repo.updateNote(noteId, body: body, dueAt: dueAt);

    final currentState = state.value;
    if (currentState != null) {
      final index = currentState.indexWhere((n) => n.id == noteId);
      if (index != -1) {
        final newList = [...currentState];
        newList[index] = updatedNote;
        state = AsyncValue.data(newList);
        final cache = _tryEntityCache(ref);
        await cache?.writeContactNotes(id, newList);
      }
    }

    return updatedNote;
  }

  Future<Note> addNote(String contactId, String body, {DateTime? dueAt}) async {
    final isDemo = await ref.read(isDemoModeProvider.future);
    if (isDemo) throw Exception('Demo mode: Modification is not allowed.');

    final repo = await ref.read(crmRepositoryProvider.future);
    final newNote = await repo.createNote(
      contactId: contactId,
      body: body,
      dueAt: dueAt,
    );

    final currentState = state.value;
    if (currentState != null) {
      final newList = [newNote, ...currentState];
      state = AsyncValue.data(newList);
      final cache = _tryEntityCache(ref);
      await cache?.writeContactNotes(id, newList);
    } else {
      ref.invalidateSelf();
    }

    return newNote;
  }

  Future<void> deleteNote(String noteId) async {
    final isDemo = await ref.read(isDemoModeProvider.future);
    if (isDemo) throw Exception('Demo mode: Modification is not allowed.');

    final currentState = state.value;
    List<Note>? previousState;

    if (currentState != null) {
      previousState = List.from(currentState);
      final newList = currentState.where((n) => n.id != noteId).toList();
      state = AsyncValue.data(newList);
    }

    try {
      final repo = await ref.read(crmRepositoryProvider.future);
      await repo.deleteNote(noteId);
      final cache = _tryEntityCache(ref);
      if (cache != null && state.value != null) {
        await cache.writeContactNotes(id, state.value!);
        await cache.deleteNoteDetail(noteId);
      }
    } catch (e) {
      if (previousState != null) {
        state = AsyncValue.data(previousState);
      } else {
        ref.invalidateSelf();
      }
      rethrow;
    }
  }
}


@riverpod
class CompanyDetail extends _$CompanyDetail {
  bool _isDisposed = false;

  @override
  FutureOr<Company> build(String id) async {
    _isDisposed = false;
    ref.onDispose(() => _isDisposed = true);
    final cache = _tryEntityCache(ref);
    final cached = cache?.readCompanyDetail(id);
    if (cached != null) {
      unawaited(_refreshCompanyDetail(id, cache!));
      return cached;
    }

    final repo = await ref.watch(crmRepositoryProvider.future);
    final company = await repo.getCompanyById(id);
    await cache?.writeCompanyDetail(company);
    return company;
  }

  Future<void> _refreshCompanyDetail(String id, EntityCache cache) async {
    try {
      final repo = await ref.read(crmRepositoryProvider.future);
      final company = await repo.getCompanyById(id);
      if (_isDisposed) return;
      state = AsyncValue.data(company);
      await cache.writeCompanyDetail(company);
    } catch (_) {}
  }
}

@riverpod
class CompanyNotes extends _$CompanyNotes {
  bool _isDisposed = false;

  @override
  FutureOr<List<Note>> build(String id) async {
    _isDisposed = false;
    ref.onDispose(() => _isDisposed = true);
    final cache = _tryEntityCache(ref);
    final cached = cache?.readCompanyNotes(id);
    if (cached != null) {
      unawaited(_refreshNotes(id, cache!));
      return cached;
    }

    final repo = await ref.watch(crmRepositoryProvider.future);
    final notes = await repo.getNotesByCompany(id);
    await cache?.writeCompanyNotes(id, notes);
    return notes;
  }

  Future<void> _refreshNotes(String companyId, EntityCache cache) async {
    try {
      final repo = await ref.read(crmRepositoryProvider.future);
      final notes = await repo.getNotesByCompany(companyId);
      if (_isDisposed) return;
      state = AsyncValue.data(notes);
      await cache.writeCompanyNotes(companyId, notes);
    } catch (_) {}
  }

  Future<Note> updateNote(String noteId, String body, {DateTime? dueAt}) async {
    final isDemo = await ref.read(isDemoModeProvider.future);
    if (isDemo) throw Exception('Demo mode: Modification is not allowed.');

    final repo = await ref.read(crmRepositoryProvider.future);
    final updatedNote = await repo.updateNote(noteId, body: body, dueAt: dueAt);

    final currentState = state.value;
    if (currentState != null) {
      final index = currentState.indexWhere((n) => n.id == noteId);
      if (index != -1) {
        final newList = [...currentState];
        newList[index] = updatedNote;
        state = AsyncValue.data(newList);
        final cache = _tryEntityCache(ref);
        await cache?.writeCompanyNotes(id, newList);
      }
    }

    return updatedNote;
  }

  Future<Note> addNote(String companyId, String body, {DateTime? dueAt}) async {
    final isDemo = await ref.read(isDemoModeProvider.future);
    if (isDemo) throw Exception('Demo mode: Modification is not allowed.');

    final repo = await ref.read(crmRepositoryProvider.future);
    final newNote = await repo.createNote(
      companyId: companyId,
      body: body,
      dueAt: dueAt,
    );

    final currentState = state.value;
    if (currentState != null) {
      final newList = [newNote, ...currentState];
      state = AsyncValue.data(newList);
      final cache = _tryEntityCache(ref);
      await cache?.writeCompanyNotes(id, newList);
    } else {
      ref.invalidateSelf();
    }

    return newNote;
  }

  Future<void> deleteNote(String noteId) async {
    final isDemo = await ref.read(isDemoModeProvider.future);
    if (isDemo) throw Exception('Demo mode: Modification is not allowed.');

    final currentState = state.value;
    List<Note>? previousState;

    if (currentState != null) {
      previousState = List.from(currentState);
      final newList = currentState.where((n) => n.id != noteId).toList();
      state = AsyncValue.data(newList);
    }

    try {
      final repo = await ref.read(crmRepositoryProvider.future);
      await repo.deleteNote(noteId);
      final cache = _tryEntityCache(ref);
      if (cache != null && state.value != null) {
        await cache.writeCompanyNotes(id, state.value!);
        await cache.deleteNoteDetail(noteId);
      }
    } catch (e) {
      if (previousState != null) {
        state = AsyncValue.data(previousState);
      } else {
        ref.invalidateSelf();
      }
      rethrow;
    }
  }
}

@riverpod
class CompanyContacts extends _$CompanyContacts {
  @override
  FutureOr<List<Contact>> build(String id) async {
    final repo = await ref.watch(crmRepositoryProvider.future);
    return repo.getContactsByCompany(id);
  }
}

@riverpod
class TaskContacts extends _$TaskContacts {
  @override
  FutureOr<List<Contact>> build(String id) async {
    final repo = await ref.watch(crmRepositoryProvider.future);
    return repo.getContactsByTask(id);
  }
}

@Riverpod(keepAlive: true)
Future<String> currentUserName(CurrentUserNameRef ref) async {
  final repo = await ref.watch(crmRepositoryProvider.future);
  return repo.getCurrentUserName();
}

@Riverpod(keepAlive: true)
class Companies extends _$Companies {
  bool _isDisposed = false;

  @override
  FutureOr<List<Company>> build() async {
    _isDisposed = false;
    ref.onDispose(() => _isDisposed = true);
    final cache = _tryEntityCache(ref);
    final cached = cache?.readCompaniesList();
    if (cached != null) {
      unawaited(_refreshCompanies(cache!));
      return cached;
    }

    final repo = await ref.watch(crmRepositoryProvider.future);
    final companies = await repo.getCompanies();
    await cache?.writeCompaniesList(companies);
    return companies;
  }

  Future<void> _refreshCompanies(EntityCache cache) async {
    try {
      final repo = await ref.read(crmRepositoryProvider.future);
      final companies = await repo.getCompanies();
      if (_isDisposed) return;
      state = AsyncValue.data(companies);
      await cache.writeCompaniesList(companies);
    } catch (_) {}
  }

  Future<void> search(String query) async {
    if (query.isEmpty) {
      final cache = _tryEntityCache(ref);
      final cached = cache?.readCompaniesList();
      if (cached != null) {
        state = AsyncValue.data(cached);
        unawaited(_refreshCompanies(cache!));
        return;
      }
    }

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = await ref.watch(crmRepositoryProvider.future);
      final companies = await repo.getCompanies(search: query);
      if (query.isEmpty) {
        final cache = _tryEntityCache(ref);
        await cache?.writeCompaniesList(companies);
      }
      return companies;
    });
  }

  Future<Company> addCompany({required String name, String? domainName}) async {
    final isDemo = await ref.read(isDemoModeProvider.future);
    if (isDemo) throw Exception('Demo mode: Modification is not allowed.');

    final repo = await ref.read(crmRepositoryProvider.future);
    final newCompany = await repo.createCompany(name: name, domainName: domainName);

    final currentState = state.value;
    if (currentState != null) {
      final updated = [newCompany, ...currentState];
      state = AsyncValue.data(updated);
      final cache = _tryEntityCache(ref);
      await cache?.writeCompaniesList(updated);
    } else {
      ref.invalidateSelf();
    }

    return newCompany;
  }

  Future<Company> updateCompany(String id, {String? name, String? domainName}) async {
    final isDemo = await ref.read(isDemoModeProvider.future);
    if (isDemo) throw Exception('Demo mode: Modification is not allowed.');

    final repo = await ref.read(crmRepositoryProvider.future);
    final updatedCompany = await repo.updateCompany(id, name: name, domainName: domainName);

    final currentState = state.value;
    if (currentState != null) {
      final index = currentState.indexWhere((c) => c.id == id);
      if (index != -1) {
        final newList = [...currentState];
        newList[index] = updatedCompany;
        state = AsyncValue.data(newList);
        final cache = _tryEntityCache(ref);
        await cache?.writeCompaniesList(newList);
      }
    }

    ref.invalidate(companyDetailProvider(id));
    return updatedCompany;
  }

  Future<void> deleteCompany(String id) async {
    final isDemo = await ref.read(isDemoModeProvider.future);
    if (isDemo) throw Exception('Demo mode: Modification is not allowed.');

    final currentState = state.value;
    List<Company>? previousState;

    if (currentState != null) {
      previousState = List.from(currentState);
      final newList = currentState.where((c) => c.id != id).toList();
      state = AsyncValue.data(newList);
    }

    try {
      final repo = await ref.read(crmRepositoryProvider.future);
      await repo.deleteCompany(id);

      ref.invalidate(companyDetailProvider(id));
      // Also potentially invalidate related contacts? (if they had this company linked)
      final cache = _tryEntityCache(ref);
      if (cache != null && state.value != null) {
        await cache.writeCompaniesList(state.value!);
        await cache.deleteCompanyDetail(id);
      }
    } catch (e) {
      if (previousState != null) {
        state = AsyncValue.data(previousState);
      } else {
        ref.invalidateSelf();
      }
      rethrow;
    }
  }
}

@riverpod
class TaskFilter extends _$TaskFilter {
  @override
  bool build() => false; // false = TODO, true = DONE

  void toggle() => state = !state;
}

@riverpod
class Tasks extends _$Tasks {
  bool _isDisposed = false;

  @override
  FutureOr<List<Task>> build() async {
    final filter = ref.watch(taskFilterProvider);
    _isDisposed = false;
    ref.onDispose(() => _isDisposed = true);
    final cache = _tryEntityCache(ref);
    final cached = cache?.readTasksList(completed: filter);
    if (cached != null) {
      unawaited(_refreshTasks(filter, cache!));
      return cached;
    }

    final repo = await ref.watch(crmRepositoryProvider.future);
    final tasks = await repo.getTasks(completed: filter);
    await cache?.writeTasksList(completed: filter, tasks: tasks);
    return tasks;
  }

  Future<void> _refreshTasks(bool completed, EntityCache cache) async {
    try {
      final repo = await ref.read(crmRepositoryProvider.future);
      final tasks = await repo.getTasks(completed: completed);
      if (_isDisposed) return;
      state = AsyncValue.data(tasks);
      await cache.writeTasksList(completed: completed, tasks: tasks);
    } catch (_) {}
  }


  Future<Task> addTask(
    String title, {
    String? body,
    DateTime? dueAt,
    String? contactId,
  }) async {
    final isDemo = await ref.read(isDemoModeProvider.future);
    if (isDemo) throw Exception('Demo mode: Modification is not allowed.');

    final repo = await ref.read(crmRepositoryProvider.future);
    final newTask = await repo.createTask(
      title: title,
      body: (body != null && body.trim().isNotEmpty) ? body.trim() : null,
      dueAt: dueAt,
      contactId: contactId,
    );
    
    // Aggiorniamo ottimisticamente lo stato inserendo il nuovo task in cima 
    final currentState = state.value;
    if (currentState != null) {
      final updated = [newTask, ...currentState];
      state = AsyncValue.data(updated);
      final filter = ref.read(taskFilterProvider);
      final cache = _tryEntityCache(ref);
      await cache?.writeTasksList(completed: filter, tasks: updated);
    } else {
      ref.invalidateSelf();
    }
    
    await NotificationService().scheduleTaskReminder(newTask);

    return newTask;
  }

  Future<Task> updateTask(String id, {String? title, String? body, DateTime? dueAt, bool clearDueDate = false, bool? completed}) async {
    final isDemo = await ref.read(isDemoModeProvider.future);
    if (isDemo) throw Exception('Demo mode: Modification is not allowed.');

    final repo = await ref.read(crmRepositoryProvider.future);
    final updatedTask = await repo.updateTask(
      id,
      title: title,
      body: body,
      dueAt: dueAt,
      clearDueDate: clearDueDate,
      completed: completed,
    );

    final currentState = state.value;
    if (currentState != null) {
      final index = currentState.indexWhere((t) => t.id == id);
      if (index != -1) {
        final currentFilter = ref.read(taskFilterProvider);
        if (completed != null && completed != currentFilter) {
          // Se lo stato di completamento è cambiato ed è diverso dal filtro attivo,
          // rimuovi il task dalla lista attiva.
          final newList = [...currentState];
          newList.removeAt(index);
          state = AsyncValue.data(newList);
          final cache = _tryEntityCache(ref);
          await cache?.writeTasksList(completed: currentFilter, tasks: newList);
        } else {
          final newList = [...currentState];
          newList[index] = updatedTask;
          state = AsyncValue.data(newList);
          final cache = _tryEntityCache(ref);
          await cache?.writeTasksList(completed: currentFilter, tasks: newList);
        }
      }
    }

    if (updatedTask.completed == true) {
      await NotificationService().cancelTaskReminder(updatedTask.id);
    } else {
      await NotificationService().scheduleTaskReminder(updatedTask);
    }

    return updatedTask;
  }

  Future<void> deleteTask(String id) async {
    final isDemo = await ref.read(isDemoModeProvider.future);
    if (isDemo) throw Exception('Demo mode: Modification is not allowed.');

    final currentState = state.value;
    List<Task>? previousState;

    if (currentState != null) {
      previousState = List.from(currentState);
      final newList = currentState.where((t) => t.id != id).toList();
      state = AsyncValue.data(newList);
    }

    try {
      final repo = await ref.read(crmRepositoryProvider.future);
      await repo.deleteTask(id);
      await NotificationService().cancelTaskReminder(id);
      final filter = ref.read(taskFilterProvider);
      final cache = _tryEntityCache(ref);
      if (cache != null && state.value != null) {
        await cache.writeTasksList(completed: filter, tasks: state.value!);
        await cache.deleteTaskDetail(id);
      }
    } catch (e) {
      if (previousState != null) {
        state = AsyncValue.data(previousState);
      } else {
        ref.invalidateSelf();
      }
      rethrow;
    }
  }
}
