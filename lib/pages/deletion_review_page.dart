import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/conflict_item.dart';
import '../models/contact.dart';
import '../providers/accounts_provider.dart';
import '../providers/sync_provider.dart';

/// Review inferred deletions (deleted outside the app, or on the server) and
/// choose per item: propagate the deletion to the other side, or restore it.
/// Mirrors ConflictPage.
class DeletionReviewPage extends ConsumerStatefulWidget {
  final List<DeletionProposal> proposals;

  const DeletionReviewPage({super.key, required this.proposals});

  @override
  ConsumerState<DeletionReviewPage> createState() => _DeletionReviewPageState();
}

class _DeletionReviewPageState extends ConsumerState<DeletionReviewPage> {
  late final List<DeletionProposal> _proposals;

  @override
  void initState() {
    super.initState();
    _proposals = widget.proposals;
  }

  @override
  Widget build(BuildContext context) {
    final allDecided = _proposals.every((p) => p.choice != DeletionChoice.unresolved);

    return Scaffold(
      appBar: AppBar(title: Text('Pending deletions (${_proposals.length})')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _setAll(DeletionChoice.propagate),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete All'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _setAll(DeletionChoice.restore),
                    icon: const Icon(Icons.restore),
                    label: const Text('Restore All'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _proposals.length,
              itemBuilder: (context, index) => _ProposalCard(
                proposal: _proposals[index],
                onChoose: (choice) => setState(() => _proposals[index].choice = choice),
              ),
            ),
          ),
          if (allDecided)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _apply,
                  icon: const Icon(Icons.check),
                  label: const Text('Confirm'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _setAll(DeletionChoice choice) {
    setState(() {
      for (final p in _proposals) {
        p.choice = choice;
      }
    });
  }

  Future<void> _apply() async {
    final accountsAsync = ref.read(accountsProvider);
    await accountsAsync.when(
      data: (accounts) async {
        if (accounts.isEmpty) return;
        for (final account in accounts) {
          await ref.read(syncNotifierProvider.notifier).resolveDeletions(account, _proposals);
        }
        if (mounted) Navigator.pop(context);
      },
      loading: () {},
      error: (_, __) {},
    );
  }
}

class _ProposalCard extends StatelessWidget {
  final DeletionProposal proposal;
  final ValueChanged<DeletionChoice> onChoose;

  const _ProposalCard({required this.proposal, required this.onChoose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Contact contact;
    final String missingSide;
    if (proposal.side == DeletionSide.localDeleted) {
      contact = proposal.remoteContact!;
      missingSide = 'deleted from this phone';
    } else {
      contact = proposal.localContact!;
      missingSide = 'deleted from the server';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(contact.bestName, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('$missingSide — also delete it from the other side, or restore it?',
                style: theme.textTheme.bodySmall),
            if (contact.phones.isNotEmpty)
              Text('Tel: ${contact.phones.first.number}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onChoose(DeletionChoice.propagate),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: proposal.choice == DeletionChoice.propagate
                          ? theme.colorScheme.primaryContainer
                          : null,
                    ),
                    child: const Text('Delete'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onChoose(DeletionChoice.restore),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: proposal.choice == DeletionChoice.restore
                          ? theme.colorScheme.primaryContainer
                          : null,
                    ),
                    child: const Text('Restore'),
                  ),
                ),
              ],
            ),
            if (proposal.choice != DeletionChoice.unresolved)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  proposal.choice == DeletionChoice.propagate ? 'Will delete' : 'Will restore',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
