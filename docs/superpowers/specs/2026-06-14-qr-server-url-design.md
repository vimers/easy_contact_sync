# QR Server-URL Scanner — Design

Date: 2026-06-14

## Goal

On the Add/Edit Account page, add a QR code scanner that fills the Server URL
field from a scanned QR. The QR encodes just the URL.

## Library & permissions

- Dependency: `mobile_scanner` (ML Kit; device confirmed to have Play Services
  + camera).
- Android: `<uses-permission android:name="android.permission.CAMERA"/>`.
- iOS: `NSCameraUsageDescription` in `Info.plist`.

## Component: `lib/pages/qr_scan_page.dart`

Full-screen scanner:
- `MobileScanner` with a `MobileScannerController`, viewfinder frame, hint text,
  cancel button.
- On detect: if the code starts with `http` → `stop()` the controller and
  `Navigator.pop(context, url)`; otherwise show "Not a valid URL" and keep
  scanning.
- Camera permission handled gracefully (no native crash — the lesson from the
  contacts permission bug): if denied, show a message + a button that opens the
  app's system settings. Controller requests permission on start.

## Component: `account_edit_page.dart`

- Add a QR icon button as the Server URL field's `suffixIcon` (the field already
  has no suffix). On tap → push `QrScanPage` → on return with a URL, set
  `_serverUrlController.text` and clear the test result.

## Out of scope (YAGNI)

Torch/gallery import, scan history, parsing anything beyond a plain URL.
