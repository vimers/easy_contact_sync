import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/sync_provider.dart';
import '../providers/accounts_provider.dart';
import '../providers/contact_sync_status_provider.dart';
import '../models/sync_record.dart';
import '../services/sync/sync_engine.dart';
import 'conflict_page.dart';
import 'deletion_review_page.dart';

/// Sync status page showing result details, manual sync button, and conflict entry.
class SyncStatusPage extends ConsumerWidget {
  const SyncStatusPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncNotifierProvider);
    final accountsAsync = ref.watch(accountsProvider);
    final conflicts = ref.watch(differingConflictsProvider);
    final deletionsAsync = ref.watch(pendingDeletionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(accountsProvider);
          ref.invalidate(syncLogsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Status card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(
                      syncState.isSyncing
                          ? Icons.sync
                          : syncState.statusMessage?.contains('failed') == true
                              ? Icons.error
                              : syncState.pendingConflicts.isNotEmpty
                                  ? Icons.warning_amber
                                  : Icons.check_circle,
                      size: 48,
                      color: syncState.isSyncing
                          ? Theme.of(context).colorScheme.primary
                          : syncState.statusMessage?.contains('failed') == true
                              ? Colors.red
                              : syncState.pendingConflicts.isNotEmpty
                                  ? Colors.orange
                                  : Colors.green,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      syncState.statusMessage ?? 'Ready',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    // Show last sync result details
                    if (syncState.lastResult != null) ...[
                      const SizedBox(height: 8),
                      _SyncResultDetails(result: syncState.lastResult!),
                    ],
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
            const SizedBox(height: 12),

            // Manual sync button
            SizedBox(
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

            // Remove duplicates (local + remote)
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: syncState.isSyncing
                    ? null
                    : () => _confirmDedup(context, ref),
                icon: const Icon(Icons.cleaning_services_outlined),
                label: const Text('Remove Duplicates (Local + Remote)'),
              ),
            ),

            // Conflicts button (contacts that differ between local and remote)
            if (conflicts.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ConflictPage(conflicts: conflicts),
                      ),
                    );
                  },
                  icon: const Icon(Icons.warning_amber),
                  label: Text('Resolve ${conflicts.length} Conflicts'),
                ),
              ),
            ],

            // Pending deletions (deleted outside the app, or on the server)
            deletionsAsync.when(
              data: (proposals) {
                if (proposals.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DeletionReviewPage(proposals: proposals),
                          ),
                        );
                      },
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: Text('Review ${proposals.length} deletions'),
                    ),
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 16),

            // Sync status overview (local vs cached remote)
            const _StatusOverviewCard(),

            const SizedBox(height: 16),

            // Section header
            Text(
              'Sync History',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),

            // Sync logs
            accountsAsync.when(
              data: (accounts) {
                if (accounts.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No accounts configured')),
                  );
                }
                return _SyncLogList(accountId: accounts.first.id!);
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error: $e'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDedup(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove duplicates?'),
        content: const Text(
          'This scans BOTH this phone and the remote server, and deletes '
          'contacts that are exact duplicates of another (same name, phone, '
          'email, etc.). One copy of each is kept. Recommended to run this '
          'BEFORE syncing a previously-broken account. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(syncNotifierProvider.notifier).dedupAll();
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

/// Widget to display sync result details.
class _SyncResultDetails extends StatelessWidget {
  final SyncResult result;

  const _SyncResultDetails({required this.result});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        if (result.pushed > 0)
          Chip(
            avatar: const Icon(Icons.upload, size: 16),
            label: Text('Pushed: ${result.pushed}'),
          ),
        if (result.pulled > 0)
          Chip(
            avatar: const Icon(Icons.download, size: 16),
            label: Text('Pulled: ${result.pulled}'),
          ),
        if (result.deletedLocal > 0)
          Chip(
            avatar: const Icon(Icons.delete_outline, size: 16),
            label: Text('Deleted local: ${result.deletedLocal}'),
          ),
        if (result.deletedRemote > 0)
          Chip(
            avatar: const Icon(Icons.cloud_off, size: 16),
            label: Text('Deleted remote: ${result.deletedRemote}'),
          ),
        if (result.conflicts.isNotEmpty)
          Chip(
            avatar: const Icon(Icons.warning_amber, size: 16),
            label: Text('Conflicts: ${result.conflicts.length}'),
          ),
        if (result.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              result.errorMessage!,
              style: TextStyle(color: Colors.red[700], fontSize: 12),
            ),
          ),
      ],
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
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('No sync history')),
          );
        }
        return Column(
          children: logs.map((log) {
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Icon(statusIcon, color: statusColor, size: 20),
              title: Text(
                _formatTimestamp(log.timestamp),
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                '${log.status.name}${log.conflictsCount > 0 ? ' · ${log.conflictsCount} conflicts' : ''}${log.errorMessage != null ? ' · ${log.errorMessage}' : ''}',
                style: const TextStyle(fontSize: 11),
              ),
            );
          }).toList(),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Error loading logs: $e'),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// Summary of local-vs-remote contact status, computed from the cached remote
/// snapshot. Refreshes automatically after each sync.
class _StatusOverviewCard extends ConsumerWidget {
  const _StatusOverviewCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(contactSyncStatusProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Sync Status Overview',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            snapshotAsync.when(
              data: (s) => Column(
                children: [
                  _row(context, Icons.cloud_outlined, Colors.blueGrey, 'Remote total', s.remoteTotal),
                  _row(context, Icons.check_circle, Colors.green, 'In sync', s.inSync),
                  _row(context, Icons.sync_problem, Colors.orange, 'Differ from local', s.differing),
                  _row(context, Icons.cloud, Colors.grey, 'Only on remote (remote has more)', s.remoteOnly),
                  _row(context, Icons.phone_android, Colors.grey, 'Only on phone (remote has fewer)', s.localOnly),
                ],
              ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Could not load status: $e', style: const TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, Color color, String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          Text(
            '$count',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
