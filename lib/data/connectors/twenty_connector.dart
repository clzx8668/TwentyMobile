import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:pocketcrm/domain/models/company.dart';
import 'package:pocketcrm/domain/models/contact.dart';
import 'package:pocketcrm/domain/models/note.dart';
import 'package:pocketcrm/domain/models/task.dart';
import 'package:pocketcrm/shared/widgets/phone_input_field.dart';
import 'package:pocketcrm/core/data/country_codes.dart';
import 'package:pocketcrm/domain/repositories/crm_repository.dart';

class TwentyConnector implements CRMRepository {
  final GraphQLClient client;
  final String? baseUrl;
  final String? apiToken;
  final String? workspaceId;

  TwentyConnector({
    required this.client,
    this.baseUrl,
    this.apiToken,
    this.workspaceId,
  });

  bool _isSingleRequestLimitError(String message) {
    final msg = message.toLowerCase();
    return msg.contains('cannot be executed as a single request') ||
        (msg.contains('single request') && msg.contains('split'));
  }

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
      // ignore token parsing failures and continue without workspace header
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

  String _normalizeToken(String rawToken) =>
      rawToken.replaceAll(RegExp(r'\s+'), '');

  bool get _hasRawTransport =>
      baseUrl != null && baseUrl!.isNotEmpty && apiToken != null && apiToken!.isNotEmpty;

  Future<Map<String, dynamic>> _rawGraphQL(
    String query, {
    Map<String, dynamic>? variables,
    String source = 'raw',
  }) async {
    if (!_hasRawTransport) {
      throw Exception('Raw transport unavailable');
    }
    final client = HttpClient();
    try {
      final uri = Uri.parse('${baseUrl!}/graphql');
      final req = await client.postUrl(uri);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${apiToken!}');
      if (workspaceId != null && workspaceId!.isNotEmpty) {
        req.headers.set('x-workspace-id', workspaceId!);
      }

      final payload = <String, dynamic>{
        'query': query,
        if (variables != null) 'variables': variables,
      };
      req.add(utf8.encode(jsonEncode(payload)));
      final resp = await req.close();
      final text = await utf8.decoder.bind(resp).join();
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      if (decoded['errors'] is List && (decoded['errors'] as List).isNotEmpty) {
        final first = (decoded['errors'] as List).first;
        final message = first is Map<String, dynamic>
            ? (first['message']?.toString() ?? 'Unknown GraphQL error')
            : first.toString();
        debugPrint('TwentyMobile.Debug: rawGraphQL error [$source]: $text');
        throw Exception(message);
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }

  void _debugLogGraphQLError(QueryResult result, {String source = 'unknown'}) {
    if (!result.hasException) return;
    final exception = result.exception!;
    final gqlErrors = exception.graphqlErrors
        .map(
          (e) => {
            'message': e.message,
            'path': e.path,
            'extensions': e.extensions,
          },
        )
        .toList();
    final payload = {
      'source': source,
      'graphqlErrors': gqlErrors,
      'linkException': exception.linkException?.toString(),
      'data': result.data,
    };
    developer.log(
      'TwentyConnector GraphQL error [$source]: ${jsonEncode(payload)}',
      name: 'TwentyMobile.Debug',
      level: 1000,
    );
    debugPrint(
      'TwentyMobile.Debug: TwentyConnector GraphQL error [$source]: ${jsonEncode(payload)}',
    );
  }

  void _handleResultException(QueryResult result, {String source = 'unknown'}) {
    if (!result.hasException) return;
    _debugLogGraphQLError(result, source: source);
    
    final exception = result.exception!;
    final linkException = exception.linkException;
    
    if (linkException != null) {
      final errorStr = linkException.toString();
      if (errorStr.contains('SocketException') || 
          errorStr.contains('NetworkError') || 
          errorStr.contains('Connection closed')) {
        throw Exception('It seems there\'s no internet connection. Please check your settings.');
      }
      if (errorStr.contains('Connection refused') || 
          errorStr.contains('404') || 
          errorStr.contains('Network unreachable')) {
        throw Exception('The CRM endpoint is unreachable. Please verify the URL in settings.');
      }
      throw Exception('Connection error: $errorStr');
    }

    if (exception.graphqlErrors.isNotEmpty) {
      final error = exception.graphqlErrors.first;
      final msg = error.message.toLowerCase();
      if (msg.contains('unauthorized') || msg.contains('forbidden')) {
        throw Exception('Session expired or invalid token. Please reconnect in settings.');
      }
      throw Exception(error.message);
    }
    
    throw Exception('An unexpected error occurred while communicating with the server.');
  }

  Future<List<Task>> _getOpenTasksSimple() async {
    const String query = r'''
      query GetOpenTasksSimple {
        tasks {
          edges {
            node {
              id
              title
              status
              dueAt
              createdAt
              bodyV2 { blocknote }
            }
          }
        }
      }
    ''';
    if (_hasRawTransport) {
      try {
        final raw = await _rawGraphQL(query, source: 'getOpenTasksSimpleRaw');
        final edges = raw['data']?['tasks']?['edges'] as List? ?? [];
        return edges
            .map((e) => Task.fromTwenty(e['node'] as Map<String, dynamic>))
            .where((t) => t.completed == false)
            .toList();
      } catch (_) {}
    }
    final result = await client.query(
      QueryOptions(
        document: gql(query),
        fetchPolicy: FetchPolicy.networkOnly,
      ),
    );
    if (result.hasException) {
      _debugLogGraphQLError(result, source: 'getOpenTasksSimple');
      return [];
    }
    final edges = result.data?['tasks']?['edges'] as List? ?? [];
    return edges
        .map((e) => Task.fromTwenty(e['node'] as Map<String, dynamic>))
        .where((t) => t.completed == false)
        .toList();
  }

  Future<List<Contact>> _getContactsSimple() async {
    const String query = r'''
      query GetPeopleSimple {
        people {
          edges {
            node {
              id
              name { firstName lastName }
              emails { primaryEmail }
              phones { primaryPhoneNumber primaryPhoneCallingCode }
              avatarUrl
              city
              jobTitle
              linkedinLink { primaryLinkUrl }
              xLink { primaryLinkUrl }
              company { id name }
              createdAt
              updatedAt
            }
          }
        }
      }
    ''';
    if (_hasRawTransport) {
      try {
        final raw = await _rawGraphQL(query, source: 'getContactsSimpleRaw');
        final edges = raw['data']?['people']?['edges'] as List? ?? [];
        return edges
            .map((e) => Contact.fromTwenty(e['node'] as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    final result = await client.query(
      QueryOptions(
        document: gql(query),
        fetchPolicy: FetchPolicy.networkOnly,
      ),
    );
    if (result.hasException) {
      _debugLogGraphQLError(result, source: 'getContactsSimple');
      return [];
    }
    final edges = result.data?['people']?['edges'] as List? ?? [];
    return edges
        .map((e) => Contact.fromTwenty(e['node'] as Map<String, dynamic>))
        .toList();
  }

  Future<List<Company>> _getCompaniesSimple() async {
    const String query = r'''
      query GetCompaniesSimple {
        companies {
          edges {
            node {
              id
              name
              domainName { primaryLinkUrl }
              logoUrl
              industry
              linkedinLink { primaryLinkUrl }
              xLink { primaryLinkUrl }
              employees
              createdAt
            }
          }
        }
      }
    ''';
    if (_hasRawTransport) {
      try {
        final raw = await _rawGraphQL(query, source: 'getCompaniesSimpleRaw');
        final edges = raw['data']?['companies']?['edges'] as List? ?? [];
        return edges
            .map((e) => Company.fromTwenty(e['node'] as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    final result = await client.query(
      QueryOptions(
        document: gql(query),
        fetchPolicy: FetchPolicy.networkOnly,
      ),
    );
    if (result.hasException) {
      _debugLogGraphQLError(result, source: 'getCompaniesSimple');
      return [];
    }
    final edges = result.data?['companies']?['edges'] as List? ?? [];
    return edges
        .map((e) => Company.fromTwenty(e['node'] as Map<String, dynamic>))
        .toList();
  }

  Future<List<Note>> _getNotesByTargetSimple({
    String? personId,
    String? companyId,
  }) async {
    const String query = r'''
      query GetNotesByTargetSimple($personId: UUID, $companyId: UUID) {
        noteTargets(
          filter: {
            or: [
              { targetPersonId: { eq: $personId } }
              { targetCompanyId: { eq: $companyId } }
            ]
          }
        ) {
          edges {
            node {
              note { id bodyV2 { blocknote } createdAt }
            }
          }
        }
      }
    ''';

    final variables = <String, dynamic>{
      'personId': personId,
      'companyId': companyId,
    };

    if (_hasRawTransport) {
      try {
        final raw = await _rawGraphQL(
          query,
          variables: variables,
          source: 'getNotesByTargetSimpleRaw',
        );
        final edges = raw['data']?['noteTargets']?['edges'] as List? ?? [];
        return edges
            .map((e) => e['node']?['note'])
            .whereType<Map>()
            .map((n) => Note.fromTwenty(Map<String, dynamic>.from(n)))
            .toList();
      } catch (_) {}
    }

    final result = await client.query(
      QueryOptions(
        document: gql(query),
        variables: variables,
        fetchPolicy: FetchPolicy.networkOnly,
      ),
    );
    if (result.hasException) {
      _debugLogGraphQLError(result, source: 'getNotesByTargetSimple');
      return [];
    }
    final edges = result.data?['noteTargets']?['edges'] as List? ?? [];
    return edges
        .map((e) => e['node']?['note'])
        .whereType<Map>()
        .map((n) => Note.fromTwenty(Map<String, dynamic>.from(n)))
        .toList();
  }

  @override
  Future<bool> testConnection(String baseUrl, String apiToken) async {
    const String workspaceMembersQuery = r'''
      query Me {
        workspaceMembers(first: 1) {
          edges {
            node {
              id
            }
          }
        }
      }
    ''';

    try {
      final normalizedBaseUrl = _normalizeInstanceUrl(baseUrl);
      final normalizedToken = _normalizeToken(apiToken);
      final workspaceId = _extractWorkspaceIdFromToken(normalizedToken);
      final headers = <String, String>{
        'Authorization': 'Bearer $normalizedToken',
        if (workspaceId != null) 'x-workspace-id': workspaceId,
      };
      final tempLink = HttpLink(
        '$normalizedBaseUrl/graphql',
        useGETForQueries: false,
        defaultHeaders: headers,
      );
      
      final tempClient = GraphQLClient(
        link: tempLink, 
        cache: GraphQLCache(),
      );

      final QueryResult result = await tempClient.query(
        QueryOptions(
          document: gql(workspaceMembersQuery),
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );

      if (result.hasException) {
        final exception = result.exception!;
        if (exception.graphqlErrors.isNotEmpty) {
          final error = exception.graphqlErrors.first;
          final msg = error.message.toLowerCase();

          // Check for common auth errors
          if (msg.contains('unauthorized') || msg.contains('forbidden')) {
            throw Exception('Invalid API Token');
          }
          if (_isSingleRequestLimitError(msg)) {
            // Some Twenty deployments reject this probe query but still accept token auth.
            // Let onboarding continue and defer full compatibility checks to actual data calls.
            return true;
          }
          throw Exception(error.message);
        }
        
        if (exception.linkException != null) {
          final linkError = exception.linkException.toString();
          if (linkError.contains('404')) {
            throw Exception('URL not found. Verify your Instance URL.');
          }
          if (linkError.contains('Connection refused') || linkError.contains('SocketException')) {
            throw Exception('Server unreachable. Check your internet or URL.');
          }
          throw Exception('Network error: $linkError');
        }
        
        throw Exception('Something went wrong: ${exception.toString()}');
      }

      final edges = result.data?['workspaceMembers']?['edges'] as List?;
      if (edges == null || edges.isEmpty) {
        throw Exception('Connected, but no access to workspace member');
      }
      return true;
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<String> getCurrentUserName() async {
    if (_hasRawTransport) {
      try {
        const String rawQuery = r'''
          query Me {
            workspaceMembers(first: 1) {
              edges { node { name { firstName lastName } } }
            }
          }
        ''';
        final raw = await _rawGraphQL(rawQuery, source: 'getCurrentUserNameRaw');
        final name = raw['data']?['workspaceMembers']?['edges']?[0]?['node']?['name'];
        if (name is Map<String, dynamic>) {
          return '${name['firstName'] ?? ''} ${name['lastName'] ?? ''}'.trim();
        }
        if (name is String) return name.trim();
      } catch (_) {}
    }
    const String workspaceMembersQuery = r'''
      query Me {
        workspaceMembers(first: 1) {
          edges {
            node {
              name { firstName lastName }
            }
          }
        }
      }
    ''';
    final QueryResult result = await client.query(
      QueryOptions(document: gql(workspaceMembersQuery)),
    );
    if (result.hasException && result.exception!.graphqlErrors.isNotEmpty) {
      _debugLogGraphQLError(result, source: 'getCurrentUserName');
      final msg = result.exception!.graphqlErrors.first.message;
      if (_isSingleRequestLimitError(msg)) {
        return '';
      }
      throw Exception(msg);
    }

    final name = result.data?['workspaceMembers']?['edges']?[0]?['node']?['name'];
    if (name == null) return '';
    if (name is String) return name.trim();
    if (name is Map<String, dynamic>) {
      return '${name['firstName'] ?? ''} ${name['lastName'] ?? ''}'.trim();
    }
    return '';
  }

  @override
  Future<({List<Contact> contacts, String? endCursor, bool hasNextPage})> getContacts({
    String? search,
    int pageSize = 20,
    String? after,
  }) async {
    const String query = r'''
      query GetPeople($filter: PersonFilterInput, $first: Int, $after: String) {
        people(filter: $filter, first: $first, after: $after, orderBy: { createdAt: DescNullsLast }) {
          edges {
            node {
              id
              name { firstName lastName }
              emails { primaryEmail }
              phones { primaryPhoneNumber primaryPhoneCallingCode }
              avatarUrl
              company { id name }
              createdAt
              updatedAt
            }
          }
          pageInfo { hasNextPage endCursor }
        }
      }
    ''';

    Map<String, dynamic>? filter;
    if (search != null && search.isNotEmpty) {
      filter = {
        'or': [
          {'name': {'firstName': {'ilike': '%$search%'}}},
          {'name': {'lastName': {'ilike': '%$search%'}}},
        ],
      };
    }

    final QueryOptions options = QueryOptions(
      document: gql(query),
      variables: {
        'first': pageSize,
        if (filter != null) 'filter': filter,
        if (after != null) 'after': after,
      },
      fetchPolicy: FetchPolicy.networkOnly,
    );

    final QueryResult result = await client.query(options);
    if (result.hasException) {
      final msg = result.exception!.graphqlErrors.isNotEmpty
          ? result.exception!.graphqlErrors.first.message
          : result.exception.toString();
      if (_isSingleRequestLimitError(msg)) {
        var contacts = await _getContactsSimple();
        if (search != null && search.isNotEmpty) {
          final keyword = search.toLowerCase();
          contacts = contacts
              .where(
                (c) =>
                    c.firstName.toLowerCase().contains(keyword) ||
                    c.lastName.toLowerCase().contains(keyword),
              )
              .toList();
        }
        return (contacts: contacts, endCursor: null, hasNextPage: false);
      }
      _handleResultException(result, source: 'getContacts');
    }

    final data = result.data?['people'];
    final edges = data?['edges'] as List? ?? [];
    final pageInfo = data?['pageInfo'] as Map<String, dynamic>? ?? {};

    final contacts = edges
        .map((e) => Contact.fromTwenty(e['node'] as Map<String, dynamic>))
        .toList();

    return (
      contacts: contacts,
      endCursor: pageInfo['endCursor'] as String?,
      hasNextPage: pageInfo['hasNextPage'] as bool? ?? false,
    );
  }

  @override
  Future<Contact> getContactById(String id) async {
    const String query = r'''
      query GetPersonById($id: UUID!) {
        people(filter: { id: { eq: $id } }) {
          edges {
            node {
              id
              name { firstName lastName }
              emails { primaryEmail additionalEmails }
              phones { primaryPhoneNumber primaryPhoneCallingCode additionalPhones }
              avatarUrl
              city
              jobTitle
              linkedinLink { primaryLinkUrl }
              xLink { primaryLinkUrl }
              company { id name }
              createdAt
              updatedAt
            }
          }
        }
      }
    ''';

    final QueryOptions options = QueryOptions(
      document: gql(query),
      variables: {'id': id},
    );

    final QueryResult result = await client.query(options);
    if (result.hasException) {
      final msg = result.exception!.graphqlErrors.isNotEmpty
          ? result.exception!.graphqlErrors.first.message
          : result.exception.toString();
      if (_isSingleRequestLimitError(msg)) {
        final contacts = await _getContactsSimple();
        final match = contacts.where((c) => c.id == id).toList();
        if (match.isNotEmpty) return match.first;
        throw Exception('Contact not found');
      }
      _handleResultException(result, source: 'getContactById');
    }

    final edges = result.data?['people']?['edges'] as List?;
    if (edges == null || edges.isEmpty) throw Exception('Contact not found');

    return Contact.fromTwenty(edges.first['node'] as Map<String, dynamic>);
  }

  @override
  Future<List<Contact>> getContactsByCompany(String companyId) async {
    const String query = r'''
      query GetCompanyPeople($filter: PersonFilterInput) {
        people(filter: $filter, orderBy: { createdAt: DescNullsLast }) {
          edges {
            node {
              id
              name { firstName lastName }
              emails { primaryEmail }
              phones { primaryPhoneNumber primaryPhoneCallingCode }
              avatarUrl
              company { id name }
              createdAt
              updatedAt
            }
          }
        }
      }
    ''';

    final QueryOptions options = QueryOptions(
      document: gql(query),
      variables: {
        'filter': {
          'companyId': {'eq': companyId},
        },
      },
      fetchPolicy: FetchPolicy.networkOnly,
    );

    final QueryResult result = await client.query(options);
    if (result.hasException) {
      final msg = result.exception!.graphqlErrors.isNotEmpty
          ? result.exception!.graphqlErrors.first.message
          : result.exception.toString();
      if (_isSingleRequestLimitError(msg)) {
        final contacts = await _getContactsSimple();
        return contacts.where((c) => c.companyId == companyId).toList();
      }
      _handleResultException(result, source: 'getContactsByCompany');
    }

    final edges = result.data?['people']?['edges'] as List?;
    if (edges == null) return [];

    return edges
        .map((e) => Contact.fromTwenty(e['node'] as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Contact>> getContactsByTask(String taskId) async {
    const String query = r'''
      query GetTaskTargets($filter: TaskTargetFilterInput) {
        taskTargets(filter: $filter) {
          edges {
            node {
              targetPerson {
                id
                name { firstName lastName }
                emails { primaryEmail }
                phones { primaryPhoneNumber primaryPhoneCallingCode }
                avatarUrl
                company { id name }
                createdAt
                updatedAt
              }
            }
          }
        }
      }
    ''';

    final QueryOptions options = QueryOptions(
      document: gql(query),
      variables: {
        'filter': {
          'taskId': {'eq': taskId},
        },
      },
      fetchPolicy: FetchPolicy.networkOnly,
    );

    final QueryResult result = await client.query(options);
    _handleResultException(result, source: 'getContactsByTask');

    final edges = result.data?['taskTargets']?['edges'] as List?;
    if (edges == null) return [];

    return edges
        .where((e) => e['node']?['targetPerson'] != null)
        .map((e) => Contact.fromTwenty(e['node']['targetPerson'] as Map<String, dynamic>))
        .toList();
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
    const String mutation = r'''
      mutation CreatePerson($input: PersonCreateInput!) {
        createPerson(data: $input) {
          id
          name { firstName lastName }
          emails { primaryEmail }
          city
          jobTitle
          linkedinLink { primaryLinkUrl }
          xLink { primaryLinkUrl }
        }
      }
    ''';

    String? phoneCountryCode;
    if (phone != null) {
      final parsed = PhoneInputField.parseE164(phone);
      final match = countryCodes.where((c) => c.dialCode == parsed.$1).toList();
      if (match.isNotEmpty) {
        phoneCountryCode = match.first.isoCode;
      }
    }

    final input = {
      'name': {'firstName': firstName, 'lastName': lastName},
      if (email != null) 'emails': {'primaryEmail': email},
      if (phone != null) 'phones': {
        'primaryPhoneNumber': phone,
        if (phoneCountryCode != null) 'primaryPhoneCountryCode': phoneCountryCode,
      },
      if (jobTitle != null && jobTitle.isNotEmpty) 'jobTitle': jobTitle,
      if (city != null && city.isNotEmpty) 'city': city,
      if (linkedinUrl != null && linkedinUrl.isNotEmpty)
        'linkedinLink': {'primaryLinkUrl': linkedinUrl},
      if (xUrl != null && xUrl.isNotEmpty) 'xLink': {'primaryLinkUrl': xUrl},
    };

    final MutationOptions options = MutationOptions(
      document: gql(mutation),
      variables: {'input': input},
    );

    final QueryResult result = await client.mutate(options);
    _handleResultException(result, source: 'createContact');

    return Contact.fromTwenty(
      result.data?['createPerson'] as Map<String, dynamic>,
    );
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
    const String mutation = r'''
      mutation UpdatePerson($id: UUID!, $input: PersonUpdateInput!) {
        updatePerson(id: $id, data: $input) {
          id
          name { firstName lastName }
          emails { primaryEmail }
          phones { primaryPhoneNumber primaryPhoneCallingCode }
          city
          jobTitle
          linkedinLink { primaryLinkUrl }
          xLink { primaryLinkUrl }
          company { id name }
        }
      }
    ''';

    final input = <String, dynamic>{};
    if (firstName != null || lastName != null) {
      input['name'] = {
        if (firstName != null) 'firstName': firstName,
        if (lastName != null) 'lastName': lastName,
      };
    }
    if (email != null) {
      input['emails'] = {'primaryEmail': email};
    }
    if (phone != null) {
      String? phoneCountryCode;
      final parsed = PhoneInputField.parseE164(phone);
      final match = countryCodes.where((c) => c.dialCode == parsed.$1).toList();
      if (match.isNotEmpty) {
        phoneCountryCode = match.first.isoCode;
      }

      input['phones'] = {
        'primaryPhoneNumber': phone,
        if (phoneCountryCode != null) 'primaryPhoneCountryCode': phoneCountryCode,
      };
    }
    if (clearCompany) {
      input['companyId'] = null;
    } else if (companyId != null) {
      input['companyId'] = companyId;
    }
    if (jobTitle != null) {
      input['jobTitle'] = jobTitle.isEmpty ? null : jobTitle;
    }
    if (city != null) {
      input['city'] = city.isEmpty ? null : city;
    }
    if (linkedinUrl != null) {
      input['linkedinLink'] = linkedinUrl.isEmpty ? null : {'primaryLinkUrl': linkedinUrl};
    }
    if (xUrl != null) {
      input['xLink'] = xUrl.isEmpty ? null : {'primaryLinkUrl': xUrl};
    }

    final MutationOptions options = MutationOptions(
      document: gql(mutation),
      variables: {'id': id, 'input': input},
    );

    final QueryResult result = await client.mutate(options);
    _handleResultException(result, source: 'updateContact');

    return Contact.fromTwenty(
      result.data?['updatePerson'] as Map<String, dynamic>,
    );
  }

  @override
  Future<void> deleteContact(String id) async {
    const String mutation = r'''
      mutation DeletePerson($id: UUID!) {
        deletePerson(id: $id) { id }
      }
    ''';

    final MutationOptions options = MutationOptions(
      document: gql(mutation),
      variables: {'id': id},
    );

    final QueryResult result = await client.mutate(options);
    _handleResultException(result, source: 'deleteContact');
  }

  @override
  Future<Company> createCompany({required String name, String? domainName}) async {
    const String mutation = r'''
      mutation CreateCompany($input: CompanyCreateInput!) {
        createCompany(data: $input) {
          id
          name
          domainName { primaryLinkUrl }
          createdAt
        }
      }
    ''';

    final input = <String, dynamic>{
      'name': name,
    };
    if (domainName != null && domainName.isNotEmpty) {
      input['domainName'] = {'primaryLinkUrl': domainName};
    }

    final MutationOptions options = MutationOptions(
      document: gql(mutation),
      variables: {'input': input},
    );

    final QueryResult result = await client.mutate(options);
    _handleResultException(result, source: 'createCompany');

    final data = result.data?['createCompany'];
    if (data == null) throw Exception('Failed to create company');

    return Company.fromTwenty(data as Map<String, dynamic>);
  }

  @override
  Future<Company> updateCompany(String id, {String? name, String? domainName}) async {
    const String mutation = r'''
      mutation UpdateCompany($id: UUID!, $input: CompanyUpdateInput!) {
        updateCompany(id: $id, data: $input) {
          id
          name
          domainName { primaryLinkUrl }
          createdAt
        }
      }
    ''';

    final input = <String, dynamic>{};
    if (name != null) input['name'] = name;
    if (domainName != null) {
       // Support clearing domain by providing empty string
       input['domainName'] = domainName.isEmpty ? null : {'primaryLinkUrl': domainName};
    }

    final MutationOptions options = MutationOptions(
      document: gql(mutation),
      variables: {'id': id, 'input': input},
    );

    final QueryResult result = await client.mutate(options);
    _handleResultException(result, source: 'updateCompany');

    return Company.fromTwenty(
      result.data?['updateCompany'] as Map<String, dynamic>,
    );
  }

  @override
  Future<void> deleteCompany(String id) async {
    const String mutation = r'''
      mutation DeleteCompany($id: UUID!) {
        deleteCompany(id: $id) { id }
      }
    ''';

    final MutationOptions options = MutationOptions(
      document: gql(mutation),
      variables: {'id': id},
    );

    final QueryResult result = await client.mutate(options);
    _handleResultException(result, source: 'deleteCompany');
  }

  @override
  Future<List<Company>> getCompanies({String? search, int page = 1}) async {
    const String query = r'''
      query GetCompanies($filter: CompanyFilterInput, $first: Int) {
        companies(filter: $filter, first: $first, orderBy: { createdAt: DescNullsLast }) {
          edges {
            node {
              id
              name
              domainName { primaryLinkUrl }
              logoUrl
              industry
              linkedinLink { primaryLinkUrl }
              xLink { primaryLinkUrl }
              employees
              createdAt
            }
          }
        }
      }
    ''';

    Map<String, dynamic>? filter;
    if (search != null && search.isNotEmpty) {
      filter = {
        'or': [
          {'name': {'like': '%$search%'}},
          {'domainName': {'primaryLinkUrl': {'like': '%$search%'}}},
        ],
      };
    }

    final QueryOptions options = QueryOptions(
      document: gql(query),
      variables: {'first': 20, if (filter != null) 'filter': filter},
      fetchPolicy: FetchPolicy.networkOnly,
    );

    final QueryResult result = await client.query(options);
    if (result.hasException) {
      final msg = result.exception!.graphqlErrors.isNotEmpty
          ? result.exception!.graphqlErrors.first.message
          : result.exception.toString();
      if (_isSingleRequestLimitError(msg)) {
        var companies = await _getCompaniesSimple();
        if (search != null && search.isNotEmpty) {
          final keyword = search.toLowerCase();
          companies = companies
              .where((c) => c.name.toLowerCase().contains(keyword))
              .toList();
        }
        return companies;
      }
      _handleResultException(result, source: 'getCompanies');
    }

    final edges = result.data?['companies']?['edges'] as List?;
    if (edges == null) return [];

    return edges
        .map((e) => Company.fromTwenty(e['node'] as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Company> getCompanyById(String id) async {
    const String query = r'''
      query GetCompanyById($id: UUID!) {
        companies(filter: { id: { eq: $id } }) {
          edges {
            node {
              id
              name
              domainName { primaryLinkUrl }
              logoUrl
              industry
              linkedinLink { primaryLinkUrl }
              xLink { primaryLinkUrl }
              employees
              createdAt
            }
          }
        }
      }
    ''';

    final QueryOptions options = QueryOptions(
      document: gql(query),
      variables: {'id': id},
      fetchPolicy: FetchPolicy.networkOnly,
    );

    final QueryResult result = await client.query(options);
    if (result.hasException) {
      final msg = result.exception!.graphqlErrors.isNotEmpty
          ? result.exception!.graphqlErrors.first.message
          : result.exception.toString();
      if (_isSingleRequestLimitError(msg)) {
        final companies = await _getCompaniesSimple();
        final match = companies.where((c) => c.id == id).toList();
        if (match.isNotEmpty) return match.first;
        throw Exception('Company not found');
      }
      _handleResultException(result, source: 'getCompanyById');
    }

    final edges = result.data?['companies']?['edges'] as List?;
    if (edges == null || edges.isEmpty) throw Exception('Company not found');

    return Company.fromTwenty(edges.first['node'] as Map<String, dynamic>);
  }

  @override
  Future<List<Note>> getNotesByCompany(String companyId) async {
    const String query = r'''
      query GetNotesByCompany($companyId: UUID!) {
        noteTargets(filter: { targetCompanyId: { eq: $companyId } },
                    orderBy: { createdAt: DescNullsLast }) {
          edges {
            node {
              note { id bodyV2 { blocknote } createdAt updatedAt }
            }
          }
        }
      }
    ''';

    final QueryOptions options = QueryOptions(
      document: gql(query),
      variables: {'companyId': companyId},
      fetchPolicy: FetchPolicy.networkOnly,
    );

    final QueryResult result = await client.query(options);
    if (result.hasException) {
      final msg = result.exception!.graphqlErrors.isNotEmpty
          ? result.exception!.graphqlErrors.first.message
          : result.exception.toString();
      if (_isSingleRequestLimitError(msg)) {
        return _getNotesByTargetSimple(companyId: companyId);
      }
      _handleResultException(result, source: 'getNotesByCompany');
    }

    final edges = result.data?['noteTargets']?['edges'] as List?;
    if (edges == null) return [];

    return edges
        .map((e) {
          final node = e['node'];
          if (node == null || node['note'] == null) return null;
          return Note.fromTwenty(node['note'] as Map<String, dynamic>);
        })
        .where((e) => e != null)
        .cast<Note>()
        .toList();
  }

  @override
  Future<List<Note>> getNotesByContact(String contactId) async {
    const String query = r'''
      query GetNotesByPerson($personId: UUID!) {
        noteTargets(filter: { targetPersonId: { eq: $personId } },
                    orderBy: { createdAt: DescNullsLast }) {
          edges {
            node {
              note { id bodyV2 { blocknote } createdAt updatedAt }
            }
          }
        }
      }
    ''';

    final QueryOptions options = QueryOptions(
      document: gql(query),
      variables: {'personId': contactId},
      fetchPolicy: FetchPolicy.networkOnly,
    );

    final QueryResult result = await client.query(options);
    if (result.hasException) {
      final msg = result.exception!.graphqlErrors.isNotEmpty
          ? result.exception!.graphqlErrors.first.message
          : result.exception.toString();
      if (_isSingleRequestLimitError(msg)) {
        return _getNotesByTargetSimple(personId: contactId);
      }
      _handleResultException(result, source: 'getNotesByContact');
    }

    final edges = result.data?['noteTargets']?['edges'] as List?;
    if (edges == null) return [];

    return edges
        .map((e) {
          final node = e['node'];
          if (node == null || node['note'] == null) return null;
          return Note.fromTwenty(node['note'] as Map<String, dynamic>);
        })
        .where((e) => e != null)
        .cast<Note>()
        .toList();
  }

  @override
  Future<Note> createNote({
    String? contactId,
    String? companyId,
    required String body,
    DateTime? dueAt, // Kept in interface but ignored for GraphQL Note
  }) async {
    final normalizedContactId = contactId?.trim();
    final normalizedCompanyId = companyId?.trim();
    final hasContact = normalizedContactId != null && normalizedContactId.isNotEmpty;
    final hasCompany = normalizedCompanyId != null && normalizedCompanyId.isNotEmpty;
    if (hasContact == hasCompany) {
      throw Exception('Exactly one of contactId or companyId must be provided.');
    }

    const String mutation = r'''
      mutation CreateNote($input: NoteCreateInput!) {
        createNote(data: $input) { id }
      }
    ''';

    final blockNodeJson = jsonEncode([
      {
        "type": "paragraph",
        "content": [
          {"type": "text", "text": body, "styles": {}}
        ]
      }
    ]);

    final input = <String, dynamic>{
      'bodyV2': {
        'blocknote': blockNodeJson,
      }
    };

    String noteId;
    if (_hasRawTransport) {
      try {
        final raw = await _rawGraphQL(
          mutation,
          variables: {'input': input},
          source: 'createNoteRaw',
        );
        final rawId = raw['data']?['createNote']?['id'];
        if (rawId is String && rawId.isNotEmpty) {
          noteId = rawId;
        } else {
          throw Exception('Invalid createNote response');
        }
      } catch (_) {
        final MutationOptions options = MutationOptions(
          document: gql(mutation),
          variables: {'input': input},
        );
        final QueryResult result = await client.mutate(options);
        _handleResultException(result, source: 'createNote');
        final data = result.data?['createNote'] as Map<String, dynamic>?;
        noteId = data?['id'] as String? ?? '';
        if (noteId.isEmpty) {
          throw Exception('createNote returned empty id');
        }
      }
    } else {
      final MutationOptions options = MutationOptions(
        document: gql(mutation),
        variables: {'input': input},
      );
      final QueryResult result = await client.mutate(options);
      _handleResultException(result, source: 'createNote');
      final data = result.data?['createNote'] as Map<String, dynamic>?;
      noteId = data?['id'] as String? ?? '';
      if (noteId.isEmpty) {
        throw Exception('createNote returned empty id');
      }
    }

    const String targetMutation = r'''
      mutation CreateNoteTarget($input: NoteTargetCreateInput!) {
        createNoteTarget(data: $input) { id }
      }
    ''';
    final targetInput = <String, dynamic>{
      'noteId': noteId,
      if (hasContact) 'targetPersonId': normalizedContactId,
      if (hasCompany) 'targetCompanyId': normalizedCompanyId,
    };
    if (_hasRawTransport) {
      try {
        await _rawGraphQL(
          targetMutation,
          variables: {'input': targetInput},
          source: 'createNoteTargetRaw',
        );
      } catch (_) {
        final MutationOptions targetOptions = MutationOptions(
          document: gql(targetMutation),
          variables: {'input': targetInput},
        );
        final targetResult = await client.mutate(targetOptions);
        if (targetResult.hasException) {
          try {
            await deleteNote(noteId);
          } catch (_) {}
          _handleResultException(targetResult, source: 'createNoteTarget');
        }
      }
    } else {
      final MutationOptions targetOptions = MutationOptions(
        document: gql(targetMutation),
        variables: {'input': targetInput},
      );
      final targetResult = await client.mutate(targetOptions);
      if (targetResult.hasException) {
        try {
          await deleteNote(noteId);
        } catch (_) {}
        _handleResultException(targetResult, source: 'createNoteTarget');
      }
    }

    return Note(
      id: noteId,
      body: body,
      contactId: hasContact ? normalizedContactId : null,
      companyId: hasCompany ? normalizedCompanyId : null,
      dueAt: dueAt,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<Note> updateNote(
    String id, {
    required String body,
    DateTime? dueAt, // Kept in interface but ignored for GraphQL Note
  }) async {
    const String mutation = r'''
      mutation UpdateNote($id: UUID!, $input: NoteUpdateInput!) {
        updateNote(id: $id, data: $input) { id bodyV2 { blocknote } createdAt }
      }
    ''';

    final blockNodeJson = jsonEncode([
      {
        "type": "paragraph",
        "content": [
          {"type": "text", "text": body, "styles": {}}
        ]
      }
    ]);

    final input = <String, dynamic>{
      'bodyV2': {
        'blocknote': blockNodeJson,
      }
    };

    final MutationOptions options = MutationOptions(
      document: gql(mutation),
      variables: {'id': id, 'input': input},
    );

    final QueryResult result = await client.mutate(options);
    _handleResultException(result, source: 'updateNote');

    return Note.fromTwenty(
      result.data?['updateNote'] as Map<String, dynamic>,
    );
  }

  @override
  Future<void> deleteNote(String id) async {
    const String mutation = r'''
      mutation DeleteNote($id: UUID!) {
        deleteNote(id: $id) { id }
      }
    ''';

    if (_hasRawTransport) {
      try {
        await _rawGraphQL(
          mutation,
          variables: {'id': id},
          source: 'deleteNoteRaw',
        );
        return;
      } catch (_) {}
    }

    final MutationOptions options = MutationOptions(
      document: gql(mutation),
      variables: {'id': id},
    );

    final QueryResult result = await client.mutate(options);
    _handleResultException(result, source: 'deleteNote');
  }

  @override
  Future<List<Task>> getOverdueTasks() async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    final String query = '''
      query GetOverdueTasks {
        tasks(
          filter: {
            and: [
              { dueAt: { lt: "${startOfToday.toIso8601String()}" } }
              { status: { neq: DONE } }
            ]
          }
          orderBy: { dueAt: AscNullsLast }
        ) {
          edges { node { id title status dueAt } }
        }
      }
    ''';

    final options = QueryOptions(
      document: gql(query),
      fetchPolicy: FetchPolicy.networkOnly,
    );

    final result = await client.query(options);

    if (result.hasException) {
      final msg = result.exception!.graphqlErrors.isNotEmpty
          ? result.exception!.graphqlErrors.first.message
          : result.exception.toString();
      if (_isSingleRequestLimitError(msg)) {
        final allOpenTasks = await _getOpenTasksSimple();
        return allOpenTasks
            .where((t) => t.dueAt != null && t.dueAt!.isBefore(startOfToday))
            .toList();
      }
      _debugLogGraphQLError(result, source: 'getOverdueTasks');
      throw Exception(result.exception.toString());
    }

    final edges = result.data?['tasks']?['edges'] as List?;
    if (edges == null) return [];

    return edges
        .map((e) => Task.fromTwenty(e['node'] as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Task>> getTodayTasks() async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));

    final String query = '''
      query GetTodayTasks {
        tasks(
          filter: {
            and: [
              { dueAt: { gte: "${startOfToday.toIso8601String()}" } }
              { dueAt: { lt: "${endOfToday.toIso8601String()}" } }
              { status: { neq: DONE } }
            ]
          }
          orderBy: { dueAt: AscNullsLast }
        ) {
          edges { node { id title status dueAt } }
        }
      }
    ''';

    final options = QueryOptions(
      document: gql(query),
      fetchPolicy: FetchPolicy.networkOnly,
    );

    final result = await client.query(options);

    if (result.hasException) {
      final msg = result.exception!.graphqlErrors.isNotEmpty
          ? result.exception!.graphqlErrors.first.message
          : result.exception.toString();
      if (_isSingleRequestLimitError(msg)) {
        final allOpenTasks = await _getOpenTasksSimple();
        return allOpenTasks
            .where(
              (t) =>
                  t.dueAt != null &&
                  !t.dueAt!.isBefore(startOfToday) &&
                  t.dueAt!.isBefore(endOfToday),
            )
            .toList();
      }
      _debugLogGraphQLError(result, source: 'getTodayTasks');
      throw Exception(result.exception.toString());
    }

    final edges = result.data?['tasks']?['edges'] as List?;
    if (edges == null) return [];

    return edges
        .map((e) => Task.fromTwenty(e['node'] as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Task>> getTomorrowTasks() async {
    final now = DateTime.now();
    final startOfTomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final endOfTomorrow = startOfTomorrow.add(const Duration(days: 1));

    final String query = '''
      query GetTomorrowTasks {
        tasks(
          filter: {
            and: [
              { dueAt: { gte: "${startOfTomorrow.toIso8601String()}" } }
              { dueAt: { lt: "${endOfTomorrow.toIso8601String()}" } }
              { status: { neq: DONE } }
            ]
          }
          orderBy: { dueAt: AscNullsLast }
        ) {
          edges { node { id title status dueAt } }
        }
      }
    ''';

    final options = QueryOptions(
      document: gql(query),
      fetchPolicy: FetchPolicy.networkOnly,
    );

    final result = await client.query(options);

    if (result.hasException) {
      final msg = result.exception!.graphqlErrors.isNotEmpty
          ? result.exception!.graphqlErrors.first.message
          : result.exception.toString();
      if (_isSingleRequestLimitError(msg)) {
        final allOpenTasks = await _getOpenTasksSimple();
        return allOpenTasks
            .where(
              (t) =>
                  t.dueAt != null &&
                  !t.dueAt!.isBefore(startOfTomorrow) &&
                  t.dueAt!.isBefore(endOfTomorrow),
            )
            .toList();
      }
      _debugLogGraphQLError(result, source: 'getTomorrowTasks');
      throw Exception(result.exception.toString());
    }

    final edges = result.data?['tasks']?['edges'] as List?;
    if (edges == null) return [];

    return edges
        .map((e) => Task.fromTwenty(e['node'] as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Contact>> getRecentContacts({int limit = 5}) async {
    if (_hasRawTransport) {
      try {
        const String rawQuery = r'''
          query GetRecentContacts($first: Int!) {
            people(first: $first, orderBy: { updatedAt: DescNullsLast }) {
              edges { node {
                id
                name { firstName lastName }
                avatarUrl
                emails { primaryEmail }
                company { name }
                updatedAt
              } }
            }
          }
        ''';
        final raw = await _rawGraphQL(
          rawQuery,
          variables: {'first': limit},
          source: 'getRecentContactsRaw',
        );
        final rawEdges = raw['data']?['people']?['edges'] as List? ?? [];
        return rawEdges
            .map((e) => Contact.fromTwenty(e['node'] as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    const String query = r'''
      query GetRecentContacts($first: Int!) {
        people(
          first: $first
          orderBy: { updatedAt: DescNullsLast }
        ) {
          edges { node {
            id
            name { firstName lastName }
            avatarUrl
            emails { primaryEmail }
            company { name }
            updatedAt
          } }
        }
      }
    ''';

    final options = QueryOptions(
      document: gql(query),
      variables: {'first': limit},
      fetchPolicy: FetchPolicy.networkOnly,
    );

    final result = await client.query(options);
    if (result.hasException) {
      _debugLogGraphQLError(result, source: 'getRecentContacts');
      final firstError = result.exception!.graphqlErrors.isNotEmpty
          ? result.exception!.graphqlErrors.first.message
          : '';
      if (_isSingleRequestLimitError(firstError)) {
        // Fallback for Twenty instances that reject this richer query shape.
        const String fallbackQuery = r'''
          query GetRecentContactsFallback($first: Int!) {
            people(
              first: $first
              orderBy: { updatedAt: DescNullsLast }
            ) {
              edges { node {
                id
                name { firstName lastName }
                avatarUrl
                updatedAt
              } }
            }
          }
        ''';
        final fallbackResult = await client.query(
          QueryOptions(
            document: gql(fallbackQuery),
            variables: {'first': limit},
            fetchPolicy: FetchPolicy.networkOnly,
          ),
        );
        if (fallbackResult.hasException) {
          _debugLogGraphQLError(
            fallbackResult,
            source: 'getRecentContactsFallback',
          );
          return [];
        }
        final fallbackEdges = fallbackResult.data?['people']?['edges'] as List?;
        if (fallbackEdges == null) return [];
        return fallbackEdges
            .map((e) => Contact.fromTwenty(e['node'] as Map<String, dynamic>))
            .toList();
      }
      _handleResultException(result, source: 'getRecentContacts');
    }

    final edges = result.data?['people']?['edges'] as List?;
    if (edges == null) return [];

    return edges
        .map((e) => Contact.fromTwenty(e['node'] as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Task>> getTasks({bool? completed}) async {
    const String query = r'''
      query GetTasks($filter: TaskFilterInput) {
        tasks(filter: $filter, orderBy: { dueAt: AscNullsLast }) {
          edges {
            node {
              id title bodyV2 { blocknote } status dueAt createdAt
            }
          }
        }
      }
    ''';

    Map<String, dynamic>? filter;
    if (completed != null) {
      filter = {
        'status': {'eq': completed ? 'DONE' : 'TODO'},
      };
    }

    final QueryOptions options = QueryOptions(
      document: gql(query),
      variables: {if (filter != null) 'filter': filter},
      fetchPolicy: FetchPolicy.networkOnly,
    );

    final QueryResult result = await client.query(options);
    if (result.hasException) {
      final msg = result.exception!.graphqlErrors.isNotEmpty
          ? result.exception!.graphqlErrors.first.message
          : result.exception.toString();
      if (_isSingleRequestLimitError(msg)) {
        final allOpenTasks = await _getOpenTasksSimple();
        if (completed == null) return allOpenTasks;
        return allOpenTasks.where((t) => t.completed == completed).toList();
      }
      _handleResultException(result, source: 'getTasks');
    }

    final edges = result.data?['tasks']?['edges'] as List?;
    if (edges == null) return [];

    return edges
        .map((e) => Task.fromTwenty(e['node'] as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Task> createTask({
    required String title,
    String? body,
    DateTime? dueAt,
    String? contactId,
  }) async {
    final fullInput = <String, dynamic>{'title': title};
    if (body != null && body.trim().isNotEmpty) {
      final blockNodeJson = jsonEncode([
        {
          "type": "paragraph",
          "content": [
            {"type": "text", "text": body, "styles": {}}
          ]
        }
      ]);
      fullInput['bodyV2'] = {'blocknote': blockNodeJson};
    }
    if (dueAt != null) {
      final utcDueAt = dueAt.toUtc();
      fullInput['dueAt'] = "${utcDueAt.toIso8601String().split('.')[0]}Z";
    }

    String taskId;
    try {
      taskId = await _createTaskId(fullInput, source: 'createTask');
    } catch (e) {
      if (!_isSingleRequestLimitError(e.toString())) rethrow;
      // Split strategy for strict Twenty instances:
      // 1) create task with title only
      // 2) patch body/dueAt separately
      taskId = await _createTaskId(
        {'title': title},
        source: 'createTaskTitleOnly',
      );
      final patchInput = <String, dynamic>{};
      if (fullInput['bodyV2'] != null) patchInput['bodyV2'] = fullInput['bodyV2'];
      if (fullInput['dueAt'] != null) patchInput['dueAt'] = fullInput['dueAt'];
      if (patchInput.isNotEmpty) {
        try {
          await _updateTaskMinimal(taskId, patchInput, source: 'createTaskPatch');
        } catch (_) {
          // Do not fail creation if patch step is rejected; task already exists.
        }
      }
    }

    final normalizedContactId = contactId?.trim();
    if (normalizedContactId != null && normalizedContactId.isNotEmpty) {
      const String targetMutation = r'''
        mutation CreateTaskTarget($input: TaskTargetCreateInput!) {
          createTaskTarget(data: $input) { id }
        }
      ''';
      final targetInput = {
        'taskId': taskId,
        'targetPersonId': normalizedContactId,
      };
      if (_hasRawTransport) {
        try {
          await _rawGraphQL(
            targetMutation,
            variables: {'input': targetInput},
            source: 'createTaskTargetRaw',
          );
        } catch (_) {
          final targetResult = await client.mutate(
            MutationOptions(
              document: gql(targetMutation),
              variables: {'input': targetInput},
            ),
          );
          if (targetResult.hasException) {
            _debugLogGraphQLError(targetResult, source: 'createTaskTarget');
          }
        }
      } else {
        final targetResult = await client.mutate(
          MutationOptions(
            document: gql(targetMutation),
            variables: {'input': targetInput},
          ),
        );
        if (targetResult.hasException) {
          _debugLogGraphQLError(targetResult, source: 'createTaskTarget');
        }
      }
    }

    return Task(
      id: taskId,
      title: title,
      body: body,
      completed: false,
      dueAt: dueAt,
      contactId: normalizedContactId,
      createdAt: DateTime.now(),
    );
  }

  Future<String> _createTaskId(
    Map<String, dynamic> input, {
    required String source,
  }) async {
    const String mutation = r'''
      mutation CreateTask($input: TaskCreateInput!) {
        createTask(data: $input) { id }
      }
    ''';

    if (_hasRawTransport) {
      try {
        final raw = await _rawGraphQL(
          mutation,
          variables: {'input': input},
          source: '${source}Raw',
        );
        final rawId = raw['data']?['createTask']?['id'];
        if (rawId is String && rawId.isNotEmpty) return rawId;
        throw Exception('Invalid createTask response');
      } catch (_) {}
    }

    final result = await client.mutate(
      MutationOptions(
        document: gql(mutation),
        variables: {'input': input},
      ),
    );
    _handleResultException(result, source: source);
    final data = result.data?['createTask'] as Map<String, dynamic>?;
    final taskId = data?['id'] as String? ?? '';
    if (taskId.isEmpty) {
      throw Exception('createTask returned empty id');
    }
    return taskId;
  }

  Future<void> _updateTaskMinimal(
    String id,
    Map<String, dynamic> input, {
    required String source,
  }) async {
    const String mutation = r'''
      mutation UpdateTaskMinimal($id: UUID!, $input: TaskUpdateInput!) {
        updateTask(id: $id, data: $input) { id }
      }
    ''';

    if (_hasRawTransport) {
      try {
        await _rawGraphQL(
          mutation,
          variables: {'id': id, 'input': input},
          source: '${source}Raw',
        );
        return;
      } catch (_) {}
    }

    final result = await client.mutate(
      MutationOptions(
        document: gql(mutation),
        variables: {'id': id, 'input': input},
      ),
    );
    _handleResultException(result, source: source);
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
    const String mutation = r'''
      mutation UpdateTask($id: UUID!, $input: TaskUpdateInput!) {
        updateTask(id: $id, data: $input) { id title status bodyV2 { blocknote } dueAt createdAt }
      }
    ''';

    final input = <String, dynamic>{};
    if (title != null) input['title'] = title;
    if (completed != null) {
      input['status'] = completed ? 'DONE' : 'TODO';
    }
    if (body != null) {
      final blockNodeJson = jsonEncode([
        {
          "type": "paragraph",
          "content": [
            {"type": "text", "text": body, "styles": {}}
          ]
        }
      ]);
      input['bodyV2'] = {
        'blocknote': blockNodeJson,
      };
    }
    if (clearDueDate) {
      input['dueAt'] = null;
    } else if (dueAt != null) {
      final utcDueAt = dueAt.toUtc();
      input['dueAt'] = "${utcDueAt.toIso8601String().split('.')[0]}Z";
    }

    // In a real scenario we'd want to also be able to clear dueAt.
    // For now we just send what is provided.

    final MutationOptions options = MutationOptions(
      document: gql(mutation),
      variables: {
        'id': id,
        'input': input,
      },
    );

    final QueryResult result = await client.mutate(options);
    _handleResultException(result, source: 'updateTask');

    final data = result.data?['updateTask'];
    
    return Task.fromTwenty(data);
  }

  @override
  Future<void> deleteTask(String id) async {
    const String mutation = r'''
      mutation DeleteTask($id: UUID!) {
        deleteTask(id: $id) { id }
      }
    ''';

    final MutationOptions options = MutationOptions(
      document: gql(mutation),
      variables: {'id': id},
    );

    final QueryResult result = await client.mutate(options);
    _handleResultException(result, source: 'deleteTask');
  }
}
