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
