# Avatar Diff in the Comparison View

**Date:** 2026-07-17
**Status:** Approved (design)
**Scope:** `ContactComparePage` only.

## Problem

A changed contact photo already makes a contact register as "differing" (the
photo length is part of `Contact.contentHash`), so the user sees the orange
"differ" status icon and can open the compare page. But `DiffEngine.computeFieldDiff`
does not include the photo, and the diff viewer only renders text — so the user
opens the compare page and **cannot see what changed about the photo**. Worse,
nowhere in the app renders a contact photo at all today (list and detail pages
both show a letter avatar).

## Goal

When the local and remote photos differ, show both avatars side by side in the
comparison view so the user can see the difference.

## Non-goals

- Rendering photos on the contacts list or contact detail page (separate task;
  the new widget is reusable so this is a natural follow-on, but not done here).
- Localizing the compare-page strings (that page already hardcodes English;
  wiring it into l10n is a separate task).
- Editing/choosing a photo to resolve the difference (the compare page is
  read-only today and stays that way).

## Design

### Architecture / boundaries

Two units, each with one clear purpose:

1. **`ContactPhoto` widget** (`lib/widgets/contact_photo.dart`) — given a
   `String? base64Photo`, a fallback initial (e.g. first letter of the name),
   and a radius, renders a `CircleAvatar`:
   - Decoded image (`Image.memory(base64Decode(photo))`) when a decodable photo
     is present.
   - Letter avatar (existing pattern: `primaryContainer` background, bold
     uppercase initial) when the photo is `null`, empty, or fails to decode.
   - Owns all base64 decode + error handling with **two** complementary
     defenses, so callers never deal with bytes: (1) try/catch around
     `base64Decode` for malformed/non-base64 `PHOTO` values (e.g. a URL); and
     (2) an `errorBuilder` on `Image.memory` for bytes that decode but are not a
     valid image. Either failure renders the letter-avatar fallback.

2. **`ContactComparePage`** — computes whether the photos differ and builds a
   "Photo" card, passing it to `DiffViewerWidget` via a new optional `leading`
   slot so it scrolls as the **first row** of the same list (not pinned above
   it). The text diff pipeline is untouched.

3. **`DiffViewerWidget`** — gains one backward-compatible optional parameter,
   `Widget? leading`. When non-null it is rendered as the first item of the
   diff `ListView` (same scroll, same spacing as the field-diff cards). Its
   text-diff rendering is unchanged. When `leading` is null the widget behaves
   exactly as today.

### What does NOT change

- `DiffEngine`, `computeFieldDiff`, `FieldDiff`, `Contact`. `DiffViewerWidget`
  gains only the optional `leading` slot described above — no other change.
- The photo is **not** added to `computeFieldDiff`. Rationale: it is binary and
  does not fit the text `FieldDiff` model; rendering it in the page keeps the
  text diff pipeline clean.

### When the card appears

`localContact.photo != remoteContact.photo` — a base64 string comparison. This
covers two cases: both sides have different photos, and one side has a photo
while the other does not. When the photos are equal, no card is rendered and the
page behaves exactly as today.

### Card layout

Styled to match the existing `FieldDiff` cards (same `Card` + `Padding` +
`Column`; same `titleSmall` bold title), so it reads as the first item in the
diff list:

- Title: `Photo`.
- Two `ContactPhoto` avatars side by side, with `Icons.swap_horiz` between them.
- Colored label chips below each avatar: `Local` (blue) and `Remote` (green),
  matching the existing diff viewer's Local=blue / Remote=green convention.

### Tap to enlarge

Tapping either avatar opens a full-screen dialog showing that image larger
(simple `Dialog` with the image fit to screen width). Useful because the
side-by-side avatars are small. Tapping the dialog dismisses it.

### Edge cases

- **Only one side has a photo.** The empty side renders a dashed-border
  placeholder containing `Icons.person` (or `Icons.broken_image_outlined`) so
  the asymmetry is obvious. This is still rendered through the compare page,
  not the `ContactPhoto` widget (the placeholder is specific to the diff card).
- **Photo is a URL or corrupt.** vCard `PHOTO` is not always base64 (it can be a
  URL), and bytes can be truncated. `base64Decode` in `ContactPhoto` is wrapped
  in try/catch and falls back to the letter avatar. The app never crashes on a
  bad photo.
- **No photo difference.** No card; identical to today.
- **Photos differ but every text field is identical.** `computeFieldDiff`
  returns no differing fields, but the `leading` Photo card is non-null, so the
  list shows just the Photo card — not the "No differences" empty state.

### Strings

Hardcoded English: `Photo`, `Local`, `Remote`, `No photo`. This matches the
existing compare page, which already hardcodes its banner text and labels.

## Testing

- Unit-style widget tests for `ContactPhoto`:
  - decodes a valid base64 image and shows `Image.memory`;
  - falls back to the letter avatar when photo is `null`, empty, or invalid
    base64 / URL.
- Widget test for `DiffViewerWidget`:
  - when `leading` is provided, it renders as the first list item;
  - when `leading` is null, behavior is unchanged (backward compatible);
  - when `leading` is provided but no field diffs differ, it still shows the
    leading card instead of the "No differences" empty state.
- Widget test for `ContactComparePage`:
  - when `localContact.photo != remoteContact.photo`, the `Photo` card is shown
    (find the `Photo` title and both avatars);
  - when photos are equal, the `Photo` card is **not** shown;
  - when only one side has a photo, the placeholder is shown on the empty side;
  - tapping an avatar opens the full-screen view.

Manual verification: run the app, open a contact whose photo differs between
phone and server (or fabricate one via a test contact), confirm the two avatars
render and tap-to-enlarge works.

## Risks

- A photo whose base64 decodes but is not a valid image (wrong bytes) —
  Flutter's `Image.memory` will throw asynchronously on decode. Mitigation:
  `ContactPhoto` uses `Image.memory` with an `errorBuilder`, so a bad image
  renders the fallback rather than throwing into the UI.
