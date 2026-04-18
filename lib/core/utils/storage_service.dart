import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

class StorageService {
  final FlutterSecureStorage _secureStorage;
  final Box<String> _box;
  final Map<String, String> _cache = {};

  static const _sensitiveKeys = {'api_token', 'instance_url'};
  static const _noisyDebugKeys = {'is_demo_mode'};

  // Android options consigliate per evitare problemi comuni
  static const _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
  );

  StorageService(this._secureStorage, this._box);

  static const _macOsOptions = MacOsOptions(
    // Usa il gruppo di accesso corretto per l'app
    accessibility: KeychainAccessibility.first_unlock,
    synchronizable: false,
  );

  /// Factory constructor con opzioni ottimizzate per piattaforma
  static FlutterSecureStorage createSecureStorage() {
    return const FlutterSecureStorage(
      aOptions: _androidOptions,
      mOptions: _macOsOptions,
    );
  }

  bool _isSensitive(String key) => _sensitiveKeys.contains(key);

  // ---------------------------------------------------------------------------
  // WRITE
  // ---------------------------------------------------------------------------
  Future<void> write({required String key, required String? value}) async {
    _log('write() called: key=$key, value=${_masked(key, value)}');

    // Aggiorna cache
    if (value != null) {
      _cache[key] = value;
    } else {
      _cache.remove(key);
    }

    // Scrivi sempre su secure storage (è il source of truth)
    bool secureWriteOk = false;
    try {
      await _secureStorage.write(key: key, value: value);
      secureWriteOk = true;
      _log('write() -> secure storage OK');
    } catch (e) {
      _logWarn('write() -> secure storage FAILED: $e');
    }

    // Scrivi su Hive:
    // - Sempre per chiavi non sensibili
    // - In debug anche per chiavi sensibili (fallback affidabile su device problematici)
    final bool writeToHive = !_isSensitive(key) || kDebugMode;

    if (writeToHive) {
      if (value != null) {
        await _box.put(key, value);
        _log('write() -> Hive OK');
      } else {
        await _box.delete(key);
        _log('write() -> Hive DELETE OK');
      }
    }

    if (!secureWriteOk && _isSensitive(key) && !kDebugMode) {
      // In produzione, se secure storage fallisce per una chiave sensibile
      // è un errore critico: il token non sarà mai recuperabile in modo sicuro
      throw StateError(
        'StorageService: impossibile scrivere "$key" su secure storage in produzione.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // READ
  // ---------------------------------------------------------------------------
  Future<String?> read({required String key}) async {
    _log('read() called: key=$key', key: key);

    // 1. Cache in memoria
    if (_cache.containsKey(key)) {
      _log('read() -> cache HIT', key: key);
      return _cache[key];
    }

    // 2. Secure storage (source of truth)
    String? value;
    for (var attempt = 1; attempt <= 2 && value == null; attempt++) {
      try {
        // Alcuni device hanno timeout sporadici: ritentiamo una volta.
        value = await _secureStorage
            .read(key: key)
            .timeout(const Duration(seconds: 3));
        _log(
          'read() -> secure storage attempt=$attempt: ${value != null ? "HIT" : "MISS"}',
          key: key,
        );
      } catch (e) {
        _logWarn(
          'read() -> secure storage attempt=$attempt FAILED or TIMED OUT: $e',
        );
      }
    }

    if (value != null) {
      _cache[key] = value;
      // In debug manteniamo una copia anche su Hive per ridurre impatti da timeout futuri.
      if (_isSensitive(key) && kDebugMode) {
        await _box.put(key, value);
      }
      return value;
    }

    // 3. Fallback Hive
    // - Per chiavi non sensibili: sempre
    // - In debug anche per chiavi sensibili
    final bool canReadFromHive = !_isSensitive(key) || kDebugMode;

    if (!canReadFromHive) {
      _log('read() -> Hive skip: chiave sensibile');
      return null;
    }

    final String? hiveValue = _box.get(key);
    _log('read() -> Hive: ${hiveValue != null ? "HIT" : "MISS"}', key: key);

    if (hiveValue == null) return null;

    // Trovato in Hive: aggiorna cache
    _cache[key] = hiveValue;

    return hiveValue;
  }

  // ---------------------------------------------------------------------------
  // DELETE
  // ---------------------------------------------------------------------------
  Future<void> delete({required String key}) async {
    _log('delete() called: key=$key');
    _cache.remove(key);

    try {
      await _secureStorage.delete(key: key);
      _log('delete() -> secure storage OK');
    } catch (e) {
      _logWarn('delete() -> secure storage FAILED: $e');
    }

    await _box.delete(key);
    _log('delete() -> Hive OK');
  }

  // ---------------------------------------------------------------------------
  // DELETE ALL
  // ---------------------------------------------------------------------------
  Future<void> deleteAll() async {
    _log('deleteAll() called');
    _cache.clear();

    try {
      await _secureStorage.deleteAll();
      _log('deleteAll() -> secure storage OK');
    } catch (e) {
      _logWarn('deleteAll() -> secure storage FAILED: $e');
    }

    await _box.clear();
    _log('deleteAll() -> Hive OK');
  }

  // ---------------------------------------------------------------------------
  // DEBUG UTILS
  // ---------------------------------------------------------------------------

  /// Stampa tutto il contenuto di secure storage (solo debug)
  Future<void> debugDumpSecureStorage() async {
    if (!kDebugMode) return;
    try {
      final all = await _secureStorage.readAll();
      print('=== StorageService: secure storage dump ===');
      if (all.isEmpty) {
        print('  (vuoto)');
      } else {
        for (final e in all.entries) {
          print('  ${e.key} = ${_masked(e.key, e.value)}');
        }
      }
      print('===========================================');
    } catch (e) {
      print('StorageService: impossibile leggere secure storage: $e');
    }
  }

  /// Stampa tutto il contenuto di Hive (solo debug)
  void debugDumpHive() {
    if (!kDebugMode) return;
    print('=== StorageService: Hive dump ===');
    if (_box.isEmpty) {
      print('  (vuoto)');
    } else {
      for (final key in _box.keys) {
        final value = _box.get(key as String);
        print('  $key = ${_masked(key, value)}');
      }
    }
    print('=================================');
  }

  // ---------------------------------------------------------------------------
  // PRIVATE HELPERS
  // ---------------------------------------------------------------------------

  void _log(String msg, {String? key}) {
    if (!kDebugMode) return;
    if (key != null && _noisyDebugKeys.contains(key)) return;
    print('StorageService: $msg');
  }

  void _logWarn(String msg) {
    if (kDebugMode) print('StorageService: ⚠️  $msg');
  }

  /// Maschera il valore delle chiavi sensibili nei log
  String? _masked(String key, String? value) {
    if (value == null) return null;
    if (_isSensitive(key))
      return '***${value.length > 4 ? value.substring(value.length - 4) : "****"}';
    return value;
  }
}
