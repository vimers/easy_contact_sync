# EasyContactSync

An open-source, cross-platform mobile app (Android + iOS) that synchronizes contacts via the CardDAV protocol (RFC 6352).

## Features

- **CardDAV Sync**: Full support for standard CardDAV protocol
- **Background Sync**: Configurable intervals (15min / 30min / 1h / 6h / manual)
- **Diff Display**: Field-level comparison between local and remote contacts
- **Conflict Resolution**: Batch or per-contact resolution with visual diff
- **Encrypted Storage**: Credentials encrypted via Android Keystore / iOS Keychain
- **Multi-language**: i18n support with extensible ARB files

## Getting Started

### Prerequisites

- Flutter SDK >= 3.0.0
- Dart SDK >= 3.0.0
- Android Studio / Xcode for platform-specific builds

### Install & Run

```bash
flutter pub get
flutter run
```

### Build

```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release
```

## Tech Stack

| Category | Technology |
|----------|-----------|
| Framework | Flutter 3.x + Dart 3.x |
| State Management | flutter_riverpod |
| CardDAV | Pure Dart (http + xml) |
| Local Contacts | flutter_contacts |
| Encrypted Storage | flutter_secure_storage |
| Background Tasks | workmanager |
| Database | sqflite |
| i18n | flutter_localizations + intl |

## License

MIT
