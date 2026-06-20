# GitHub Actions Workflows — Design Spec

**Date:** 2026-06-20
**Repo:** `vimers/easy_contact_sync`
**Goal:** Add CI so that (1) every PR must pass a compile check before merging, and (2) pushing a `v*` tag builds an APK and attaches it to that tag's GitHub Release.

## Background / constraints discovered

- No `.github/` directory exists yet — greenfield.
- Android signing is already wired in `android/app/build.gradle.kts`: it reads `android/key.properties` and signs release builds with the upload key, **falling back to debug keys when `key.properties` is absent**. The keystore (`*.jks`) and `key.properties` are gitignored.
- Tests exist (`test/widget_test.dart`, `test/services/sync/diff_engine_test.dart`); `analysis_options.yaml` uses `flutter_lints`.
- Gradle 8.10.2; Java 11 source/target. `pubspec.lock` is committed → CI uses the pinned `sqlite3` 2.x (the local-network `.so` issue from memory does not apply on GitHub runners).
- **No Flutter version pin** in the repo.

## Decision: no signing in CI

Per the user's choice, the release APK is built **unsigned / debug-signed** (the existing fallback). No keystore or passwords are needed as GitHub secrets. The release APK is therefore debug-signed — fine for self-distribution/sideloading. Switching to upload-key signing later only requires adding the keystore + passwords as secrets (documented as a future option, out of scope here).

## Prerequisite (must-do, blocks CI): commit the Gradle wrapper

`android/gradlew`, `android/gradlew.bat`, and `android/gradle/wrapper/gradle-wrapper.jar` exist locally but are **gitignored and not committed**. A fresh CI checkout would have no wrapper, so `flutter build apk` would fail.

Fix:
1. `.gitignore` — remove: `**/android/gradlew`, `**/android/gradlew.bat`, `**/android/**/gradle-wrapper.jar`
2. `android/.gitignore` — remove: `gradlew`, `gradlew.bat`, `gradle-wrapper.jar`
3. Commit the three files. (Keep `key.properties`, `*.jks`, `local.properties` ignored.)

## Workflow 1 — `.github/workflows/pr-check.yml` (PR compile check)

- **Trigger:** `pull_request` → `branches: [main]`, types `[opened, synchronize, reopened]`.
- **Runner:** `ubuntu-latest`.
- **Toolchain:** JDK 17 (temurin); Flutter `channel: stable` (via `subosito/flutter-action@v2`, `cache: true` for pub).
- **Gradle cache:** `actions/cache@v4` on `~/.gradle/caches` + `~/.gradle/wrapper`, keyed on `gradle-wrapper.properties` + `**/*.gradle*`.
- **Steps:** `flutter pub get` → `flutter analyze` → `flutter test` → `flutter build apk --debug`.
- **Job name:** `pr-check` → this is the predictable required-status-check name for branch protection.
- `GRADLE_OPTS: -Dorg.gradle.vfs.watch=false` set on build steps (per the WSL2 finding; harmless on CI).
- No signing needed (debug build auto debug-signed).

## Workflow 2 — `.github/workflows/release.yml` (tag → APK)

- **Trigger:** `push` → `tags: ['v*']`.
- **Permissions:** `contents: write` (to create/upload the Release).
- **Steps:** `flutter pub get` → `flutter build apk --release` (debug-signed via fallback) → rename `build/app/outputs/flutter-apk/app-release.apk` to `easy_contact_sync-<tag>.apk` → `softprops/action-gh-release@v2` with `generate_release_notes: true` and `files:` pointing at the renamed APK.

## Branch protection — via `gh` (user-chosen)

The workflows only produce the status check; enforcing "merge only if green" needs a branch-protection rule. The `gh api branches/.../protection` PUT is **full-replace**, so it sets a complete, minimal config (required status check `pr-check`, nothing else):

```bash
gh api -X PUT repos/{owner}/{repo}/branches/main/protection \
  --input - <<'EOF'
{
  "required_status_checks": { "strict": false, "contexts": ["pr-check"] },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false
}
EOF
```

- `strict: false` — does not require the branch to be up-to-date with main before merging (less friction). Set `true` if you want checks to always run against latest main.
- Requires the token to have `administration: write`; gh is already authed as `vimers` (repo owner), so this works.
- The check name `pr-check` must match the job name in Workflow 1 exactly.

## Out of scope (YAGNI)

- iOS build / TestFlight (only APK requested).
- Split-per-ABI APKs (single universal APK chosen).
- Upload-key signing in CI (debug-signed chosen).
- Reusable `workflow_call` indirection (two simple files instead).
- Pinning Flutter to an exact version — using `channel: stable`; pin later if reproducibility demands it.

## Risks / notes

- **`channel: stable` is mutable:** a Flutter stable upgrade could introduce a new lint/analysis failure and temporarily block PRs until addressed. Acceptable now; easy to pin a version later if it bites.
- **Branch-protection PUT is full-replace:** running the gh command overwrites any existing protection on `main`. The current repo has none, so this is safe.
