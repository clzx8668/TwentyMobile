import 'dart:async';
import 'package:flutter/services.dart' show rootBundle;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pocketcrm/core/offline/outbox_queue.dart';
import 'package:pocketcrm/core/router/router.dart';
import 'package:pocketcrm/core/router/navigator_key.dart';
import 'package:pocketcrm/core/theme/app_theme.dart';
import 'package:pocketcrm/core/theme/theme_provider.dart';
import 'package:pocketcrm/core/di/providers.dart';
import 'package:pocketcrm/data/repositories/offline_first_crm_repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pocketcrm/core/notifications/notification_service.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:pocketcrm/core/config/app_config.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await SentryFlutter.init(
    (options) {
      options.dsn = kDebugMode
          ? ''
          : AppConfig.glitchtipDsn; // disabilitato in debug
      options.tracesSampleRate = 1.0;
      options.debug = false;
      // Filter out non-fatal network errors that spam GlitchTip
      options.beforeSend = (event, hint) {
        final exceptions = event.exceptions;
        if (exceptions != null && exceptions.isNotEmpty) {
          final errorValue = exceptions.first.value ?? '';
          if (errorValue.contains('Failed to load font with url') ||
              errorValue.contains('fonts.gstatic.com')) {
            return null; // Ignore and drop this event
          }
        }
        return event;
      };
    },
    appRunner: () async {
      try {
        await NotificationService().initialize();

        final appDocDir = await getApplicationSupportDirectory();
        if (kDebugMode) print('Hive storage path: ${appDocDir.path}');
        Hive.init(appDocDir.path);

        final box = await Hive.openBox<String>('app_storage');
        if (kDebugMode) {
          print('Hive box keys at startup: ${box.keys.toList()}');
        }
        await _applyDebugEnvFromAsset(box);

        await initializeDateFormatting('it_IT', null);

        runApp(
          ProviderScope(
            overrides: [hiveStorageBoxProvider.overrideWithValue(box)],
            child: const PocketCRMApp(),
          ),
        );
      } catch (e, stack) {
        if (kDebugMode) {
          print('Fatal error during initialization: $e');
          print(stack);
        }
        // In case of error, still try to run the app to show an error or the UI
        runApp(
          ProviderScope(
            overrides: [], // No box available
            child: const PocketCRMApp(),
          ),
        );
      } finally {
        // Rimuoviamo lo splash screen una volta che l'app è pronta o è fallita
        FlutterNativeSplash.remove();
      }
    },
  );
}

class PocketCRMApp extends ConsumerStatefulWidget {
  const PocketCRMApp({super.key});

  @override
  ConsumerState<PocketCRMApp> createState() => _PocketCRMAppState();
}

Future<void> _applyDebugEnvFromAsset(Box<String> box) async {
  if (!kDebugMode) return;
  try {
    final raw = await rootBundle.loadString('.env');
    final lines = raw
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.startsWith('#'))
        .toList(growable: false);
    if (lines.isEmpty) return;

    final token = lines[0];
    final url = lines.length > 1 ? lines[1] : '';
    if (token.isNotEmpty) {
      await box.put('api_token', token);
    }
    if (url.isNotEmpty) {
      await box.put('instance_url', url);
    }
    if (kDebugMode) {
      print('Debug .env applied to local storage keys.');
    }
  } catch (_) {
    // .env asset optional in debug
  }
}

class _PocketCRMAppState extends ConsumerState<PocketCRMApp>
    with WidgetsBindingObserver {
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_attemptAutoSync()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_attemptAutoSync());
      if (initialNotificationRoute != null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (navigatorKey.currentContext != null) {
            navigatorKey.currentContext!.go(initialNotificationRoute!);
            clearInitialNotificationRoute();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_attemptAutoSync());
    }
  }

  Future<void> _attemptAutoSync() async {
    try {
      final box = ref.read(hiveStorageBoxProvider);
      final queue = OutboxQueue(box);
      final pending = await queue.listPending();
      if (pending.isEmpty) return;

      final repo = await ref.read(crmRepositoryProvider.future);
      if (repo is OfflineFirstCRMRepository) {
        await repo.flushOutbox();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'TwentyMobile',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
