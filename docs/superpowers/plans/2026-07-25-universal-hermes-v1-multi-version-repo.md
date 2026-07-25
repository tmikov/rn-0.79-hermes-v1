# Universal Hermes V1 Multi-Version Repo — Implementation Plan

> **Amendment (2026-07-25).** The easy-path target below is written as
> `rn-0.85`, but execution pivoted it to **`rn-0.86`**: RN 0.85 pins a JSI
> from just before `jsi::Runtime::isTypedArray` was added to the primary
> `jsi::Runtime` interface, so it can't take a pure bump to `260318099.0.1`
> (dlopen fails on the missing symbol); RN 0.86 can. Read every `rn-0.85` /
> `sample85` below as `rn-0.86` / `sample86`. See the spec's matching
> amendment and `docs/hermes-v1-versioning.md` for the JSI-ABI ceiling.


> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize this single-target repo into a universal guide plus per-version worked examples for running current Hermes V1 (`static_h`) on different React Native versions, with RN 0.79 (hard path) and RN 0.85 (easy path) both building and running on Android against Hermes V1 `260318099.0.1`.

**Architecture:** A thin universal top layer (`README.md` + `docs/`) over self-contained `targets/rn-<ver>/` directories. Current 0.79 content moves intact into `targets/rn-0.79/` (history preserved via `git mv`). A new `targets/rn-0.85/` demonstrates the easy path — overriding the Hermes V1 artifact on an already-V1 RN. Both targets pin the same Hermes V1 stable. iOS is deferred to a Mac-side handoff doc.

**Tech Stack:** React Native 0.79.5 / 0.85.3, Hermes V1 (`facebook/hermes` `static_h`), Gradle + CMake + NDK 27, Android SDK/emulator, Maven Central (`com.facebook.hermes:hermes-android`), `hermes-compiler` npm (release hermesc).

## Global Constraints

- **Hermes V1 = `facebook/hermes` `static_h` branch.** Library is `libhermesvm.so` (never `libhermes.so`). Maven group `com.facebook.hermes` (not `com.facebook.react`).
- **Both targets pin the same Hermes V1 artifact: `com.facebook.hermes:hermes-android:260318099.0.1`** (and matching `hermes-ios` / `hermes-compiler` at `260318099.0.1`). The corresponding source/JSI tag is `hermes-v260318099.0.1`.
- **Android only this pass.** Debug + Release. iOS work is written into `docs/ios-handoff.md`, not executed here.
- **Toolchain (from the 0.79 port):** NDK 27.1.12297006, API 24, STL `c++_shared`, JDK 17. The machine has the Android SDK/NDK + an emulator (confirmed).
- **Preserve git history** for relocated files — use `git mv`, never delete-and-recreate.
- **Container dir is `targets/`.**
- This is a build/integration project: "tests" are build-and-run verification gates (does it compile, does the app launch, is `libhermesvm.so` present, does the engine report V1, does Release bake HBC). Each task ends with such a gate + a commit.

**Verification helpers referenced throughout:**
- Confirm V1 `.so` in an APK: `unzip -l <apk> | grep -E 'libhermes(vm)?\.so'` → expect `libhermesvm.so`, no `libhermes.so`.
- Confirm engine at runtime: `adb logcat | grep -i hermes` and the app's welcome screen (`sample*/App.tsx` renders the engine string).
- Confirm HBC version of a baked bundle: `xxd <bundle> | head -1` → byte 8 is the HBC version (`62` hex = v98; the exact expected value for `260318099.0.1` is captured during Task 3.7).

---

## Phase 1 — Reorg (history-preserving relocation)

### Task 1.1: Move current content into `targets/rn-0.79/`

**Files:**
- Move (git mv): `patches/` → `targets/rn-0.79/patches/`; `scripts/` → `targets/rn-0.79/scripts/`; `sample79/` → `targets/rn-0.79/sample79/`; `README.md` → `targets/rn-0.79/README.md`; `CDP_ADAPTER_PLAN.md` → `docs/cdp-adapter.md` (this one lands in shared `docs/`, see Task 2.4).
- Keep at root for now: `CLAUDE.md` (edited in Task 2.5).

- [ ] **Step 1: Create target dir and move the 0.79 tree**

```bash
cd /home/tmikov/work/rn-0.79-hermes-v1
mkdir -p targets/rn-0.79
git mv patches targets/rn-0.79/patches
git mv scripts targets/rn-0.79/scripts
git mv sample79 targets/rn-0.79/sample79
git mv README.md targets/rn-0.79/README.md
```

- [ ] **Step 2: Verify the move preserved history**

Run: `git log --follow --oneline -- targets/rn-0.79/patches/01-jsi-vendoring.patch | head -3`
Expected: shows commits from before the move (e.g. the original patch-add commit), proving `--follow` works.

- [ ] **Step 3: Verify nothing stray left at root**

Run: `ls` then `git status --short`
Expected: root no longer has `patches/ scripts/ sample79/ README.md`; status shows the renames (`R`).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Reorg: move RN 0.79 port into targets/rn-0.79/"
```

### Task 1.2: Fix relative paths in the relocated 0.79 scripts

The two scripts compute `REPO_ROOT` as the script's grandparent and reference `sample79/` under it. After the move, `sample79/` is a sibling of `scripts/` inside `targets/rn-0.79/`, so `REPO_ROOT` must resolve to `targets/rn-0.79`, and the patch/vendor dirs are relative to that. Verify current logic and correct.

**Files:**
- Modify: `targets/rn-0.79/scripts/apply-patches.sh`
- Modify: `targets/rn-0.79/scripts/vendor-hermes-ios.sh`

- [ ] **Step 1: Re-read both scripts and confirm the path assumptions**

Run: `sed -n '10,20p' targets/rn-0.79/scripts/apply-patches.sh`
Observe: `REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)`, `PATCHDIR="$REPO_ROOT/patches"`, `RN_DIR="$REPO_ROOT/sample79/node_modules/react-native"`, `APP_DIR="$REPO_ROOT/sample79"`.
Because `patches/`, `sample79/` now sit beside `scripts/` inside `targets/rn-0.79/`, `SCRIPT_DIR/..` = `targets/rn-0.79` and all four paths are already correct. **No edit needed to apply-patches.sh** — confirm by inspection.

- [ ] **Step 2: Confirm vendor-hermes-ios.sh path assumption**

Run: `sed -n '9,16p' targets/rn-0.79/scripts/vendor-hermes-ios.sh`
Observe: `VENDOR_DIR="$REPO_ROOT/vendor/hermes-ios"`. This resolves to `targets/rn-0.79/vendor/hermes-ios` — correct and self-contained. No edit needed.

- [ ] **Step 3: Smoke-test apply-patches.sh path resolution without applying**

Run:
```bash
cd /home/tmikov/work/rn-0.79-hermes-v1
bash -c 'set -e; SCRIPT_DIR=targets/rn-0.79/scripts; REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd); echo "REPO_ROOT=$REPO_ROOT"; test -d "$REPO_ROOT/patches" && echo "patches OK"; test -f "$REPO_ROOT/patches/01-jsi-vendoring.patch" && echo "patch01 OK"'
```
Expected: `REPO_ROOT=/home/tmikov/work/rn-0.79-hermes-v1/targets/rn-0.79`, `patches OK`, `patch01 OK`.

- [ ] **Step 4: Fix README-internal relative references if any broke**

Run: `grep -nE '\.\./scripts|\.\./patches|sample79' targets/rn-0.79/README.md | head`
For each hit, confirm it still makes sense relative to `targets/rn-0.79/` (the README now lives inside the target, so `../scripts/apply-patches.sh` from `sample79` still resolves to `targets/rn-0.79/scripts/...`). Edit only genuinely broken paths. If none broke, note "no changes" and skip the commit-of-README part.

- [ ] **Step 5: Commit (only if edits were made)**

```bash
git add -A
git commit -m "Reorg: fix relative paths in relocated rn-0.79 scripts/README"
```
If Step 4 found nothing to change, skip this commit.

---

## Phase 2 — Universal top layer

### Task 2.1: Write `docs/hermes-v1-versioning.md` (the reusable explainer)

**Files:**
- Create: `docs/hermes-v1-versioning.md`

**Interfaces:**
- Produces: the canonical reference other docs link to for "what is V1, how is it versioned, which file does RN pin."

- [ ] **Step 1: Write the doc with these verified facts (all confirmed 2026-07-25)**

The doc MUST contain, as prose + a verification-commands appendix:

1. **What V1 is:** `facebook/hermes` `static_h` branch; `libhermes.so`→`libhermesvm.so`; Maven group `com.facebook.hermes` vs old `com.facebook.react`.
2. **Date versioning:** `YYMMDDxxx.0.N`; `YYMMDDxxx` = the date a `-stable` branch was cut from `static_h`. Evidence: `static_h`'s `npm/hermes-compiler/package.json` = `260318099.0.0`; `250829098.0.0-stable` merge-base = 2025-08-29; `260318099.0.0-stable` merge-base = 2026-03-18. Stable branches: `250829098` (2025-08-29), `260318099` (2026-03-18).
3. **How RN pins V1:** `packages/react-native/sdks/.hermesv1version`. Verified: RN 0.84 = `hermes-v250829098.0.9`, 0.85 = `hermes-v250829098.0.10`, 0.86 = `hermes-v250829098.0.14`.
4. **The trap:** the sibling `.hermesversion` (semver `hermes-v0.15.1`…`0.17.0`) is the **legacy classic-Hermes** pin — a different lineage (`release-vNN`, descends from the old `hermes-YYYY-MM-DD-RNvX.Y` tags) that diverged from `static_h` on 2022-08-19 (merge-base `7a93595`). It is NOT V1. Both live in `facebook/hermes`; only `static_h`/date is V1.
5. **Adoption timeline:** 0.82 opt-in (source), 0.83 default packaging, 0.84 first V1-default-with-prebuilts; 0.84–0.86 all on the `250829098` stable branch. Newest static_h stable not yet in any shipped RN = `260318099.0.1`.

Appendix — the exact `gh api` / `git compare` commands used to derive each fact (so a reader can re-verify against a future Hermes state). Include at minimum:
```bash
# date scheme is native to static_h
gh api "repos/facebook/hermes/contents/npm/hermes-compiler/package.json?ref=static_h" --jq '.content' | base64 -d | grep version
# RN's real V1 pin
gh api "repos/facebook/react-native/contents/packages/react-native/sdks/.hermesv1version?ref=v0.85.3" --jq '.content' | base64 -d
# the 2022 fork proving semver != V1
gh api "repos/facebook/hermes/compare/static_h...release-v0.17" --jq '.merge_base_commit.commit.committer.date'
```

- [ ] **Step 2: Verify the doc's claims still hold (re-run the appendix commands)**

Run the three commands above.
Expected: `260318099.0.0`; `hermes-v250829098.0.10`; a 2022 date. If any drifted, update the doc to match (the guide must reflect current reality).

- [ ] **Step 3: Commit**

```bash
git add docs/hermes-v1-versioning.md
git commit -m "docs: add Hermes V1 versioning + static_h fork explainer"
```

### Task 2.2: Write `docs/choosing-the-path.md` (decision tree)

**Files:**
- Create: `docs/choosing-the-path.md`

- [ ] **Step 1: Write the decision guide**

Content: a "what does your RN ship?" flow keyed on `.hermesv1version`, plus the effort table:

| RN version | Consumes | Effort | Worked example |
|---|---|---|---|
| ≥ 0.84 | V1 by default (`com.facebook.hermes`, `250829098.x`) | Easy — override artifact to a newer static_h stable; re-vendor JSI + matching hermesc only if required | `targets/rn-0.85` |
| 0.82–0.83 | V1 opt-in / source-build | Medium | documented, not built |
| ≤ 0.81 | old inline `libhermes.so` (`com.facebook.react`) | Hard — vendor static_h JSI, CMake `libhermes`→`hermesvm`, swap Maven group, CDP shim | `targets/rn-0.79` |

Include the one-liner to classify any checkout: `cat node_modules/react-native/sdks/.hermesv1version 2>/dev/null || echo "pre-V1 (no .hermesv1version) — hard path"`. Link to `hermes-v1-versioning.md` for the why.

- [ ] **Step 2: Commit**

```bash
git add docs/choosing-the-path.md
git commit -m "docs: add path-selection guide keyed on RN's Hermes consumption"
```

### Task 2.3: Write the universal root `README.md`

**Files:**
- Create: `README.md` (root; the old one now lives at `targets/rn-0.79/README.md`)

- [ ] **Step 1: Write a short landing README**

Sections: (1) one-paragraph what/why; (2) the mental model — "Hermes V1 = static_h date-line; RN pins it via `.hermesv1version`" linking `docs/hermes-v1-versioning.md`; (3) the path-selection table (same as Task 2.2, or a short version linking to it); (4) "Worked examples" listing `targets/rn-0.79/` (hard) and `targets/rn-0.85/` (easy) with one line each and a pointer that both run on `com.facebook.hermes:hermes-android:260318099.0.1`; (5) repo layout tree; (6) iOS status pointer to `docs/ios-handoff.md`. Keep it short — depth lives in `targets/*` and `docs/*`.

- [ ] **Step 2: Verify all internal links resolve**

Run: `grep -oE '\]\(([^)]+)\)' README.md | sed -E 's/\]\(|\)//g' | while read p; do [ -e "${p%%#*}" ] && echo "OK $p" || echo "MISSING $p"; done`
Expected: every link `OK` (note: `targets/rn-0.85/` may not exist yet — if so, leave that link and re-verify after Phase 3; record the known-pending link explicitly rather than silently).

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add universal landing README"
```

### Task 2.4: Relocate the CDP plan into `docs/`

**Files:**
- Move (git mv): `CDP_ADAPTER_PLAN.md` → `docs/cdp-adapter.md`

- [ ] **Step 1: Move it**

```bash
git mv CDP_ADAPTER_PLAN.md docs/cdp-adapter.md
```

- [ ] **Step 2: Fix inbound references**

Run: `grep -rn 'CDP_ADAPTER_PLAN' . --include='*.md' | grep -v docs/superpowers`
Edit each hit (notably `targets/rn-0.79/README.md`) to point at `docs/cdp-adapter.md` (adjust relative depth: from `targets/rn-0.79/README.md` the path is `../../docs/cdp-adapter.md`).

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "docs: move CDP adapter plan into docs/cdp-adapter.md"
```

### Task 2.5: Update `CLAUDE.md` to the multi-version framing

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Rewrite the Goal + add a repo-map section**

Change the Goal from "Get RN 0.79.5 … running on Hermes V1" to the multi-version framing: the repo teaches running current Hermes V1 on different RN versions, with `targets/rn-0.79` (hard) and `targets/rn-0.85` (easy) as worked examples, both on `260318099.0.1`. Add a short "Where things live" map (`targets/`, `docs/`). Keep the existing "Hermes V1 facts" and "Known risks" content but update the pinned version references from `250829098.0.13` to `260318099.0.1` and note `.hermesv1version` as RN's V1 pin. Preserve the RN-side surgery checklist (still accurate for the hard path) but scope it as "hard path (rn-0.79)".

- [ ] **Step 2: Verify no stale single-version claims remain**

Run: `grep -nE '0\.79\.5 .*Hermes V1|250829098\.0\.13' CLAUDE.md`
Expected: no lines implying the repo is only-0.79, and no lingering `250829098.0.13` except where intentionally describing history.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: reframe CLAUDE.md as multi-version; pin 260318099.0.1"
```

---

## Phase 3 — `targets/rn-0.85` Android port (easy path)

### Task 3.1: Scaffold the RN 0.85.3 host app

**Files:**
- Create: `targets/rn-0.85/sample85/` (fresh RN app), `targets/rn-0.85/README.md` (stub, filled in Task 3.8), `targets/rn-0.85/.gitignore`

- [ ] **Step 1: Create the app**

```bash
cd /home/tmikov/work/rn-0.79-hermes-v1/targets/rn-0.85
npx @react-native-community/cli@latest init sample85 --version 0.85.3 --skip-install --pm npm
```
(If the pinned CLI can't target 0.85.3, use `npx react-native@0.85.3 init sample85 --skip-install`. Record the exact command that worked in the target README.)

- [ ] **Step 2: Install deps and confirm the RN version + V1 pin**

```bash
cd sample85 && npm install
cat node_modules/react-native/sdks/.hermesv1version
```
Expected: `hermes-v250829098.0.10` (RN 0.85's shipped V1). This is the baseline we will override.

- [ ] **Step 3: Commit the baseline app (mirror how sample79 is committed — app source, not node_modules)**

Verify `node_modules` is gitignored:
Run: `grep -q node_modules targets/rn-0.85/sample85/.gitignore && echo IGNORED`
Expected: `IGNORED`.
```bash
cd /home/tmikov/work/rn-0.79-hermes-v1
git add targets/rn-0.85/sample85
git commit -m "rn-0.85: vendor pristine RN 0.85.3 baseline app"
```

### Task 3.2: Baseline build — prove the stock app builds/runs BEFORE the swap

**Files:** none (verification task)

- [ ] **Step 1: Build the stock Debug APK on shipped V1**

```bash
cd targets/rn-0.85/sample85/android && ./gradlew assembleDebug
```
Expected: BUILD SUCCESSFUL. (Sets a known-good baseline so a later failure is attributable to the swap.)

- [ ] **Step 2: Confirm the stock APK ships shipped-V1 `libhermesvm.so`**

Run: `unzip -l app/build/outputs/apk/debug/app-debug.apk | grep -E 'libhermes'`
Expected: `libhermesvm.so` present, no `libhermes.so` (RN 0.85 is already V1).

- [ ] **Step 3: Launch on the emulator and confirm it runs**

```bash
# emulator already available on this machine; start it, then:
adb install -r app/build/outputs/apk/debug/app-debug.apk
# start Metro in another shell: (cd targets/rn-0.85/sample85 && npm start)
adb shell monkey -p com.sample85 -c android.intent.category.LAUNCHER 1
adb logcat -d | grep -i 'ReactNativeJS\|hermes' | tail
```
Expected: app launches; JS runs. Note the package id (`com.sample85` or as generated) in the README.

- [ ] **Step 4: No commit** (verification only). Record baseline results in a scratch note for the README.

### Task 3.3: Discover the RN 0.85 Hermes-version override mechanism

**Files:** none (investigation; output feeds Task 3.4)

**Interfaces:**
- Produces: the exact override point — a Gradle property, a `.hermesv1version` edit, or a `settings.gradle` substitution — that swaps the V1 artifact to `260318099.0.1`.

- [ ] **Step 1: Find where the V1 artifact version is resolved**

```bash
cd targets/rn-0.85/sample85
grep -rn 'hermesv1version\|hermesVersion\|com.facebook.hermes\|hermes-android' node_modules/@react-native/gradle-plugin node_modules/react-native/ReactAndroid/gradle.properties 2>/dev/null | head -40
cat node_modules/react-native/ReactAndroid/gradle.properties | grep -i hermes
```
Record: does the plugin read `.hermesv1version`, or a gradle property (e.g. `react.internal.hermes*`)? Is the dependency declared as `com.facebook.hermes:hermes-android:<resolved>`?

- [ ] **Step 2: Determine the cleanest override**

Prefer, in order: (a) a documented Gradle property set in `android/gradle.properties`; (b) editing `node_modules/.../sdks/.hermesv1version` to `hermes-v260318099.0.1`; (c) a `settings.gradle` dependency-substitution (the mechanism `targets/rn-0.79` uses in patch 03). Whichever is used, it must be capturable as a patch/app-side edit so it survives `npm install` via an apply script (mirroring rn-0.79). Write the chosen mechanism into a scratch note.

- [ ] **Step 3: Sanity-check the artifact exists at the target version**

Run: `curl -sfI https://repo1.maven.org/maven2/com/facebook/hermes/hermes-android/260318099.0.1/hermes-android-260318099.0.1.pom | head -1`
Expected: `HTTP/... 200`.

- [ ] **Step 4: No commit** (investigation only).

### Task 3.4: Apply the Hermes V1 `260318099.0.1` override

**Files:**
- Create: `targets/rn-0.85/patches/01-hermes-v1-bump.patch` (and/or an app-side edit under `sample85/android/`) — exact shape decided in Task 3.3.
- Create: `targets/rn-0.85/scripts/apply-patches.sh` (adapted from the rn-0.79 script for the 0.85 patch set)

- [ ] **Step 1: Implement the override** using the mechanism chosen in Task 3.3, pointing at `com.facebook.hermes:hermes-android:260318099.0.1`.

- [ ] **Step 2: Capture it as a patch + apply script**

Regenerate the patch from the working-tree edit (mirror `targets/rn-0.79/patches/REGENERATE.md` conventions). Write `targets/rn-0.85/scripts/apply-patches.sh` to apply the 0.85 patch set idempotently (marker-file gated, same pattern as rn-0.79).

- [ ] **Step 3: Verify the override resolves**

```bash
cd targets/rn-0.85/sample85/android && ./gradlew :app:dependencies --configuration releaseRuntimeClasspath | grep hermes-android
```
Expected: `com.facebook.hermes:hermes-android:260318099.0.1` (not `250829098.0.10`).

- [ ] **Step 4: Commit**

```bash
cd /home/tmikov/work/rn-0.79-hermes-v1
git add targets/rn-0.85/patches targets/rn-0.85/scripts
git commit -m "rn-0.85: override Hermes V1 to 260318099.0.1"
```

### Task 3.5: Resolve JSI / ABI drift (conditional)

**Files:**
- Possibly Create: `targets/rn-0.85/patches/02-jsi-vendoring.patch` (only if needed)

- [ ] **Step 1: Attempt a Debug build on the bumped artifact**

```bash
cd targets/rn-0.85/sample85/android && ./gradlew assembleDebug 2>&1 | tee /tmp/rn085-debug-build.log
```

- [ ] **Step 2: Branch on the result**

- If **BUILD SUCCESSFUL**: no JSI drift — skip to Task 3.6. Record "no JSI re-vendor needed" in the README (a key finding: newer static_h stable was drop-in for RN 0.85).
- If it **fails on JSI/ABI mismatch** (missing `jsi::ICast`/`jsi::UUID`, header mismatch, symbol errors referencing `hermes-interfaces.h`): re-vendor JSI from tag `hermes-v260318099.0.1` into `node_modules/react-native/ReactCommon/jsi/jsi/`, exactly as `targets/rn-0.79/patches/01-jsi-vendoring.patch` does but for the 0.85 tree. Use the `REGENERATE.md` download loop with `TAG=hermes-v260318099.0.1`. Capture as `patches/02-jsi-vendoring.patch`.

- [ ] **Step 3: Re-build until Debug succeeds**

Run: `./gradlew assembleDebug`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 4: Commit (only if a JSI patch was produced)**

```bash
git add targets/rn-0.85/patches
git commit -m "rn-0.85: re-vendor static_h JSI for 260318099.0.1"
```

### Task 3.6: Debug run on Hermes V1 `260318099.0.1`

**Files:** none (verification)

- [ ] **Step 1: Confirm the APK carries V1**

Run: `unzip -l targets/rn-0.85/sample85/android/app/build/outputs/apk/debug/app-debug.apk | grep -E 'libhermes'`
Expected: `libhermesvm.so`, no `libhermes.so`.

- [ ] **Step 2: Install, run against Metro, confirm the engine**

```bash
adb install -r targets/rn-0.85/sample85/android/app/build/outputs/apk/debug/app-debug.apk
# Metro running in another shell
adb shell monkey -p com.sample85 -c android.intent.category.LAUNCHER 1
adb logcat -d | grep -i 'ReactNativeJS\|hermes' | tail
```
Expected: `Running "sample85" with {...}`; app renders. If `App.tsx` doesn't already show the engine version, add a small line rendering the Hermes version (mirror what sample79 does) so V1 is visible on-screen.

- [ ] **Step 3: Commit** any `App.tsx` engine-display tweak.

```bash
git add targets/rn-0.85/sample85/App.tsx
git commit -m "rn-0.85: surface Hermes engine version on the welcome screen"
```

### Task 3.7: Release build on Hermes V1 `260318099.0.1`

**Files:**
- Modify: `targets/rn-0.85/sample85/android/app/build.gradle` (point `react.hermesCommand` at V1 hermesc, if RN 0.85 doesn't already resolve it) — decided during this task.
- Possibly Create: `targets/rn-0.85/patches/03-release-hermesc.patch`

- [ ] **Step 1: Provide V1 hermesc at the matching version**

```bash
cd targets/rn-0.85/sample85
npm install --save-dev hermes-compiler@260318099.0.1
node -e "console.log(require('hermes-compiler/package.json').version)"
```
Expected: `260318099.0.1`. (Mirrors the rn-0.79 release approach in README §7a.) If RN 0.85's gradle plugin already sources a bundled V1 hermesc, verify its HBC output version instead and only override if it mismatches.

- [ ] **Step 2: Build the Release APK**

```bash
cd android && ./gradlew assembleRelease 2>&1 | tee /tmp/rn085-release-build.log
```
Expected: BUILD SUCCESSFUL, with an HBC bundle baked in (no Metro dependency).

- [ ] **Step 3: Verify baked bundle + HBC version**

```bash
unzip -l app/build/outputs/apk/release/app-release.apk | grep -E 'index.android.bundle|libhermes'
unzip -p app/build/outputs/apk/release/app-release.apk assets/index.android.bundle | xxd | head -1
```
Expected: `libhermesvm.so` present; `index.android.bundle` present; first bytes are HBC magic. Record byte 8 (the HBC version the `260318099.0.1` compiler emits) in the README as the expected value.

- [ ] **Step 4: Install and run the Release APK (no Metro)**

```bash
adb install -r app/build/outputs/apk/release/app-release.apk
adb shell monkey -p com.sample85 -c android.intent.category.LAUNCHER 1
adb logcat -d | grep -i 'ReactNativeJS\|hermes' | tail
```
Expected: app runs with no Metro server running.

- [ ] **Step 5: Commit**

```bash
cd /home/tmikov/work/rn-0.79-hermes-v1
git add targets/rn-0.85/sample85/package.json targets/rn-0.85/sample85/package-lock.json targets/rn-0.85/sample85/android/app/build.gradle targets/rn-0.85/patches 2>/dev/null
git commit -m "rn-0.85: release build on Hermes V1 260318099.0.1 (V1 hermesc)"
```

### Task 3.8: Write `targets/rn-0.85/README.md`

**Files:**
- Modify: `targets/rn-0.85/README.md`

- [ ] **Step 1: Document the easy path end-to-end**

Content: prerequisites (reuse the root/0.79 Android env); the exact `init` command used; the override mechanism (from Task 3.3/3.4) and why it's the whole job on an already-V1 RN; whether JSI re-vendor was needed (Task 3.5 finding — the headline result); Debug build/install/run commands; Release build + V1 hermesc + the observed HBC version; the verification one-liners (`unzip -l … | grep libhermes`). Explicitly contrast with `targets/rn-0.79` ("hard path") and link `../../docs/hermes-v1-versioning.md`. Add an iOS pointer to `../../docs/ios-handoff.md`.

- [ ] **Step 2: Verify internal links resolve**

Run: `grep -oE '\]\(([^)]+)\)' targets/rn-0.85/README.md | sed -E 's/\]\(|\)//g' | while read p; do case "$p" in http*|\#*) continue;; esac; ( cd targets/rn-0.85 && [ -e "${p%%#*}" ] ) && echo "OK $p" || echo "MISSING $p"; done`
Expected: all `OK`.

- [ ] **Step 3: Commit**

```bash
git add targets/rn-0.85/README.md
git commit -m "rn-0.85: document the easy-path Hermes V1 bump"
```

---

## Phase 4 — Bump `targets/rn-0.79` to Hermes V1 `260318099.0.1`

### Task 4.1: Update the version strings in the 0.79 patch set

**Files:**
- Modify: `targets/rn-0.79/patches/02-rn-surgery.patch` (line with `com.facebook.hermes:hermes-android:250829098.0.13`)
- Modify: `targets/rn-0.79/patches/03-app-side.patch` (the substitution line)
- Modify: `targets/rn-0.79/patches/REGENERATE.md` (doc references + `TAG=`)
- (iOS patch 05 is bumped in Phase 5 / handoff, not here)

- [ ] **Step 1: Bump the Android-side version strings**

```bash
cd /home/tmikov/work/rn-0.79-hermes-v1/targets/rn-0.79
sed -i 's/hermes-android:250829098\.0\.13/hermes-android:260318099.0.1/' patches/02-rn-surgery.patch patches/03-app-side.patch
sed -i 's/250829098\.0\.13/260318099.0.1/g; s/hermes-v250829098\.0\.13/hermes-v260318099.0.1/g' patches/REGENERATE.md
```

- [ ] **Step 2: Verify no Android-side `250829098.0.13` remains (iOS patch 05 intentionally deferred)**

Run: `grep -rn '250829098' patches/02-rn-surgery.patch patches/03-app-side.patch patches/REGENERATE.md`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
cd /home/tmikov/work/rn-0.79-hermes-v1
git add targets/rn-0.79/patches
git commit -m "rn-0.79: bump Android Hermes V1 pin to 260318099.0.1"
```

### Task 4.2: Re-vendor JSI for `260318099.0.1` if it drifted (patch 01)

**Files:**
- Possibly Modify: `targets/rn-0.79/patches/01-jsi-vendoring.patch`

- [ ] **Step 1: Diff the JSI that patch 01 vendors vs the target tag**

```bash
cd /tmp && rm -rf jsi-085 jsi-013 && mkdir jsi-085 jsi-013
for f in jsi.h jsi.cpp jsi-inl.h instrumentation.h decorator.h threadsafe.h JSIDynamic.h JSIDynamic.cpp hermes-interfaces.h; do
  curl -sfLo "jsi-085/$f" "https://raw.githubusercontent.com/facebook/hermes/hermes-v260318099.0.1/API/jsi/jsi/$f" || echo "absent: $f"
done
# Extract the versions patch 01 currently ships and compare (patch 01 embeds full file bodies)
```
Compare the downloaded `hermes-v260318099.0.1` JSI against the bodies embedded in `patches/01-jsi-vendoring.patch`. If identical, no change.

- [ ] **Step 2: Branch on drift**

- If **no drift**: record "JSI unchanged between 250829098.0.13 and 260318099.0.1" and skip to Task 4.3.
- If **drift**: regenerate `patches/01-jsi-vendoring.patch` from tag `hermes-v260318099.0.1` using the `REGENERATE.md` procedure (now with the bumped `TAG`).

- [ ] **Step 3: Commit (only if regenerated)**

```bash
git add targets/rn-0.79/patches/01-jsi-vendoring.patch
git commit -m "rn-0.79: re-vendor static_h JSI at 260318099.0.1"
```

### Task 4.3: Re-check the CDP shim (patch 04) against `260318099`

**Files:**
- Possibly Modify: `targets/rn-0.79/patches/04-cdp-adapter.patch`

- [ ] **Step 1: Diff the V1 CDP surface the shim targets**

```bash
for f in $(gh api "repos/facebook/hermes/contents/API/hermes/cdp?ref=hermes-v250829098.0.13" --jq '.[].name'); do
  a=$(gh api "repos/facebook/hermes/contents/API/hermes/cdp/$f?ref=hermes-v250829098.0.13" --jq '.sha' 2>/dev/null)
  b=$(gh api "repos/facebook/hermes/contents/API/hermes/cdp/$f?ref=hermes-v260318099.0.1" --jq '.sha' 2>/dev/null)
  [ "$a" = "$b" ] && echo "same  $f" || echo "DIFF  $f"
done
```
Expected mostly `same`. Any `DIFF` on a header the shim (`CDPHandler.cpp`) references means the shim may need adjustment.

- [ ] **Step 2: If DIFFs touch the shim's surface, rebuild the Debug APK and let the compiler tell you**

The real gate is Task 4.4's build. If Step 1 shows no relevant diffs, note "CDP surface stable" and proceed.

- [ ] **Step 3: Commit** any shim edit (only if made).

### Task 4.4: Re-validate rn-0.79 Android Debug + Release on `260318099.0.1`

**Files:** none (verification) — but this is the gate that confirms Phase 4.

- [ ] **Step 1: Fresh apply of the bumped patch set**

```bash
cd targets/rn-0.79/sample79
rm -f node_modules/react-native/.hermes-v1-patches-applied 2>/dev/null || true
npm install
../scripts/apply-patches.sh
```
Expected: all patches apply cleanly (no `.rej`). If a hunk fails, the version-string edits or a JSI regen were incomplete — fix before proceeding.

- [ ] **Step 2: Debug build + verify V1**

```bash
cd android && ./gradlew assembleDebug
unzip -l app/build/outputs/apk/debug/app-debug.apk | grep -E 'libhermes'
```
Expected: BUILD SUCCESSFUL; `libhermesvm.so`, no `libhermes.so`.

- [ ] **Step 3: Run on emulator**

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
# Metro in another shell
adb shell monkey -p com.sample79 -c android.intent.category.LAUNCHER 1
adb logcat -d | grep -i 'ReactNativeJS\|hermes' | tail
```
Expected: `Running "sample79" with {...}`; engine version now reads `260318099.0.1`.

- [ ] **Step 4: Release build + verify HBC**

```bash
cd targets/rn-0.79/sample79
npm install --save-dev hermes-compiler@260318099.0.1   # bump release hermesc to match
cd android && ./gradlew assembleRelease
unzip -p app/build/outputs/apk/release/app-release.apk assets/index.android.bundle | xxd | head -1
```
Expected: BUILD SUCCESSFUL; HBC magic present. Compare byte 8 to the value observed for rn-0.85 Task 3.7 — they should match (same compiler version).

- [ ] **Step 5: Commit the release hermesc bump**

```bash
cd /home/tmikov/work/rn-0.79-hermes-v1
git add targets/rn-0.79/sample79/package.json targets/rn-0.79/sample79/package-lock.json
git commit -m "rn-0.79: bump release hermesc to 260318099.0.1; Android re-validated"
```

### Task 4.5: Update `targets/rn-0.79/README.md` for the new version

**Files:**
- Modify: `targets/rn-0.79/README.md`

- [ ] **Step 1: Update version references + Status**

Replace `250829098.0.13` references with `260318099.0.1` in the Android sections. Update the Status block: Android re-validated on `260318099.0.1`; iOS re-validation pending (link `../../docs/ios-handoff.md`). If Task 4.2/4.3 found drift, add a short note documenting what the newer static_h stable required (valuable data point).

- [ ] **Step 2: Verify no stale Android-side version refs**

Run: `grep -nE '250829098\.0\.13' targets/rn-0.79/README.md`
Expected: only iOS-section references remain (those are addressed in the handoff); Android sections show `260318099.0.1`.

- [ ] **Step 3: Commit**

```bash
git add targets/rn-0.79/README.md
git commit -m "rn-0.79: docs updated for 260318099.0.1 (Android)"
```

---

## Phase 5 — iOS handoff doc

### Task 5.1: Write `docs/ios-handoff.md`

**Files:**
- Create: `docs/ios-handoff.md`

- [ ] **Step 1: Write the Mac-side runbook**

Two workstreams, both requiring macOS/Xcode (cannot be done on the Linux dev box):

1. **rn-0.79 iOS re-validation at `260318099.0.1`:** bump the iOS pin in `targets/rn-0.79/patches/05-ios.patch` (`version = "250829098.0.13"` → `"260318099.0.1"`, and the vendor URL) and `targets/rn-0.79/scripts/vendor-hermes-ios.sh` (`VERSION="250829098.0.13"` → `"260318099.0.1"`); re-vendor the `hermes-ios` tarballs; `pod install`; build+run Debug and Release in the Simulator; confirm `hermesvm.framework` and HBC v-match. Reference README §§8–9.
2. **rn-0.85 iOS bring-up:** apply the 0.85 override to the iOS side (Podfile / `hermes-ios` version), `pod install` with `260318099.0.1`, build+run Debug and Release. Note that RN 0.85 already consumes `hermes-ios` V1, so this is a version override, not a framework rename.

Include the exact strings to change (cite the patch/script line numbers from `targets/rn-0.79/`), the expected artifacts (`hermesvm.framework`, `@rpath/hermesvm.framework/hermesvm`), and the HBC-byte check. State clearly which steps were NOT run here and must be validated on the Mac.

- [ ] **Step 2: Cross-link**

Ensure root `README.md`, `targets/rn-0.79/README.md`, and `targets/rn-0.85/README.md` all point to `docs/ios-handoff.md` for iOS status.
Run: `grep -rln 'ios-handoff' README.md targets/*/README.md`
Expected: all three listed.

- [ ] **Step 3: Commit**

```bash
git add docs/ios-handoff.md README.md targets/rn-0.79/README.md targets/rn-0.85/README.md
git commit -m "docs: add iOS handoff runbook (rn-0.79 re-validation + rn-0.85 bring-up)"
```

---

## Phase 6 — Final integration check

### Task 6.1: Whole-repo consistency pass

**Files:** none (verification)

- [ ] **Step 1: No stray root artifacts; structure matches the spec tree**

Run: `ls; echo '---'; ls targets docs`
Expected: root has `README.md CLAUDE.md docs/ targets/` (+ `.git*`); `targets/` has `rn-0.79 rn-0.85`; `docs/` has `hermes-v1-versioning.md choosing-the-path.md cdp-adapter.md ios-handoff.md` (+ `superpowers/`).

- [ ] **Step 2: Every Android-side reference to the Hermes version is the target version**

Run: `grep -rnE '250829098' --include='*.md' --include='*.patch' --include='*.sh' targets docs README.md CLAUDE.md | grep -v ios | grep -v hermes-v250829098.0.10`
Expected: only intentional historical/iOS mentions remain; no stray Android pins.

- [ ] **Step 3: All markdown internal links resolve**

Run:
```bash
for md in README.md CLAUDE.md docs/*.md targets/*/README.md; do
  grep -oE '\]\(([^)]+)\)' "$md" | sed -E 's/\]\(|\)//g' | while read p; do
    case "$p" in http*|\#*) continue;; esac
    d=$(dirname "$md"); [ -e "$d/${p%%#*}" ] || echo "MISSING in $md -> $p"
  done
done
```
Expected: no `MISSING` output.

- [ ] **Step 4: Final commit / branch ready for review**

```bash
git add -A && git commit -m "chore: whole-repo consistency pass" --allow-empty
git log --oneline origin/master..HEAD
```
Expected: the full task series of commits, ready to open a PR.

---

## Notes for the executor

- **Discovery-gated tasks (3.3, 3.5, 4.2, 4.3)** legitimately can't have their exact diffs pre-written — the newer static_h stable's drift vs RN's shipped JSI/CDP is unknown until built. Each such task has a concrete investigation command, an explicit branch on the result, and a build gate that objectively decides. Do the investigation, then implement what it shows — do not guess.
- **The headline result of Phase 3** is whether the easy path was truly a version override (no JSI re-vendor). Record that finding prominently — it's the guide's core claim.
- **Android toolchain** is present on this machine (confirmed). If a build fails on missing NDK/SDK bits, that's an environment gap to fix, not a code defect — surface it rather than working around it.
- **iOS is never built here.** Any iOS step lands in `docs/ios-handoff.md` only.
