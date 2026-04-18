import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:pocketcrm/core/utils/storage_service.dart';

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

class UiConfigService {
  UiConfigService({
    required StorageService storage,
    Dio? dio,
  })  : _storage = storage,
        _dio = dio ?? Dio();

  final StorageService _storage;
  final Dio _dio;

  Future<Map<String, dynamic>> getPageNodeJson(String pageKey) async {
    final cached = await _readCachedPage(pageKey);
    if (cached != null) return cached;

    final remote = await _tryFetchRemotePage(pageKey);
    if (remote != null) {
      await _writeCachedPage(pageKey, remote);
      return remote;
    }

    final local = await _loadLocalDefaultPage(pageKey);
    await _writeCachedPage(pageKey, local);
    return local;
  }

  Future<Map<String, dynamic>?> _readCachedPage(String pageKey) async {
    try {
      final raw = await _storage.read(key: 'ui_config:page:$pageKey');
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded as Map);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _writeCachedPage(String pageKey, Map<String, dynamic> json) async {
    try {
      await _storage.write(
        key: 'ui_config:page:$pageKey',
        value: jsonEncode(json),
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _tryFetchRemotePage(String pageKey) async {
    final rawBaseUrl = await _storage.read(key: 'instance_url');
    if (rawBaseUrl == null || rawBaseUrl.trim().isEmpty) return null;
    final baseUrl = _normalizeInstanceUrl(rawBaseUrl);
    final url = '$baseUrl/mobile-ui-config.json';

    try {
      final resp = await _dio.get(
        url,
        options: Options(
          responseType: ResponseType.json,
          followRedirects: true,
          receiveTimeout: const Duration(seconds: 4),
          sendTimeout: const Duration(seconds: 4),
        ),
      );

      final data = resp.data;
      if (data is Map) {
        final map = Map<String, dynamic>.from(data as Map);
        final pages = map['pages'];
        if (pages is Map && pages[pageKey] is Map) {
          return Map<String, dynamic>.from(pages[pageKey] as Map);
        }
        if (map['type'] is String) {
          return map;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> _loadLocalDefaultPage(String pageKey) async {
    final raw = await rootBundle.loadString('assets/ui/default_ui.json');
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw Exception('Invalid default UI config');
    }
    final root = Map<String, dynamic>.from(decoded as Map);
    final pages = root['pages'];
    if (pages is Map && pages[pageKey] is Map) {
      return Map<String, dynamic>.from(pages[pageKey] as Map);
    }
    throw Exception('Missing default UI config for page=$pageKey');
  }
}

