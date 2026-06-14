import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/error_log.dart';
import '../../providers/error_log_provider.dart';

/// Lists captured errors (crashes + sync failures) persisted across restarts.
/// Opening this page marks everything read, clearing the Settings badge.
class ErrorLogPage extends ConsumerStatefulWidget {
  const ErrorLogPage({super.key});

  @override
  ConsumerState<ErrorLogPage> createState() => _ErrorLogPageState();
}

class _ErrorLogPageState extends ConsumerState<ErrorLogPage> {
  @override
  void initState() {
    super.initState();
    // Clear the unread badge once the user is looking at the list.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(errorLogProvider.notifier).markAllRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final errors = ref.watch(errorLogProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Error Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy all',
            onPressed: errors.isEmpty ? null : () => _copyAll(context, errors),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear all',
            onPressed: errors.isEmpty
                ? null
                : () => _confirmClear(context, ref),
          ),
        ],
      ),
      body: errors.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 56, color: Colors.green),
                  SizedBox(height: 12),
                  Text('No errors recorded'),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: errors.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _ErrorCard(error: errors[i]),
            ),
    );
  }

  void _copyAll(BuildContext context, List<ErrorLog> errors) {
    final text = errors
        .map((e) =>
            '[${e.source}] ${e.timestamp.toLocal()}\n${e.message}\n${e.stackTrace ?? ''}')
        .join('\n\n---\n\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied all errors')),
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear error log?'),
        content: const Text('This permanently deletes all recorded errors.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              ref.read(errorLogProvider.notifier).clearAll();
              Navigator.pop(ctx);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final ErrorLog error;
  const _ErrorCard({required this.error});

  @override
  Widget build(BuildContext context) {
    final color = error.isUncaught ? Colors.red : Colors.orange;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, size: 18, color: color),
                const SizedBox(width: 6),
                Text(
                  error.source.toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                Text(
                  _formatTime(error.timestamp),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              error.message,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            if ((error.stackTrace ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  error.stackTrace!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    final local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}
