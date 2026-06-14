import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/conflict_item.dart';
import '../providers/contacts_provider.dart';
import '../providers/contact_sync_status_provider.dart';
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
                    return ContactListItem(
                      contact: dc.contact,
                      status: dc.status,
                      onTap: () => _onTap(dc),
                      onStatusTap: dc.status == ContactSyncStatus.differing
                          ? () => _openResolve(dc)
                          : null,
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
        builder: (_) => ContactDetailPage(contact: dc.contact),
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
}
