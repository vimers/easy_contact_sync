import 'package:flutter/material.dart';
import '../models/contact.dart';

/// Detail page showing all fields of a single contact.
class ContactDetailPage extends StatelessWidget {
  final Contact contact;

  const ContactDetailPage({super.key, required this.contact});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(contact.bestName),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with avatar
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                    child: Text(
                      contact.bestName.isNotEmpty ? contact.bestName[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    contact.bestName,
                    style: theme.textTheme.headlineSmall,
                  ),
                  if (contact.organization != null) ...[
                    const SizedBox(height: 4),
                    Text(contact.organization!, style: theme.textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Phone numbers
            if (contact.phones.isNotEmpty) ...[
              _sectionTitle(context, 'Phone'),
              ...contact.phones.map((p) => _infoRow(context, p.label, p.number, Icons.phone)),
            ],

            // Emails
            if (contact.emails.isNotEmpty) ...[
              _sectionTitle(context, 'Email'),
              ...contact.emails.map((e) => _infoRow(context, e.label, e.address, Icons.email)),
            ],

            // Organization & Title
            if (contact.title != null) ...[
              _sectionTitle(context, 'Title'),
              _infoRow(context, '', contact.title!, Icons.badge),
            ],

            // Note
            if (contact.note != null) ...[
              _sectionTitle(context, 'Note'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(contact.note!),
              ),
            ],

            // Birthday
            if (contact.birthday != null) ...[
              _sectionTitle(context, 'Birthday'),
              _infoRow(context, '', _formatDate(contact.birthday!), Icons.cake),
            ],

            // Addresses
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
