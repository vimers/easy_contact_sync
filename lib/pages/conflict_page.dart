import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/conflict_item.dart';
import '../models/contact.dart';
import '../providers/sync_provider.dart';
import '../providers/accounts_provider.dart';
import '../widgets/diff_viewer.dart';
import '../services/sync/diff_engine.dart';

/// Conflict resolution page.
class ConflictPage extends ConsumerStatefulWidget {
  final List<ConflictItem> conflicts;

  const ConflictPage({super.key, required this.conflicts});

  @override
  ConsumerState<ConflictPage> createState() => _ConflictPageState();
}

class _ConflictPageState extends ConsumerState<ConflictPage> {
  late List<ConflictItem> _conflicts;

  @override
  void initState() {
    super.initState();
    _conflicts = widget.conflicts;
  }

  @override
  Widget build(BuildContext context) {
    final allResolved = _conflicts.every((c) => c.resolution != ConflictResolution.unresolved);

    return Scaffold(
      appBar: AppBar(
        title: Text('Conflicts (${_conflicts.length})'),
      ),
      body: Column(
        children: [
          // Batch actions
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _resolveAll(ConflictResolution.useLocal),
                    icon: const Icon(Icons.phone_android),
                    label: const Text('Use All Local'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _resolveAll(ConflictResolution.useRemote),
                    icon: const Icon(Icons.cloud),
                    label: const Text('Use All Remote'),
                  ),
                ),
              ],
            ),
          ),

          // Conflict list
          Expanded(
            child: ListView.builder(
              itemCount: _conflicts.length,
              itemBuilder: (context, index) {
                final conflict = _conflicts[index];
                return _ConflictCard(
                  conflict: conflict,
                  onResolve: (resolution) {
                    setState(() => conflict.resolution = resolution);
                  },
                  onViewDetails: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _ConflictDetailPage(conflict: conflict),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Confirm button
          if (allResolved)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _applyResolutions,
                  icon: const Icon(Icons.check),
                  label: const Text('Confirm Sync'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _resolveAll(ConflictResolution resolution) {
    setState(() {
      for (final conflict in _conflicts) {
        conflict.resolution = resolution;
      }
    });
  }

  Future<void> _applyResolutions() async {
    final accountsAsync = ref.read(accountsProvider);
    await accountsAsync.when(
      data: (accounts) async {
        if (accounts.isEmpty) return;
        for (final account in accounts) {
          await ref.read(syncNotifierProvider.notifier).resolveConflicts(
                account,
                _conflicts,
              );
        }
        if (mounted) Navigator.pop(context);
      },
      loading: () {},
      error: (_, __) {},
    );
  }
}

class _ConflictCard extends StatelessWidget {
  final ConflictItem conflict;
  final ValueChanged<ConflictResolution> onResolve;
  final VoidCallback onViewDetails;

  const _ConflictCard({
    required this.conflict,
    required this.onResolve,
    required this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isResolved = conflict.resolution != ConflictResolution.unresolved;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name
            Row(
              children: [
                Expanded(
                  child: Text(
                    conflict.localContact.bestName,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (isResolved)
                  Chip(
                    label: Text(
                      conflict.resolution == ConflictResolution.useLocal ? 'Local' : 'Remote',
                    ),
                    backgroundColor: conflict.resolution == ConflictResolution.useLocal
                        ? Colors.blue.withValues(alpha: 0.2)
                        : Colors.green.withValues(alpha: 0.2),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Side by side preview
            Row(
              children: [
                Expanded(child: _miniContact(context, 'Local', conflict.localContact)),
                const SizedBox(width: 8),
                Expanded(child: _miniContact(context, 'Remote', conflict.remoteContact)),
              ],
            ),
            const SizedBox(height: 8),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onResolve(ConflictResolution.useLocal),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: conflict.resolution == ConflictResolution.useLocal
                          ? theme.colorScheme.primaryContainer
                          : null,
                    ),
                    child: const Text('Use Local'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onResolve(ConflictResolution.useRemote),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: conflict.resolution == ConflictResolution.useRemote
                          ? theme.colorScheme.primaryContainer
                          : null,
                    ),
                    child: const Text('Use Remote'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onViewDetails,
                  child: const Text('Details'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniContact(BuildContext context, String label, Contact contact) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          if (contact.phones.isNotEmpty)
            Text('Tel: ${contact.phones.first.number}', style: const TextStyle(fontSize: 12)),
          if (contact.emails.isNotEmpty)
            Text('Email: ${contact.emails.first.address}', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

/// Field-by-field diff detail page.
class _ConflictDetailPage extends StatelessWidget {
  final ConflictItem conflict;

  const _ConflictDetailPage({required this.conflict});

  @override
  Widget build(BuildContext context) {
    final diffEngine = DiffEngine();
    final fieldDiffs = diffEngine.computeFieldDiff(conflict.localContact, conflict.remoteContact);

    return Scaffold(
      appBar: AppBar(
        title: Text(conflict.localContact.bestName),
      ),
      body: DiffViewerWidget(fieldDiffs: fieldDiffs),
    );
  }
}
