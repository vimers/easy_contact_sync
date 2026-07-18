import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/contact.dart';
import '../providers/contact_sync_status_provider.dart';
import '../widgets/contact_photo.dart';
import '../providers/contacts_provider.dart';
import '../providers/accounts_provider.dart';
import '../providers/sync_provider.dart';

/// Detail page showing all fields of a single contact, with a delete action.
/// Delete is offered only when a local copy exists; deleting records a tombstone
/// so the next sync removes the contact from the server too.
class ContactDetailPage extends ConsumerWidget {
  final DisplayContact display;

  const ContactDetailPage({super.key, required this.display});

  Contact get contact => display.localContact ?? display.remoteContact!;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canDelete = display.localContact?.uid != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(contact.bestName),
        actions: [
          if (canDelete)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: () => _confirmDelete(context, ref),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  ContactPhoto(
                    base64Photo: contact.photo,
                    fallbackInitial: contact.bestName.isNotEmpty
                        ? contact.bestName[0].toUpperCase()
                        : '?',
                    radius: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(contact.bestName, style: theme.textTheme.headlineSmall),
                  if (contact.organization != null) ...[
                    const SizedBox(height: 4),
                    Text(contact.organization!, style: theme.textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (contact.phones.isNotEmpty) ...[
              _sectionTitle(context, 'Phone'),
              ...contact.phones.map((p) => _infoRow(context, p.label, p.number, Icons.phone)),
            ],
            if (contact.emails.isNotEmpty) ...[
              _sectionTitle(context, 'Email'),
              ...contact.emails.map((e) => _infoRow(context, e.label, e.address, Icons.email)),
            ],
            if (contact.title != null) ...[
              _sectionTitle(context, 'Title'),
              _infoRow(context, '', contact.title!, Icons.badge),
            ],
            if (contact.note != null) ...[
              _sectionTitle(context, 'Note'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(contact.note!),
              ),
            ],
            if (contact.birthday != null) ...[
              _sectionTitle(context, 'Birthday'),
              _infoRow(context, '', _formatDate(contact.birthday!), Icons.cake),
            ],
            if (contact.addresses.isNotEmpty) ...[
              _sectionTitle(context, 'Address'),
              ...contact.addresses.map((a) => _infoRow(
                    context,
                    a.label,
                    [a.street, a.city, a.region, a.postalCode, a.country]
                        .where((s) => s != null && s.isNotEmpty)
                        .join(', '),
                    Icons.location_on,
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final localUid = display.localContact!.uid;
    if (localUid == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete contact?'),
        content: const Text(
          'This removes the contact from your phone. It will also be removed '
          'from the server on the next sync.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final accounts = await ref.read(accountsProvider.future);
    if (accounts.isEmpty) {
      await ref.read(localContactServiceProvider).deleteContact(localUid);
    } else {
      await ref.read(syncNotifierProvider.notifier).deleteLocalContact(
            accountId: accounts.first.id!,
            localUid: localUid,
          );
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Deleted. Will be removed from the server on next sync.')),
    );
    Navigator.of(context).pop();
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(value),
      subtitle: label.isNotEmpty ? Text(label) : null,
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
