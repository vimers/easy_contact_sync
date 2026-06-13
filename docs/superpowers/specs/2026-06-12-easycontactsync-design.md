# EasyContactSync Design Spec

## Overview

EasyContactSync is an open-source, cross-platform mobile app (Android + iOS) built with Flutter that synchronizes contacts via the CardDAV protocol (RFC 6352). It supports configurable background sync, field-level diff display between local and remote contacts, and user-driven conflict resolution. CardDAV credentials are encrypted at rest using platform-native secure storage.

## Architecture: Pure Dart (Option A)

All CardDAV protocol logic is implemented in pure Dart. No native platform channel code required for the sync layer. Platform-specific capabilities (encrypted storage, background tasks, contact access) are accessed via Flutter plugins.

```
┌─────────────────────────────────────────┐
│              UI Layer (Flutter)          │
│  ┌──────┐ ┌──────────┐ ┌─────────────┐  │
│  │账号  │ │联系人列表│ │冲突解决页面 │  │
│  │管理  │ │+ 搜索    │ │(差异对比)   │  │
│  └──────┘ └──────────┘ └─────────────┘  │
├─────────────────────────────────────────┤
│            Business Logic Layer          │
│  ┌──────────┐ ┌────────┐ ┌───────────┐  │
│  │ Sync     │ │ Diff   │ │ Conflict  │  │
│  │ Engine   │ │ Engine │ │ Resolver  │  │
│  └──────────┘ └────────┘ └───────────┘  │
├─────────────────────────────────────────┤
│              Data Layer                  │
│  ┌──────────┐ ┌────────┐ ┌───────────┐  │
│  │CardDAV   │ │Local   │ │ Secure    │  │
│  │Client    │ │Contact │ │ Storage   │  │
│  │(Dart HTTP│ │Provider│ │(加密凭证) │  │
│  │ + XML)   │ │        │ │           │  │
│  └──────────┘ └────────┘ └───────────┘  │
├─────────────────────────────────────────┤
│          Platform Layer                  │
│  ┌──────────┐ ┌──────────────────────┐  │
│  │flutter_  │ │ workmanager          │  │
│  │contacts  │ │ (定时后台同步)        │  │
│  └──────────┘ └──────────────────────┘  │
└─────────────────────────────────────────┘
```

State management: `flutter_riverpod`.

## CardDAV Client

Standard CardDAV operations based on RFC 6352:

| Operation | HTTP Method | Purpose |
|-----------|------------|---------|
| Discovery | PROPFIND + well-known | Auto-discover address book URL |
| List | REPORT (addressbook-query) | Fetch remote contact list (vCard) |
| Get | GET | Fetch single contact full vCard |
| Create | PUT | Create contact |
| Update | PUT | Update contact |
| Delete | DELETE | Delete contact |
| Sync | REPORT (sync-collection) | Incremental sync (changes only) |

Remote contacts are parsed from vCard (3.0/4.0) into an internal `Contact` model with fields: name, phone, email, organization, note, etc.

## Encrypted Credential Storage

Uses `flutter_secure_storage`:

- **Android**: EncryptedSharedPreferences + Android Keystore (AES256)
- **iOS**: Keychain Services (kSecAttrAccessible: whenUnlockedThisDeviceOnly)

Stored items:
- `server_url` (plaintext, not sensitive)
- `username` (plaintext)
- `password` (encrypted via flutter_secure_storage)
- `sync_token` (encrypted, used for incremental sync)

Optional biometric lock: require fingerprint/face unlock to view saved credentials.

## Sync Engine

### Flow

1. Triggered by timer (configurable interval) or manual action
2. Fetch remote changes via sync-collection REPORT
3. Read local contacts via flutter_contacts
4. Diff engine compares local vs remote by UID
5. Auto-resolve non-conflicting changes:
   - Local-only → push to remote
   - Remote-only → pull to local
   - Local deleted → delete from remote
   - Remote deleted → delete from local
6. Conflicting changes (both sides modified same contact) → present to user

### Diff Engine

Matches contacts by vCard UID. For each contact:
- Compare ETag/content hash to detect changes
- Categorize: local-only, remote-only, local-deleted, remote-deleted, both-modified (conflict)

### Background Sync

Configurable intervals: 15min / 30min / 1h / 6h / manual only.

- **Android**: WorkManager PeriodicWorkRequest with NetworkRequired constraint, works during Doze
- **iOS**: BGAppRefreshTask (system-controlled timing) + auto-sync on app open as fallback

Notifications:
- Sync failure → local notification
- Conflicts detected → local notification prompting user to open app

## Conflict Resolution UI

```
┌──────────────────────────────────┐
│  冲突解决 (3个联系人)              │
│                                  │
│  ┌─────── 批量操作 ──────────┐   │
│  │ [全部用本地] [全部用远端]  │   │
│  └───────────────────────────┘   │
│                                  │
│  张三                            │
│  ┌──本地──┐  ┌──远端──┐         │
│  │电话: xxx│  │电话: yyy│         │
│  │邮箱: a@b│  │邮箱: c@d│         │
│  └─────────┘  └─────────┘         │
│  [用本地]  [用远端]  [查看详情]    │
│                                  │
│         [确认同步]                │
└──────────────────────────────────┘
```

- Batch actions: "Use all local" / "Use all remote"
- Per-contact override: select local or remote individually
- Detail view: field-by-field comparison
- Silent completion when no conflicts

## Page Navigation

Bottom navigation with 3 tabs:

1. **Contacts**: Local contact list with search and alphabetical index. Tap to view detail.
2. **Sync Status**: Last sync time, sync log (success/fail/conflict count), manual sync button. Entry point to conflict resolution.
3. **Settings**: CardDAV account management (CRUD), sync frequency, encryption options, language switch, about page.

Additional pages:
- Contact detail (from contacts tab)
- Conflict resolution (from sync status tab or notification)

## Tech Stack

| Category | Choice | Notes |
|----------|--------|-------|
| Framework | Flutter 3.x + Dart 3.x | Null safety, min Android 6.0 / iOS 13.0 |
| State management | flutter_riverpod | Lightweight, compile-time safe |
| CardDAV | Pure Dart (http + xml) | RFC 6352 |
| Local contacts | flutter_contacts | Read/write system address book |
| Encrypted storage | flutter_secure_storage | Android KeyStore / iOS Keychain |
| Background tasks | workmanager | Periodic tasks on both platforms |
| vCard parsing | Custom vcard_parser | vCard 3.0 + 4.0 |
| Local notifications | flutter_local_notifications | Sync result notifications |
| i18n | flutter_localizations + intl | ARB files, extensible |
| Routing | go_router | Declarative routing |
| Database | sqflite | Sync metadata only |

## Project Structure

```
lib/
├── main.dart
├── l10n/                        # i18n ARB files
│   ├── app_en.arb
│   └── app_zh.arb
├── models/                      # Data models
│   ├── contact.dart
│   ├── sync_record.dart
│   ├── account.dart
│   └── conflict_item.dart
├── services/                    # Core services
│   ├── carddav/
│   │   ├── carddav_client.dart
│   │   ├── discovery.dart
│   │   └── operations.dart
│   ├── vcard/
│   │   ├── vcard_parser.dart
│   │   └── vcard_writer.dart
│   ├── sync/
│   │   ├── sync_engine.dart
│   │   ├── diff_engine.dart
│   │   └── conflict_resolver.dart
│   ├── local_contact_service.dart
│   ├── secure_storage_service.dart
│   └── background_sync_service.dart
├── providers/                   # Riverpod providers
│   ├── contacts_provider.dart
│   ├── sync_provider.dart
│   ├── accounts_provider.dart
│   └── settings_provider.dart
├── pages/                       # Pages
│   ├── contacts_page.dart
│   ├── contact_detail_page.dart
│   ├── sync_status_page.dart
│   ├── conflict_page.dart
│   └── settings/
│       ├── settings_page.dart
│       ├── account_edit_page.dart
│       └── about_page.dart
├── widgets/                     # Shared widgets
│   ├── contact_list_item.dart
│   ├── diff_viewer.dart
│   └── sync_status_badge.dart
└── theme/
    └── app_theme.dart           # Material 3 theme
```

## Local Database (sqflite)

Stores sync metadata only. Contacts are managed by the system address book.

| Table | Fields | Purpose |
|-------|--------|---------|
| `accounts` | id, server_url, username, created_at | CardDAV accounts |
| `sync_meta` | account_id, uid, etag, last_sync_hash | Remote state snapshot per contact |
| `sync_log` | id, account_id, timestamp, status, conflicts_count | Sync history log |
| `settings` | key, value | User settings (sync frequency, language, etc.) |

## Design Decisions

1. **Pure Dart CardDAV**: Single codebase, low maintenance, low contribution barrier for open-source community.
2. **riverpod over bloc**: Lighter weight, sufficient for this data-driven app.
3. **sqflite for metadata only**: Contacts stay in system address book; we only track sync state.
4. **vCard parser custom-built**: Existing Dart vCard packages are limited/maintained; a focused parser covering vCard 3.0/4.0 fields we need is simpler and more maintainable.
5. **workmanager for background sync**: Best cross-platform option. iOS limitations mitigated by auto-sync on app open.
