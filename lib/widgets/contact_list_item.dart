import 'package:flutter/material.dart';
import '../models/contact.dart';

/// A single contact row in the contacts list.
class ContactListItem extends StatelessWidget {
  final Contact contact;
  final VoidCallback? onTap;

  const ContactListItem({super.key, required this.contact, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        foregroundColor: theme.colorScheme.onPrimaryContainer,
        child: Text(
          contact.bestName.isNotEmpty ? contact.bestName[0].toUpperCase() : '?',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(
        contact.bestName,
        style: theme.textTheme.bodyLarge,
      ),
      subtitle: contact.phones.isNotEmpty
          ? Text(contact.phones.first.number)
          : contact.emails.isNotEmpty
              ? Text(contact.emails.first.address)
              : null,
      onTap: onTap,
    );
  }
}
