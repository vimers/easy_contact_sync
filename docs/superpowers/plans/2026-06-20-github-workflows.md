# GitHub Actions PR-Check + Tag-Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two GitHub Actions workflows — a PR compile-check that gates merges (via branch protection), and a tag-triggered release APK build that attaches to the tag's GitHub Release.

**Architecture:** Two independent workflow files under `.github/workflows/`. `pr-check.yml` runs `pub get → analyze → test → debug APK build` on PRs to `main` (job named `pr-check` so it's the stable required-check name). `release.yml` runs `pub get → release APK build → rename → attach to Release` on `v*` tags. First, the gitignored Gradle wrapper is committed (CI can't build without it). No signing in CI — the release APK is debug-signed via the existing fallback in `build.gradle.kts`. CI workflows aren't unit-testable, so verification = local YAML syntax check (PyYAML) + the authoritative GitHub run observed via `gh`.

**Tech Stack:** GitHub Actions, `actions/checkout@v4`, `actions/setup-java@v4` (temurin 17), `subosito/flutter-action@v2` (stable), `actions/cache@v4`, `softprops/action-gh-release@v2`, `gh` CLI, Flutter/Dart, Gradle wrapper.

**Spec:** `docs/superpowers/specs/2026-06-20-github-workflows-design.md`

---

## File Structure

- **Create** `.github/workflows/pr-check.yml` — PR compile-check job (`pr-check`).
- **Create** `.github/workflows/release.yml` — tag-triggered release APK + upload job.
- **Modify** `.gitignore` — remove the 3 lines that ignore the Gradle wrapper (`gradlew`, `gradlew.bat`, `gradle-wrapper.jar`).
- **Modify** `android/.gitignore` — remove the same 3 lines.
- **Track** `android/gradlew`, `android/gradlew.bat`, `android/gradle/wrapper/gradle-wrapper.jar` (currently local-only).

Branch: `ci/github-workflows` (already created; spec committed there). Final delivery: a PR that merges into `main`, which also dogfoods the new `pr-check` workflow.

---

## Task 1: Commit the Gradle wrapper (prerequisite — CI cannot build without it)

**Files:**
- Modify: `.gitignore`
- Modify: `android/.gitignore`
- Track: `android/gradlew`, `android/gradlew.bat`, `android/gradle/wrapper/gradle-wrapper.jar`

- [ ] **Step 1: Un-ignore the wrapper in the root `.gitignore`**

Remove these three lines from the `# Android` block:
```
**/android/**/gradle-wrapper.jar
...
**/android/gradlew
**/android/gradlew.bat
```

Concretely, the `# Android` block should go from:
```
# Android
**/android/**/gradle-wrapper.jar
**/android/.gradle
**/android/captures/
**/android/gradlew
**/android/gradlew.bat
**/android/local.properties
**/android/**/GeneratedPluginRegistrant.java
**/android/key.properties
*.jks
```
to:
```
# Android
**/android/.gradle
**/android/captures/
**/android/local.properties
**/android/**/GeneratedPluginRegistrant.java
**/android/key.properties
*.jks
```
(Keep `key.properties` and `*.jks` ignored — signing stays out of git.)

- [ ] **Step 2: Un-ignore the wrapper in `android/.gitignore`**

Remove these three lines:
```
gradle-wrapper.jar
...
/gradlew
/gradlew.bat
```

The file should go from:
```
gradle-wrapper.jar
/.gradle
/captures/
/gradlew
/gradlew.bat
/local.properties
GeneratedPluginRegistrant.java
.cxx/

# Remember to never publicly share your keystore.
# See https://flutter.dev/to/reference-keystore
key.properties
**/*.keystore
**/*.jks
```
to:
```
/.gradle
/captures/
/local.properties
GeneratedPluginRegistrant.java
.cxx/

# Remember to never publicly share your keystore.
# See https://flutter.dev/to/reference-keystore
key.properties
**/*.keystore
**/*.jks
```

- [ ] **Step 3: Stage the wrapper files**

Run:
```bash
git add .gitignore android/.gitignore \
  android/gradlew android/gradlew.bat \
  android/gradle/wrapper/gradle-wrapper.jar
```

- [ ] **Step 4: Verify the wrapper is now tracked**

Run:
```bash
git status --short && \
git ls-files android/gradlew android/gradlew.bat \
  android/gradle/wrapper/gradle-wrapper.jar
```
Expected: `git status` lists all three files as staged (added), and `git ls-files` prints all three paths back. If `git ls-files` is empty, the files are still ignored — re-check Step 1/2 and use `git add -f` as a fallback.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
build(android): commit Gradle wrapper so CI can build

The wrapper (gradlew, gradlew.bat, gradle-wrapper.jar) was gitignored,
which would break fresh CI checkouts. Un-ignore and track them.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add the PR compile-check workflow

**Files:**
- Create: `.github/workflows/pr-check.yml`

- [ ] **Step 1: Create `.github/workflows/pr-check.yml`**

```yaml
name: pr-check

on:
  pull_request:
    branches: [main]
    types: [opened, synchronize, reopened]

permissions:
  contents: read

concurrency:
  group: pr-check-${{ github.ref }}
  cancel-in-progress: true

jobs:
  pr-check:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    env:
      GRADLE_OPTS: -Dorg.gradle.vfs.watch=false
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: Cache Gradle
        uses: actions/cache@v4
        with:
          path: |
            ~/.gradle/caches
            ~/.gradle/wrapper
          key: gradle-${{ runner.os }}-${{ hashFiles('android/**/*.gradle*', 'android/**/gradle-wrapper.properties') }}
          restore-keys: gradle-${{ runner.os }}-

      - name: flutter pub get
        run: flutter pub get

      - name: flutter analyze
        run: flutter analyze

      - name: flutter test
        run: flutter test

      - name: Build debug APK
        run: flutter build apk --debug
```

- [ ] **Step 2: Validate YAML syntax (local pre-check)**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/pr-check.yml')); print('pr-check.yml: valid YAML')"
```
Expected output: `pr-check.yml: valid YAML`. (PyYAML checks syntax only; GitHub validates the Actions schema at run time in Task 4.)

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/pr-check.yml
git commit -m "$(cat <<'EOF'
ci: add pr-check workflow (analyze + test + debug build)

Runs on pull requests to main. Job is named pr-check so it is the
stable required-status-check name for branch protection.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Add the tag-release workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create `.github/workflows/release.yml`**

```yaml
name: release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write

jobs:
  build-and-release:
    runs-on: ubuntu-latest
    timeout-minutes: 45
    env:
      GRADLE_OPTS: -Dorg.gradle.vfs.watch=false
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: Cache Gradle
        uses: actions/cache@v4
        with:
          path: |
            ~/.gradle/caches
            ~/.gradle/wrapper
          key: gradle-${{ runner.os }}-${{ hashFiles('android/**/*.gradle*', 'android/**/gradle-wrapper.properties') }}
          restore-keys: gradle-${{ runner.os }}-

      - name: flutter pub get
        run: flutter pub get

      - name: Build release APK
        run: flutter build apk --release

      - name: Rename APK to include the tag
        run: |
          mv build/app/outputs/flutter-apk/app-release.apk \
             "easy_contact_sync-${GITHUB_REF_NAME}.apk"

      - name: Upload APK to the GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          generate_release_notes: true
          files: easy_contact_sync-${{ github.ref_name }}.apk
```

- [ ] **Step 2: Validate YAML syntax (local pre-check)**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml')); print('release.yml: valid YAML')"
```
Expected output: `release.yml: valid YAML`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "$(cat <<'EOF'
ci: add release workflow (tag -> signed APK in Release)

On v* tag push, builds a universal release APK (debug-signed via the
existing fallback) and attaches it to the tag's GitHub Release with
auto-generated notes.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Push the branch and open the PR (dogfoods `pr-check`)

For a same-repo feature branch, GitHub runs the workflow file from the PR's head branch — so opening this PR triggers `pr-check` on the change itself.

- [ ] **Step 1: Push the branch**

Run:
```bash
git push -u origin ci/github-workflows
```
Expected: push succeeds, prints the new remote branch `origin/ci/github-workflows`.

- [ ] **Step 2: Open the PR**

Run:
```bash
gh pr create --base main --head ci/github-workflows \
  --title "ci: add PR-check and tag-release workflows" \
  --body "$(cat <<'EOF'
## What
- `.github/workflows/pr-check.yml` — on PRs to `main`: `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build apk --debug`. Job name `pr-check` (the required-check name for branch protection).
- `.github/workflows/release.yml` — on `v*` tag push: builds a universal release APK (debug-signed) and attaches it to the tag's Release with auto notes.
- Commits the previously-gitignored Gradle wrapper so fresh CI checkouts can build.

## Notes
- No signing in CI (per decision); release APK is debug-signed.
- Branch protection (require `pr-check`) configured separately via `gh` after this merges.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
Expected: prints the PR URL. The `pr-check` workflow starts running automatically.

- [ ] **Step 3: Watch `pr-check` go green**

Run:
```bash
gh run watch --exit-status $(gh run list --workflow=pr-check.yml --limit=1 --json databaseId -q '.[0].databaseId')
```
Expected: the run reaches `completed` / `success` and the command exits 0. This is the authoritative verification that the workflow is valid and the project compiles/tests/builds under CI.

- [ ] **Step 4: If the run fails — debug**

`gh run view --log-failed` for the failing job. Common causes:
- Gradle wrapper missing → Task 1 wasn't committed (check `git ls-files android/gradlew`).
- `flutter analyze` flags a lint → fix in the same PR, push again.
- `flutter test` fails → fix the test/code.

Do not merge until `pr-check` is green.

---

## Task 5: Merge the PR into `main`

- [ ] **Step 1: Merge**

Run:
```bash
gh pr merge ci/github-workflows --squash --delete-branch
```
Expected: PR is squashed into `main`, remote branch deleted. (Branch protection isn't on yet, so merge is allowed regardless; this brings the workflows onto `main` so they apply to all future PRs/tags.)

- [ ] **Step 2: Sync local `main`**

Run:
```bash
git checkout main && git pull --ff-only
```
Expected: local `main` advances to the squash commit; working tree clean.

---

## Task 6: Require `pr-check` before merging (branch protection via `gh`)

The workflows only produce the status check; enforcement needs a branch-protection rule. The `gh api …/protection` PUT is full-replace — the payload below sets a minimal, complete config. Run from inside the repo so `gh` resolves `{owner}/{repo}` (currently `vimers/easy_contact_sync`).

- [ ] **Step 1: Apply the rule**

Run:
```bash
gh api -X PUT repos/{owner}/{repo}/branches/main/protection --input - <<'EOF'
{
  "required_status_checks": { "strict": false, "contexts": ["pr-check"] },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false
}
EOF
```
Expected: JSON echoing the protection settings (HTTP 200). No error.

- [ ] **Step 2: Verify the rule**

Run:
```bash
gh api repos/{owner}/{repo}/branches/main/protection --jq '.required_status_checks.contexts'
```
Expected output: `["pr-check"]`.

- [ ] **Step 3: Sanity-check with a throwaway PR (optional but recommended)**

Create a trivial change on a branch, open a PR, and confirm the merge button is blocked until `pr-check` passes:
```bash
git checkout -b verify-protection
git commit --allow-empty -m "chore: verify branch protection" 
git push -u origin verify-protection
gh pr create --base main --head verify-protection --title "verify protection" --body "testing pr-check gate" 
gh pr checks
gh pr merge verify-protection --squash --delete-branch   # only after pr-check is green
```
Expected: `gh pr checks` shows `pr-check` as pending→passing; merge succeeds only once green.

---

## Task 7 (optional / on-demand): Verify the release workflow with a real tag

Only do this when ready — pushing a `v*` tag creates a public Release with the APK. To smoke-test without polluting real version numbers, use a throwaway tag and delete it after.

- [ ] **Step 1: Create and push a test tag**

```bash
git checkout main && git pull --ff-only
git tag v0.0.0-ci-test
git push origin v0.0.0-ci-test
```
Expected: the `release` workflow triggers (visible in the Actions tab).

- [ ] **Step 2: Watch the release run go green**

```bash
gh run watch --exit-status $(gh run list --workflow=release.yml --limit=1 --json databaseId -q '.[0].databaseId')
```
Expected: `completed` / `success`, exit 0.

- [ ] **Step 3: Confirm the APK is attached to the Release**

```bash
gh release view v0.0.0-ci-test --json assets --jq '.assets[].name'
```
Expected output: `easy_contact_sync-v0.0.0-ci-test.apk`.

- [ ] **Step 4: Clean up the test tag/release**

```bash
gh release delete v0.0.0-ci-test --yes
git push origin :refs/tags/v0.0.0-ci-test
git tag -d v0.0.0-ci-test
```
Expected: the Release and tag are removed. The next real release is `git tag v1.0.0 && git push origin v1.0.0`.

---

## Done criteria

- `pr-check.yml` exists on `main` and passes on a PR.
- Branch protection requires `pr-check` on `main` (verified).
- `release.yml` exists on `main`; pushing a `v*` tag produces a Release with `easy_contact_sync-<tag>.apk` (verified with a throwaway tag, or left for the first real release).
- Gradle wrapper is committed; `key.properties` / `*.jks` remain ignored.

## Risks / notes (carried from spec)

- `channel: stable` is mutable — a Flutter upgrade could introduce a new lint and block PRs until fixed. Pin a version in both workflows if that bites.
- Branch-protection PUT is full-replace — re-running Task 6 Step 1 overwrites any later manual protection edits on `main`.
