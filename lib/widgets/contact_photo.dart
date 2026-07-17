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

  /// Text shown when there is no decodable photo.
  ///
  /// Callers should pass an already-formatted initial (e.g. uppercased first
  /// letter) — this widget renders it verbatim and does not transform it.
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
          : Image.memory(
              bytes,
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => fallback,
            ),
    );
  }
}
