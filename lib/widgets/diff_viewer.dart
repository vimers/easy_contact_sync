import 'package:flutter/material.dart';
import '../models/conflict_item.dart';

/// Widget that displays field-level diffs between local and remote.
class DiffViewerWidget extends StatelessWidget {
  final List<FieldDiff> fieldDiffs;

  /// Optional widget rendered as the first item of the diff list (e.g. the
  /// photo-diff card). Null = behave as before.
  final Widget? leading;

  const DiffViewerWidget({
    super.key,
    required this.fieldDiffs,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diffs = fieldDiffs.where((d) => d.hasDifference).toList();

    if (diffs.isEmpty && leading == null) {
      return const Center(child: Text('No differences'));
    }

    final leadingCount = leading != null ? 1 : 0;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: diffs.length + leadingCount,
      itemBuilder: (context, index) {
        if (leading != null && index == 0) {
          // Caller passes a Card with the same bottom margin as the field cards.
          return leading!;
        }
        final diff = diffs[index - leadingCount];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  diff.fieldName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Local value
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Local',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[700],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              diff.localValue ?? '(empty)',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Remote value
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Remote',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[700],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              diff.remoteValue ?? '(empty)',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
