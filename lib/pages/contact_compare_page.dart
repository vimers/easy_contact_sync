import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../services/sync/diff_engine.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: Text(localContact.bestName),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: const [
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
          Expanded(child: DiffViewerWidget(fieldDiffs: fieldDiffs)),
        ],
      ),
    );
  }
}
