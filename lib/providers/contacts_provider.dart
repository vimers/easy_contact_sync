import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/contact.dart';
import '../services/local_contact_service.dart';

/// Provider for LocalContactService.
final localContactServiceProvider = Provider<LocalContactService>((ref) {
  return LocalContactService();
});

/// Provider for all local contacts.
final contactsProvider = FutureProvider<List<Contact>>((ref) async {
  final service = ref.watch(localContactServiceProvider);
  final hasPermission = await service.hasPermission();
  if (!hasPermission) {
    final granted = await service.requestPermission();
    if (!granted) return [];
  }
  return service.getAllContacts();
});

/// Search query state.
final contactSearchQueryProvider = StateProvider<String>((ref) => '');

/// Filtered contacts based on search query.
final filteredContactsProvider = FutureProvider<List<Contact>>((ref) async {
  final contacts = await ref.watch(contactsProvider.future);
  final query = ref.watch(contactSearchQueryProvider);
  if (query.isEmpty) return contacts;
  final lowerQuery = query.toLowerCase();
  return contacts.where((c) {
    return c.bestName.toLowerCase().contains(lowerQuery) ||
        c.phones.any((p) => p.number.contains(query)) ||
        c.emails.any((e) => e.address.toLowerCase().contains(lowerQuery));
  }).toList();
});
