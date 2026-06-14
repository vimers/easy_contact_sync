import 'package:flutter/material.dart';
import '../models/contact.dart';
import '../providers/contact_sync_status_provider.dart';

/// A single contact row in the contacts list, with an optional sync-status icon.
class ContactListItem extends StatelessWidget {
  final Contact contact;
  final ContactSyncStatus? status;
  final VoidCallback? onTap;
  // Only `differing` is interactive (opens the compare view).
  final VoidCallback? onStatusTap;

  const ContactListItem({
    super.key,
    required this.contact,
    this.status,
    this.onTap,
    this.onStatusTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusSpec = _statusSpec(status);

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
      trailing: statusSpec != null ? _buildStatusIcon(statusSpec) : null,
      onTap: onTap,
    );
  }

  Widget _buildStatusIcon(_StatusSpec spec) {
    final icon = Icon(spec.icon, color: spec.color, size: 20);
    if (spec == _statusSpec(ContactSyncStatus.differing) && onStatusTap != null) {
      return IconButton(
        icon: icon,
        tooltip: spec.tooltip,
        onPressed: onStatusTap,
        visualDensity: VisualDensity.compact,
      );
    }
    return Tooltip(message: spec.tooltip, child: icon);
  }
}

class _StatusSpec {
  final IconData icon;
  final Color color;
  final String tooltip;
  const _StatusSpec(this.icon, this.color, this.tooltip);
}

// Per-status icon / color / tooltip. Kept here so both the list and any legend
// share one definition.
_StatusSpec? _statusSpec(ContactSyncStatus? status) {
  switch (status) {
    case ContactSyncStatus.localOnly:
      return const _StatusSpec(Icons.phone_android, Colors.grey, 'Only on this phone');
    case ContactSyncStatus.remoteOnly:
      return const _StatusSpec(Icons.cloud_outlined, Colors.grey, 'Only on remote server');
    case ContactSyncStatus.inSync:
      return const _StatusSpec(Icons.check_circle, Colors.green, 'In sync');
    case ContactSyncStatus.differing:
      return const _StatusSpec(Icons.sync_problem, Colors.orange, 'Differs — tap to compare');
    case null:
      return null;
  }
}
