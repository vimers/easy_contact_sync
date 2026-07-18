import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_contact_sync/models/conflict_item.dart';
import 'package:easy_contact_sync/widgets/diff_viewer.dart';

const _differing = [FieldDiff(fieldName: 'displayName', localValue: 'a', remoteValue: 'b')];

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders the leading widget as the first item when provided', (tester) async {
    await tester.pumpWidget(_wrap(
      const DiffViewerWidget(fieldDiffs: _differing, leading: Text('LEADING_MARKER')),
    ));
    expect(find.text('LEADING_MARKER'), findsOneWidget);
    expect(find.text('displayName'), findsOneWidget);
  });

  testWidgets('behaves unchanged when leading is null (backward compatible)', (tester) async {
    await tester.pumpWidget(_wrap(
      const DiffViewerWidget(fieldDiffs: _differing),
    ));
    expect(find.text('displayName'), findsOneWidget);
    expect(find.text('No differences'), findsNothing);
  });

  testWidgets('shows "No differences" only when there are no field diffs AND no leading',
      (tester) async {
    await tester.pumpWidget(_wrap(
      const DiffViewerWidget(fieldDiffs: []),
    ));
    expect(find.text('No differences'), findsOneWidget);
  });

  testWidgets('shows the leading card (not "No differences") when fields match but leading exists',
      (tester) async {
    await tester.pumpWidget(_wrap(
      const DiffViewerWidget(
        fieldDiffs: [FieldDiff(fieldName: 'displayName', localValue: 'a', remoteValue: 'a')],
        leading: Text('LEADING_MARKER'),
      ),
    ));
    expect(find.text('LEADING_MARKER'), findsOneWidget);
    expect(find.text('No differences'), findsNothing);
  });
}
