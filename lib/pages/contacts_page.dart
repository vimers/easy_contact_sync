import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/conflict_item.dart';
import '../providers/contacts_provider.dart';
import '../providers/contact_sync_status_provider.dart';
import '../providers/accounts_provider.dart';
import '../providers/sync_provider.dart';
import '../widgets/contact_list_item.dart';
import 'conflict_page.dart';
import 'contact_detail_page.dart';

/// Contacts list (local ∪ remote) with per-contact sync status icons.
class ContactsPage extends ConsumerStatefulWidget {
  const ContactsPage({super.key});

  @override
  ConsumerState<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends ConsumerState<ContactsPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = ref.watch(contactSearchQueryProvider);
    final snapshotAsync = ref.watch(contactSyncStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search contacts...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(contactSearchQueryProvider.notifier).state = '';
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                ref.read(contactSearchQueryProvider.notifier).state = value;
              },
            ),
          ),
          Expanded(
            child: snapshotAsync.when(
              data: (snapshot) {
                var items = snapshot.items;
                if (searchQuery.isNotEmpty) {
                  final q = searchQuery.toLowerCase();
                  items = items.where((dc) {
                    final name = dc.contact.bestName.toLowerCase();
                    return name.contains(q) ||
                        dc.contact.phones.any((p) => p.number.contains(q)) ||
                        dc.contact.emails
                            .any((e) => e.address.toLowerCase().contains(q));
                  }).toList();
                }
                if (items.isEmpty) {
                  return const Center(child: Text('No contacts'));
                }
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final dc = items[index];
                    final canDelete = dc.localContact?.uid != null;
                    return Dismissible(
                      key: ValueKey('contact-${dc.uid}-${dc.contact.bestName}'),
                      direction: canDelete
                          ? DismissDirection.endToStart
                          : DismissDirection.none,
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: canDelete ? (_) => _confirmDelete(dc) : null,
                      child: ContactListItem(
                        contact: dc.contact,
                        status: dc.status,
                        onTap: () => _onTap(dc),
                        onStatusTap: dc.status == ContactSyncStatus.differing
                            ? () => _openResolve(dc)
                            : null,
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Error: $error')),
            ),
          ),
        ],
      ),
    );
  }

  void _onTap(DisplayContact dc) {
    // A differing contact jumps straight into conflict resolution.
    if (dc.status == ContactSyncStatus.differing) {
      _openResolve(dc);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContactDetailPage(display: dc),
      ),
    );
  }

  void _openResolve(DisplayContact dc) {
    if (dc.localContact == null || dc.remoteContact == null) return;
    final item = ConflictItem(
      uid: dc.uid,
      localContact: dc.localContact!,
      remoteContact: dc.remoteContact!,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConflictPage(conflicts: [item]),
      ),
    );
  }

  Future<bool> _confirmDelete(DisplayContact dc) async {
    final localUid = dc.localContact!.uid;
    if (localUid == null) return false;
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
    if (confirmed != true) return false;

    final accounts = await ref.read(accountsProvider.future);
    if (accounts.isEmpty) {
      await ref.read(localContactServiceProvider).deleteContact(localUid);
    } else {
      await ref.read(syncNotifierProvider.notifier).deleteLocalContact(
            accountId: accounts.first.id!,
            localUid: localUid,
          );
    }

    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Deleted. Will be removed from the server on next sync.')),
    );
    return true;
  }
}
