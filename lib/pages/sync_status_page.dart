import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/sync_provider.dart';
import '../providers/accounts_provider.dart';
import '../models/sync_record.dart';
import 'conflict_page.dart';

/// Sync status page showing logs, manual sync button, and conflict entry.
class SyncStatusPage extends ConsumerWidget {
  const SyncStatusPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncNotifierProvider);
    final accountsAsync = ref.watch(accountsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync'),
      ),
      body: Column(
        children: [
          // Status card
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    syncState.isSyncing
                        ? Icons.sync
                        : syncState.pendingConflicts.isNotEmpty
                            ? Icons.warning_amber
                            : Icons.check_circle,
                    size: 48,
                    color: syncState.isSyncing
                        ? Theme.of(context).colorScheme.primary
                        : syncState.pendingConflicts.isNotEmpty
                            ? Colors.orange
                            : Colors.green,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    syncState.statusMessage ?? 'Ready',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (syncState.pendingConflicts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${syncState.pendingConflicts.length} conflicts to resolve',
                      style: TextStyle(color: Colors.orange[700]),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Manual sync button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: syncState.isSyncing
                    ? null
                    : () => ref.read(syncNotifierProvider.notifier).syncAll(),
                icon: syncState.isSyncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: Text(syncState.isSyncing ? 'Syncing...' : 'Sync Now'),
              ),
            ),
          ),

          // Conflicts button
          if (syncState.pendingConflicts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ConflictPage(
                          conflicts: syncState.pendingConflicts,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.warning_amber),
                  label: Text('Resolve ${syncState.pendingConflicts.length} Conflicts'),
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Sync logs
          Expanded(
            child: accountsAsync.when(
              data: (accounts) {
                if (accounts.isEmpty) {
                  return const Center(child: Text('No accounts configured'));
                }
                return _SyncLogList(accountId: accounts.first.id!);
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncLogList extends ConsumerWidget {
  final int accountId;

  const _SyncLogList({required this.accountId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(syncLogsProvider(accountId));

    return logsAsync.when(
      data: (logs) {
        if (logs.isEmpty) {
          return const Center(child: Text('No sync history'));
        }
        return ListView.builder(
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final log = logs[index];
            final statusIcon = switch (log.status) {
              SyncStatus.success => Icons.check_circle,
              SyncStatus.failure => Icons.error,
              SyncStatus.conflicts => Icons.warning,
            };
            final statusColor = switch (log.status) {
              SyncStatus.success => Colors.green,
              SyncStatus.failure => Colors.red,
              SyncStatus.conflicts => Colors.orange,
            };

            return ListTile(
              leading: Icon(statusIcon, color: statusColor),
              title: Text(_formatTimestamp(log.timestamp)),
              subtitle: Text(
                '${log.status.name}${log.conflictsCount > 0 ? ' · ${log.conflictsCount} conflicts' : ''}${log.errorMessage != null ? ' · ${log.errorMessage}' : ''}',
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
