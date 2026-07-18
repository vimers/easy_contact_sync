# Avatar Diff in Comparison View — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a contact's local and remote photos differ, show both avatars side by side as the first row of the comparison view's diff list.

**Architecture:** A new reusable `ContactPhoto` widget owns base64 decoding + fallback rendering. `ContactComparePage` builds a "Photo" card (two avatars, labels, arrow, tap-to-enlarge, missing-photo placeholder) and passes it to `DiffViewerWidget` via a new backward-compatible `leading` slot, so it scrolls as the first item of the existing diff list. `DiffEngine` / `computeFieldDiff` / `FieldDiff` / `Contact` are not changed — the photo never enters the text-diff pipeline.

**Tech Stack:** Flutter (Dart), `flutter_test`, `dart:convert` (`base64Decode`), `dart:typed_data` (`Uint8List`). Package name `easy_contact_sync`. Color API uses `Color.withValues(alpha:)` (matches the existing `diff_viewer.dart`).

---

## File Structure

- **Create** `lib/widgets/contact_photo.dart` — renders a base64 contact photo as a circular avatar, with a letter-avatar fallback when the photo is missing/undecodable. Exposes a `static Uint8List? tryDecode(String?)` helper (reused by the compare page's full-screen view).
- **Create** `test/widgets/contact_photo_test.dart` — widget tests for `ContactPhoto`.
- **Modify** `lib/widgets/diff_viewer.dart` — add optional `Widget? leading` parameter; render it as the first item of the diff `ListView`; only show the "No differences" empty state when there are no differing fields AND no `leading`.
- **Create** `test/widgets/diff_viewer_test.dart` — widget tests for the `leading` slot.
- **Modify** `lib/pages/contact_compare_page.dart` — build the Photo card and pass it as `leading` when `localContact.photo != remoteContact.photo`.
- **Create** `test/pages/contact_compare_page_test.dart` — widget tests for the Photo card show/hide, missing-photo placeholder, and tap-to-enlarge.

---

## Task 1: `ContactPhoto` widget

**Files:**
- Create: `lib/widgets/contact_photo.dart`
- Test: `test/widgets/contact_photo_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/widgets/contact_photo_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_contact_sync/widgets/contact_photo.dart';

// A valid 1x1 red PNG, base64-encoded.
const _validPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('renders the decoded image when photo is valid base64', (tester) async {
    await tester.pumpWidget(_wrap(
      ContactPhoto(base64Photo: _validPngBase64, fallbackInitial: 'A'),
    ));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('A'), findsNothing);
  });

  testWidgets('falls back to the letter avatar when photo is null', (tester) async {
    await tester.pumpWidget(_wrap(
      ContactPhoto(base64Photo: null, fallbackInitial: 'A'),
    ));
    expect(find.byType(Image), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('falls back to the letter avatar when photo is empty', (tester) async {
    await tester.pumpWidget(_wrap(
      ContactPhoto(base64Photo: '', fallbackInitial: 'A'),
    ));
    expect(find.byType(Image), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('falls back to the letter avatar when photo is not base64 (e.g. a URL)',
      (tester) async {
    await tester.pumpWidget(_wrap(
      ContactPhoto(base64Photo: 'https://example.com/photo.jpg', fallbackInitial: 'A'),
    ));
    expect(find.byType(Image), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });

  test('tryDecode returns null for null/empty/non-base64 and bytes for valid base64', () {
    expect(ContactPhoto.tryDecode(null), isNull);
    expect(ContactPhoto.tryDecode(''), isNull);
    expect(ContactPhoto.tryDecode('https://example.com/photo.jpg'), isNull);
    expect(ContactPhoto.tryDecode(_validPngBase64), isNotNull);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/widgets/contact_photo_test.dart`
Expected: FAIL with a compilation error — `contact_photo.dart` does not exist / `ContactPhoto` is undefined.

- [ ] **Step 3: Write the implementation**

Create `lib/widgets/contact_photo.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Renders a contact's base64 photo as a circular avatar.
///
/// Falls back to a bold initial letter when the photo is missing, empty, not
/// valid base64 (some vCard PHOTO values are URLs), or fails to decode as an
/// image. All decode/error handling lives here so callers stay declarative.
class ContactPhoto extends StatelessWidget {
  final String? base64Photo;
  final String fallbackInitial;
  final double radius;

  const ContactPhoto({
    super.key,
    required this.base64Photo,
    required this.fallbackInitial,
    this.radius = 24,
  });

  /// Decodes [base64Photo] to raw bytes, or returns null when it is null/empty
  /// or not valid base64 (e.g. a vCard PHOTO URL). Shared so the compare page's
  /// full-screen viewer decodes consistently with this widget.
  static Uint8List? tryDecode(String? base64Photo) {
    if (base64Photo == null || base64Photo.isEmpty) return null;
    try {
      return base64Decode(base64Photo);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = tryDecode(base64Photo);
    final initial = fallbackInitial.isEmpty ? '?' : fallbackInitial;
    final fallback = Text(
      initial,
      style: const TextStyle(fontWeight: FontWeight.bold),
    );
    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primaryContainer,
      foregroundColor: theme.colorScheme.onPrimaryContainer,
      child: bytes == null
          ? fallback
          : ClipOval(
              child: Image.memory(
                bytes,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => fallback,
              ),
            ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/widgets/contact_photo_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/contact_photo.dart test/widgets/contact_photo_test.dart
git commit -m "feat: add ContactPhoto widget for base64 avatar rendering"
```

---

## Task 2: `DiffViewerWidget` optional `leading` slot

**Files:**
- Modify: `lib/widgets/diff_viewer.dart`
- Test: `test/widgets/diff_viewer_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/widgets/diff_viewer_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_contact_sync/models/conflict_item.dart';
import 'package:easy_contact_sync/widgets/diff_viewer.dart';

const _differing = [FieldDiff(fieldName: 'displayName', localValue: 'a', remoteValue: 'b')];

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders the leading widget as the first item when provided', (tester) async {
    await tester.pumpWidget(_wrap(DiffViewerWidget(
      fieldDiffs: _differing,
      leading: const Text('LEADING_MARKER'),
    )));
    expect(find.text('LEADING_MARKER'), findsOneWidget);
    expect(find.text('displayName'), findsOneWidget);
  });

  testWidgets('behaves unchanged when leading is null (backward compatible)', (tester) async {
    await tester.pumpWidget(_wrap(DiffViewerWidget(fieldDiffs: _differing)));
    expect(find.text('displayName'), findsOneWidget);
    expect(find.text('No differences'), findsNothing);
  });

  testWidgets('shows "No differences" only when there are no field diffs AND no leading',
      (tester) async {
    await tester.pumpWidget(_wrap(DiffViewerWidget(fieldDiffs: const [])));
    expect(find.text('No differences'), findsOneWidget);
  });

  testWidgets('shows the leading card (not "No differences") when fields match but leading exists',
      (tester) async {
    await tester.pumpWidget(_wrap(DiffViewerWidget(
      fieldDiffs: const [FieldDiff(fieldName: 'displayName', localValue: 'a', remoteValue: 'a')],
      leading: const Text('LEADING_MARKER'),
    )));
    expect(find.text('LEADING_MARKER'), findsOneWidget);
    expect(find.text('No differences'), findsNothing);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/widgets/diff_viewer_test.dart`
Expected: FAIL — `DiffViewerWidget` has no `leading` parameter (compile error).

- [ ] **Step 3: Write the implementation**

Modify `lib/widgets/diff_viewer.dart`. Replace the whole file with:

```dart
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/widgets/diff_viewer_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/diff_viewer.dart test/widgets/diff_viewer_test.dart
git commit -m "feat: add optional leading slot to DiffViewerWidget"
```

---

## Task 3: Photo diff card in `ContactComparePage`

**Files:**
- Modify: `lib/pages/contact_compare_page.dart`
- Test: `test/pages/contact_compare_page_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/pages/contact_compare_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_contact_sync/models/contact.dart';
import 'package:easy_contact_sync/pages/contact_compare_page.dart';
import 'package:easy_contact_sync/widgets/contact_photo.dart';

// Two distinct, valid 1x1 PNGs so the two sides render different images.
const _imgA =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const _imgB =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMBAQDJ/pLvAAAAAElFTkSuQmCC';

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('shows Photo card when photos differ', (tester) async {
    await tester.pumpWidget(_wrap(ContactComparePage(
      localContact: const Contact(displayName: 'Alice', photo: _imgA),
      remoteContact: const Contact(displayName: 'Alice', photo: _imgB),
    )));
    expect(find.text('Photo'), findsOneWidget);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('Remote'), findsOneWidget);
    expect(find.byType(ContactPhoto), findsNWidgets(2));
  });

  testWidgets('hides Photo card when photos are equal', (tester) async {
    await tester.pumpWidget(_wrap(ContactComparePage(
      localContact: const Contact(displayName: 'Alice', photo: _imgA),
      remoteContact: const Contact(displayName: 'Alice', photo: _imgA),
    )));
    expect(find.text('Photo'), findsNothing);
  });

  testWidgets('hides Photo card when both photos are null', (tester) async {
    await tester.pumpWidget(_wrap(ContactComparePage(
      localContact: const Contact(displayName: 'Alice'),
      remoteContact: const Contact(displayName: 'Alice'),
    )));
    expect(find.text('Photo'), findsNothing);
  });

  testWidgets('shows a no-photo placeholder on the side without a photo', (tester) async {
    await tester.pumpWidget(_wrap(ContactComparePage(
      localContact: const Contact(displayName: 'Alice', photo: _imgA),
      remoteContact: const Contact(displayName: 'Alice'),
    )));
    expect(find.text('Photo'), findsOneWidget);
    // Only the local side has a decodable photo.
    expect(find.byType(ContactPhoto), findsOneWidget);
    // The empty side shows the person placeholder icon.
    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testWidgets('tapping an avatar opens a full-screen view', (tester) async {
    await tester.pumpWidget(_wrap(ContactComparePage(
      localContact: const Contact(displayName: 'Alice', photo: _imgA),
      remoteContact: const Contact(displayName: 'Alice', photo: _imgB),
    )));
    await tester.tap(find.byType(ContactPhoto).first);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/pages/contact_compare_page_test.dart`
Expected: FAIL — the Photo card / labels do not exist yet (`find.text('Photo')` finds nothing).

- [ ] **Step 3: Write the implementation**

Modify `lib/pages/contact_compare_page.dart`. Replace the whole file with:

```dart
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
    final hasPhoto = photo != null && photo.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: hasPhoto ? () => _showFullPhoto(context, photo, label) : null,
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

  void _showFullPhoto(BuildContext context, String base64Photo, String label) {
    final bytes = ContactPhoto.tryDecode(base64Photo);
    if (bytes == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: Image.memory(bytes),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/pages/contact_compare_page_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/pages/contact_compare_page.dart test/pages/contact_compare_page_test.dart
git commit -m "feat: show avatar diff card in contact compare view"
```

---

## Task 4: Full-suite check and manual verification

**Files:** none (verification only).

- [ ] **Step 1: Run the entire test suite**

Run: `flutter test`
Expected: PASS — all existing tests plus the 14 new ones (5 + 4 + 5) green.

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`
Expected: "No issues found!" (or only pre-existing warnings unrelated to this change).

- [ ] **Step 3: Manual verification**

Build and run the app on a device/emulator, open a contact marked "differing" whose photo differs between phone and server (or temporarily inject a differing photo for testing). Confirm:
- Two avatars appear side by side under a "Photo" title, with `Local`/`Remote` labels and an arrow between them.
- The card scrolls together with the field-diff cards.
- If only one side has a photo, the other side shows the grey person placeholder.
- Tapping an avatar opens a larger full-screen view; tapping the image dismisses it.
- A contact whose photos are equal shows no Photo card.

(If no real differing-photo contact is available, the widget tests in Tasks 1–3 already cover the behavior; manual verification is a confidence check, not a gate.)

- [ ] **Step 4: Final commit if any tweaks were made during manual verification**

Only if Step 3 surfaced a change. Otherwise skip.

```bash
git add -A
git commit -m "fix: avatar diff manual-verification tweaks"
```

---

## Self-Review

**Spec coverage:**
- `ContactPhoto` widget (decode + fallback) → Task 1. ✓
- `DiffViewerWidget` optional `leading` slot → Task 2. ✓
- Photo card as first row of diff list, shown only when photos differ → Task 3. ✓
- Side-by-side avatars + Local/Remote colored labels + arrow → Task 3. ✓
- Tap to enlarge → Task 3 (`_showFullPhoto`) + test. ✓
- Missing-photo placeholder on the empty side → Task 3 (`_noPhotoPlaceholder`) + test. ✓
- Robust to URL/corrupt photo (try/catch + errorBuilder) → Task 1. ✓
- No changes to `DiffEngine`/`computeFieldDiff`/`FieldDiff`/`Contact` → confirmed; none of the tasks touch them. ✓
- Empty-state: photos differ but all fields identical → still shows Photo card (Task 2 test + Task 3 wiring). ✓

**Placeholder scan:** No TBD/TODO; every code step contains full code.

**Type consistency:** `ContactPhoto(base64Photo:, fallbackInitial:, radius:)` signature and `ContactPhoto.tryDecode(String?) → Uint8List?` are used identically in Tasks 1 and 3. `DiffViewerWidget(fieldDiffs:, leading:)` matches between Task 2 and Task 3.
