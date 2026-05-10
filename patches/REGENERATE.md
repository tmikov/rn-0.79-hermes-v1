# Regenerating the patches

There are six patches:

- `01-jsi-vendoring.patch` and `02-rn-surgery.patch` describe the diff
  between **pristine RN 0.79.5 from npm** and our **modified
  `node_modules/react-native/`** in `sample79/`. Patch 02 is
  Android-build-system specific (Gradle/CMake). Regenerate when:
  - you bump the Hermes V1 AAR version (must re-vendor JSI from the
    matching `hermes-v<aar-version>` tag — see "JSI tag pinning" below);
  - you re-vendor JSI for any other reason;
  - you edit anything in the modified `node_modules/react-native/` tree
    that's covered by these patches.
- `03-app-side.patch` describes the diff between the **pristine
  `sample79/`** (as committed in this repo) and the modified
  `android/settings.gradle` + `android/app/build.gradle`. See
  "Regenerating patch 03" below.
- `04-cdp-adapter.patch` is the CDP-adapter shim that restores the
  legacy `hermes/inspector/*` API on top of V1's `hermes/cdp/*` API
  (see `CDP_ADAPTER_PLAN.md` at the repo root). It **layers on top
  of** patches 01 and 02 — its baseline for diffing is
  `(pristine RN) + patch 01 + patch 02 applied`, so it can be applied
  with `patch -p1` cleanly after 01 and 02 (and undoes some of patch
  02's `HERMES_ENABLE_DEBUGGER` removals where the shim now provides
  a working back-end). See "Regenerating patch 04" below.
- `05-ios.patch` is the iOS-build-system analog of patch 02:
  CocoaPods/Podspec edits that wire RN 0.79's iOS build to consume
  V1 from the `com.facebook.hermes:hermes-ios` Maven artifact, glob
  the patch-04 shim files into `React-hermes`, and include a workaround
  for fmt 11.0.2 + clang 19+ (Xcode 26+). Diffs straight against
  pristine RN 0.79.5 — no layering. Required only for iOS builds.
  See "Regenerating patch 05" below.
- `06-ios-app-side.patch` is the iOS analog of patch 03: app-side
  CocoaPods Podfile edits in `sample79/ios/`. Adds a `post_install`
  hook that re-applies a one-line patch to `Pods/fmt/include/fmt/base.h`
  after each `pod install` (CocoaPods makes pod files read-only and
  re-extracts on install, so the in-tree fmt fix from patch 05 alone
  isn't enough). Required only for iOS builds. See "Regenerating
  patch 06" below.

## JSI tag pinning

JSI is **source-stable, not ABI-stable**. The vendored JSI files must
match the snapshot the `libhermesvm.so` in the V1 AAR was built against.
That snapshot is captured by the git tag `hermes-v<aar-version>` (e.g.
the AAR `com.facebook.hermes:hermes-android:250829098.0.13` corresponds
to tag `hermes-v250829098.0.13`).

Do **not** vendor from `static_h` HEAD — even an unrelated commit between
the AAR's snapshot and HEAD that changes inline JSI functions, vtable
layouts, or member offsets would silently produce UB at runtime.

Re-vendor:

```bash
TAG=hermes-v250829098.0.13            # match the V1 AAR Maven version
JSI_DST=/path/to/sample79/node_modules/react-native/ReactCommon/jsi/jsi
files="CMakeLists.txt JSIDynamic.cpp JSIDynamic.h decorator.h \
       hermes-interfaces.h instrumentation.h jsi-inl.h jsi.cpp jsi.h \
       jsilib-posix.cpp jsilib-windows.cpp jsilib.h threadsafe.h"
for f in $files; do
  curl -sfL -o "$JSI_DST/$f" \
    "https://raw.githubusercontent.com/facebook/hermes/$TAG/API/jsi/jsi/$f"
done
```

Then regenerate the patches via the steps below.

## Setup

Get a pristine copy of RN 0.79.5:

```bash
mkdir -p /tmp/pristine-rn79 && cd /tmp/pristine-rn79
npm pack react-native@0.79.5
rm -rf package                        # remove any stale extraction
tar xf react-native-0.79.5.tgz        # creates ./package/
```

(`rm -rf package` matters: `tar` from npm pack doesn't always overwrite
existing dirs cleanly, and a partial extraction will give you missing
files and a broken round-trip diff.)

## Generate

```bash
PRISTINE="/tmp/pristine-rn79/package"
MODIFIED="/path/to/sample79/node_modules/react-native"
PATCHDIR="/path/to/this/patches"

JSI_FILES="CMakeLists.txt JSIDynamic.cpp decorator.h hermes-interfaces.h \
           instrumentation.h jsi-inl.h jsi.cpp jsi.h"

SURGERY_FILES="
settings.gradle.kts
ReactAndroid/build.gradle.kts
ReactAndroid/src/main/jni/CMakeLists.txt
ReactAndroid/src/main/jni/react/hermes/instrumentation/CMakeLists.txt
ReactAndroid/src/main/jni/react/hermes/instrumentation/HermesSamplingProfiler.cpp
ReactAndroid/src/main/jni/react/hermes/reactexecutor/CMakeLists.txt
ReactAndroid/src/main/jni/react/hermes/reactexecutor/OnLoad.cpp
ReactAndroid/src/main/jni/react/hermes/tooling/CMakeLists.txt
ReactAndroid/src/main/jni/react/runtime/hermes/jni/CMakeLists.txt
ReactAndroid/src/main/jni/react/runtime/jni/CMakeLists.txt
ReactCommon/hermes/executor/CMakeLists.txt
ReactCommon/hermes/executor/HermesExecutorFactory.cpp
ReactCommon/hermes/inspector-modern/CMakeLists.txt
ReactCommon/hermes/inspector-modern/chrome/HermesRuntimeSamplingProfileSerializer.cpp
ReactCommon/jsc/CMakeLists.txt
ReactCommon/react/runtime/CMakeLists.txt
ReactCommon/react/runtime/hermes/CMakeLists.txt
"

emit() {
  local rel="$1"
  local old="$PRISTINE/$rel"
  [ -f "$old" ] || old="/dev/null"
  diff -uN --label "a/$rel" --label "b/$rel" "$old" "$MODIFIED/$rel"
}

{ for f in $JSI_FILES; do emit "ReactCommon/jsi/jsi/$f"; done; } \
  > "$PATCHDIR/01-jsi-vendoring.patch"

{ for rel in $SURGERY_FILES; do emit "$rel"; done; } \
  > "$PATCHDIR/02-rn-surgery.patch"
```

`--label a/<rel>` / `--label b/<rel>` is what makes `patch -p1` work on the
output (otherwise the patch headers carry absolute paths).

## Verify round-trip

Applying all RN-side patches to a pristine copy must reproduce the
modified tree exactly:

```bash
TMP=$(mktemp -d) && cp -R "$PRISTINE" "$TMP/rn"
( cd "$TMP/rn" && patch -p1 -i "$PATCHDIR/01-jsi-vendoring.patch" \
                && patch -p1 -i "$PATCHDIR/02-rn-surgery.patch" \
                && patch -p1 -i "$PATCHDIR/04-cdp-adapter.patch" \
                && patch -p1 -i "$PATCHDIR/05-ios.patch" )
diff -ruN -x .gradle -x sdks -x .cxx -x build -x node_modules \
  "$TMP/rn" "$MODIFIED" | wc -l    # must be 0
rm -rf "$TMP"
```

## Regenerating patch 04

Patch 04 layers on top of 01 + 02. Build a temporary post-(01,02)
baseline, then diff each shim file against it:

```bash
PRISTINE="/tmp/pristine-rn79/package"
MODIFIED="/path/to/sample79/node_modules/react-native"
PATCHDIR="/path/to/this/patches"

CDP_FILES="
ReactCommon/hermes/inspector/CMakeLists.txt
ReactCommon/hermes/inspector/RuntimeAdapter.h
ReactCommon/hermes/inspector/RuntimeAdapter.cpp
ReactCommon/hermes/inspector/chrome/CDPHandler.h
ReactCommon/hermes/inspector/chrome/CDPHandler.cpp
ReactCommon/hermes/executor/CMakeLists.txt
ReactCommon/hermes/executor/HermesExecutorFactory.cpp
ReactCommon/hermes/inspector-modern/CMakeLists.txt
ReactCommon/hermes/inspector-modern/chrome/HermesRuntimeTargetDelegate.cpp
ReactCommon/react/runtime/CMakeLists.txt
ReactCommon/react/runtime/hermes/CMakeLists.txt
ReactCommon/react/runtime/hermes/HermesInstance.cpp
ReactAndroid/src/main/jni/CMakeLists.txt
ReactAndroid/src/main/jni/react/hermes/reactexecutor/CMakeLists.txt
ReactAndroid/src/main/jni/react/hermes/tooling/CMakeLists.txt
ReactAndroid/src/main/jni/react/runtime/hermes/jni/CMakeLists.txt
ReactAndroid/src/main/jni/react/runtime/jni/CMakeLists.txt
"

BASE=$(mktemp -d)
trap 'rm -rf "$BASE"' EXIT
cp -R "$PRISTINE/." "$BASE/"
( cd "$BASE" && patch -p1 --quiet -i "$PATCHDIR/01-jsi-vendoring.patch" \
                && patch -p1 --quiet -i "$PATCHDIR/02-rn-surgery.patch" )

emit() {
  local rel="$1"
  local old="$BASE/$rel"
  [ -f "$old" ] || old="/dev/null"
  diff -uN --label "a/$rel" --label "b/$rel" "$old" "$MODIFIED/$rel" || true
}

> "$PATCHDIR/04-cdp-adapter.patch"
for rel in $CDP_FILES; do
  emit "$rel" >> "$PATCHDIR/04-cdp-adapter.patch"
done
```

`emit() ... || true` matters: `diff` exits 1 when files differ, which
is the normal case here, so we suppress that under `set -e`.

## Regenerating patch 03

Patch 03 covers `sample79/android/settings.gradle` and
`sample79/android/app/build.gradle`. The pristine reference is the
committed copy of those files in this repo's `sample79/` subtree, so a
plain `git diff` from the parent repo's root produces it directly:

```bash
cd /path/to/directtv
git diff -- sample79/android/settings.gradle \
            sample79/android/app/build.gradle \
  | sed 's|sample79/||g' \
  > patches/03-app-side.patch
```

The `sed` strips the `sample79/` prefix from the diff headers so the
patch applies with `patch -p1` from inside `sample79/` (matching how the
README §6 Option A invokes it).

## Regenerating patch 05

Patch 05 covers four files in `node_modules/react-native/`. Same pattern
as patches 01/02 — diff against pristine RN 0.79.5:

```bash
PRISTINE="/tmp/pristine-rn79/package"
MODIFIED="/path/to/sample79/node_modules/react-native"
PATCHDIR="/path/to/this/patches"

IOS_FILES="
sdks/hermes-engine/hermes-engine.podspec
sdks/hermes-engine/hermes-utils.rb
ReactCommon/hermes/React-hermes.podspec
third-party-podspecs/fmt.podspec
"

emit() {
  local rel="$1"
  local old="$PRISTINE/$rel"
  [ -f "$old" ] || old="/dev/null"
  diff -uN --label "a/$rel" --label "b/$rel" "$old" "$MODIFIED/$rel" || true
}

> "$PATCHDIR/05-ios.patch"
for rel in $IOS_FILES; do
  emit "$rel" >> "$PATCHDIR/05-ios.patch"
done
```

Patch 05 does not layer on patches 02 or 04 — it touches an entirely
disjoint set of files (CocoaPods podspecs vs Gradle/CMake), so it
diffs straight against pristine.

## Regenerating patch 06

Patch 06 covers `sample79/ios/Podfile`. Same pattern as patch 03:

```bash
cd /path/to/directtv
git diff -- sample79/ios/Podfile \
  | sed 's|sample79/||g' \
  > patches/06-ios-app-side.patch
```

(Or `sl diff sample79/ios/Podfile --reason "..."` if you're on Sapling.)

## What's *not* in the patches

- `sample79/package.json` / `package-lock.json` — `hermes-compiler`
  devDependency for the V1 host hermesc on Android (covered in README
  §7a). It's an `npm install` step, not a source edit; patches don't
  compose well with npm lockfiles. iOS doesn't need this — the V1 iOS
  tarball ships its own host `hermesc` at `destroot/bin/hermesc` and
  RN's `react-native-xcode.sh` finds it there by default.
- The `sdkmanager` stub at `$ANDROID_HOME/cmdline-tools/latest/bin/`
  (covered in README §5b). Filesystem-level, not in any source tree.
- The vendored V1 iOS tarballs under `vendor/hermes-ios/`. Binary
  blobs, not source edits; download with `curl` (URLs in
  `IOS_V1_PLAN.md`). Selected at `pod install` time via
  `HERMES_ENGINE_TARBALL_PATH=...`.
- Incidental edits to `sample79/ios/sample79.xcodeproj/project.pbxproj`
  that CocoaPods makes on `pod install` (privacy manifest aggregation,
  removing stale test target placeholders). These happen on any RN
  0.79 + Xcode 26 + `pod install`, independent of our V1 work.
