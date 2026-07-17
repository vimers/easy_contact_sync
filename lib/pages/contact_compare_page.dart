import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../services/sync/diff_engine.dart';
import '../widgets/contact_photo.dart';
import '../widgets/diff_viewer.dart';

/// Read-only side-by-side comparison of a contact's local vs remote fields.
/// Reached by tapping the "differing" status icon on a contact.
class ContactComparePage extends StatelessWidget {
  final Contact localContact;
  final Contact remoteContact;

  const ContactComparePage({
    super.key,
    required this.localContact,
    required this.remoteContact,
  });

  @override
  Widget build(BuildContext context) {
    final diffEngine = DiffEngine();
    final fieldDiffs =
        diffEngine.computeFieldDiff(localContact, remoteContact);

    final Widget? photoCard =
        localContact.photo != remoteContact.photo ? _buildPhotoCard(context) : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(localContact.bestName),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.sync_problem, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This contact differs between this phone and the remote server.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: DiffViewerWidget(fieldDiffs: fieldDiffs, leading: photoCard),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Photo',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _avatarColumn(
                    context,
                    photo: localContact.photo,
                    name: localContact.bestName,
                    label: 'Local',
                    color: Colors.blue,
                  ),
                ),
                Icon(Icons.swap_horiz, color: theme.colorScheme.outline),
                Expanded(
                  child: _avatarColumn(
                    context,
                    photo: remoteContact.photo,
                    name: remoteContact.bestName,
                    label: 'Remote',
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarColumn(
    BuildContext context, {
    required String? photo,
    required String name,
    required String label,
    required Color color,
  }) {
    final bytes = ContactPhoto.tryDecode(photo);
    final hasPhoto = bytes != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: hasPhoto ? () => _showFullPhoto(context, bytes, label) : null,
          child: hasPhoto
              ? ContactPhoto(
                  base64Photo: photo,
                  fallbackInitial: _initialOf(name),
                  radius: 32,
                )
              : _noPhotoPlaceholder(),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _noPhotoPlaceholder() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey.shade300,
        border: Border.all(color: Colors.grey.shade400, width: 1.5),
      ),
      child: const Icon(Icons.person, color: Colors.grey),
    );
  }

  String _initialOf(String name) =>
      name.isNotEmpty ? name[0].toUpperCase() : '?';

  void _showFullPhoto(BuildContext context, Uint8List bytes, String label) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(ctx).size.width * 0.8,
                    maxHeight: MediaQuery.of(ctx).size.height * 0.7,
                  ),
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.broken_image, size: 48),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
