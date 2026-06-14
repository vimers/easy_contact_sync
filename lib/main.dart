import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'theme/app_theme.dart';
import 'pages/shell_page.dart';
import 'providers/error_log_provider.dart';
import 'services/error_logger_service.dart';

void main() {
  // Initialize binding first so error handlers work.
  WidgetsFlutterBinding.ensureInitialized();

  // Capture errors thrown outside Flutter's framework reporting (async, zones,
  // platform channel failures). Everything is persisted via ErrorLoggerService
  // so it survives a restart and is surfaced in release builds (where the
  // default red error screen is stripped).
  runZonedGuarded(() {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      ErrorLoggerService.instance.log(
        source: 'flutter',
        error: details.exception,
        stackTrace: details.stack,
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      ErrorLoggerService.instance.log(
        source: 'platform',
        error: error,
        stackTrace: stack,
      );
      return true; // suppress the default crash
    };
    runApp(const ProviderScope(child: EasyContactSyncApp()));
  }, (error, stack) {
    ErrorLoggerService.instance.log(
      source: 'zone',
      error: error,
      stackTrace: stack,
    );
  });
}

class EasyContactSyncApp extends ConsumerWidget {
  const EasyContactSyncApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild when the "has an un-viewed uncaught error" condition flips.
    final showCrash = ref.watch(
      errorLogProvider.select((errors) =>
          errors.any((e) => !e.isRead && e.isUncaught)),
    );

    return MaterialApp(
      title: 'EasyContactSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: ThemeMode.system,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', ''),
        Locale('zh', ''),
      ],
      // Show the crash screen whenever there's an un-viewed uncaught error;
      // otherwise the normal app. Reactive, so runtime errors surface too
      // (previously this was a StatelessWidget that only checked once).
      home: showCrash ? const CrashScreen() : const ShellPage(),
    );
  }
}

/// Full-screen view of captured uncaught errors, shown instead of the app when
/// something crashed. Lets the user read, copy, and acknowledge the error so
/// the app can resume — no more silent blank screens in release.
class CrashScreen extends ConsumerWidget {
  const CrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final errors = ref.watch(errorLogProvider)
        .where((e) => !e.isRead && e.isUncaught)
        .toList();

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('App Error Captured'),
          actions: [
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy all',
              onPressed: () => _copyAll(context, errors),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            Text(
              'The app caught ${errors.length} uncaught error(s). '
              'Details are also saved in Settings → Error Log.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            ...errors.map((e) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '[${e.source}] ${e.timestamp.toLocal()}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          e.message,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                        if ((e.stackTrace ?? '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          SelectableText(
                            e.stackTrace!,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                  ),
                )),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.check),
          label: const Text('Dismiss'),
          onPressed: () => ref.read(errorLogProvider.notifier).markAllRead(),
        ),
      ),
    );
  }

  void _copyAll(BuildContext context, List errors) {
    final text = errors.map((e) {
      final m = e as dynamic;
      return '[${m.source}] ${m.timestamp.toLocal()}\n${m.message}\n${m.stackTrace ?? ''}';
    }).join('\n\n---\n\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Error details copied')),
    );
  }
}
