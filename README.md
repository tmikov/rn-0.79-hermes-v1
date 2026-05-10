# React Native Hermes-swap experiment

RN 0.79.5 with stock Hermes swapped out for **Hermes V1** (`static_h`),
running on Android and the iOS Simulator. The baseline app (`sample79/`)
and the patches that do the swap are committed in this repo — see
**Quick start** below.

The rest of the README (§§1–9) is the linear diary of how we got here:
bootstrapping the RN app, building it from prebuilts, building Hermes
from source, the V1 swap on Android (§§6–7) and the V1 swap on iOS
(§§8–9). Useful as reference; not needed for the happy path.

**Apply all six patches** — the result builds and runs on both
platforms. The patches split by application directory:

- **RN-side** (apply from `sample79/node_modules/react-native/`):
  `01-jsi-vendoring`, `02-rn-surgery`, `04-cdp-adapter`, `05-ios`.
  Order matters: patch 04 layers on 01 + 02, so apply 02 before 04.
- **App-side** (apply from `sample79/`): `03-app-side` (Android-side
  Gradle), `06-ios-app-side` (iOS-side Podfile).

You don't need to opt in or out by platform — Android-only edits are
inert when building iOS, and vice versa. Apply all six, then build
whichever platform you want.

## Prerequisites

Common to both platforms:

- Node.js (with `npx`)

### Android prerequisites

- Android Studio (for the SDK + emulator)
- An AVD created in Android Studio (we use `Medium_Phone_API_36`)
- **JDK 17** — RN 0.79's Gradle build trips `-Werror` on JDK 21's
  source/target=8 deprecation warnings, so we install Temurin 17:

  ```bash
  brew install --cask temurin@17
  ```

Common environment for all later Android steps:

```bash
export JAVA_HOME="/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$PATH"
```

One more one-time setup: a no-op `sdkmanager` stub. RN 0.79's
`hermes-engine` Gradle module wires up a call to `$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager`
at *configuration* time even though it only *runs* it when CMake is
missing. Configuration fails if the binary isn't there. (See §5b for
context — a real `cmdline-tools` install also works.)

```bash
mkdir -p "$ANDROID_HOME/cmdline-tools/latest/bin"
printf '#!/bin/sh\nexit 0\n' > "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
chmod +x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
```

### iOS prerequisites

- macOS (Apple Silicon validated; Intel should work).
- **Xcode 26.x.** Earlier versions probably work for the V1 swap but
  haven't been tested. Xcode 26 needs the fmt workaround (see §8 /
  patches 05 + 06).
- **iOS Simulator runtime** for the SDK Xcode shipped (Xcode 26.4
  needs iOS 26.4):

  ```bash
  xcodebuild -downloadPlatform iOS
  ```

  (Multi-GB; one-time.)
- **CocoaPods via Bundler against system Ruby.** macOS ships Ruby 2.6.10
  at `/usr/bin/ruby`, and `sample79/Gemfile` is already pinned to
  `ruby ">= 2.6.10"` with CocoaPods version constraints that work on it.
  Avoids rbenv/rvm/Homebrew-Ruby pain. See §8a.
- **Pre-vendored V1 iOS tarballs** under `vendor/hermes-ios/`. Not
  committed (49 MB of binary blobs); fetch with the curl commands in §8b.

## Quick start

The fast path from a fresh clone to a Hermes V1 app on the emulator
(Android) or simulator (iOS).

```bash
cd sample79
npm install                                 # baseline npm deps
```

The remaining commands assume `cd sample79` as the starting point.

### Apply all six patches (one-time)

```bash
../scripts/apply-patches.sh
```

`scripts/apply-patches.sh` applies all six in canonical order (four
RN-side under `node_modules/react-native/`; two app-side under
`sample79/`) and writes a marker file at
`sample79/node_modules/react-native/.directtv-v1-patches-applied`.
Re-running the script is a no-op while the marker is present;
delete the marker to force re-application (or just `rm -rf
node_modules && npm install` and re-run).

If you'd rather apply by hand, the equivalent commands are:

```bash
( cd node_modules/react-native && \
  patch -p1 -i ../../../patches/01-jsi-vendoring.patch && \
  patch -p1 -i ../../../patches/02-rn-surgery.patch && \
  patch -p1 -i ../../../patches/04-cdp-adapter.patch && \
  patch -p1 -i ../../../patches/05-ios.patch )
patch -p1 -i ../patches/03-app-side.patch
patch -p1 -i ../patches/06-ios-app-side.patch
```

The Android-only patches (02 partial, 03) and iOS-only patches (05, 06)
modify disjoint files, so it's safe to apply them all even if you only
intend to build one platform.

### Android — Debug APK (Metro serves the JS)

```bash
cd android
./gradlew --no-daemon assembleDebug          # ~4 min cold, much faster incremental
```

(`--no-daemon` works around a sandboxing issue with the Gradle daemon's
localhost socket; drop it if not running under sandbox restrictions.)

Boot the emulator and launch:

```bash
emulator -avd Medium_Phone_API_36 &           # boot in background

cd /path/to/sample79
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
npx react-native start &                     # Metro
adb reverse tcp:8081 tcp:8081
adb shell am start -n com.sample79/.MainActivity
```

Verify V1 ran the bundle:

```bash
adb logcat -d ReactNativeJS:V '*:S' | tail
# expect: ReactNativeJS: Running "sample79" with {...}
```

### Android — Release APK (HBC bundle baked in, no Metro)

The release build inlines a precompiled HBC bundle, so it needs the V1
host bytecode compiler (`hermesc`). RN 0.79's bundled `hermesc` emits
HBC v96; V1 requires v98. The matching host compiler is in the
`hermes-compiler` npm package (versioned in lockstep with the
`hermes-android` AAR).

After the debug path works:

```bash
cd sample79
npm install hermes-compiler@250829098.0.13 --save-dev

cd android
./gradlew --no-daemon assembleRelease         # ~4 min cold

adb uninstall com.sample79                    # release uses a different keystore
adb install app/build/outputs/apk/release/app-release.apk
adb shell am start -n com.sample79/.MainActivity
```

(`hermesCommand` in `app/build.gradle` is already set by patch 03; the
gradle plugin substitutes `%OS-BIN%` for the host-OS bin dir at build
time.)

Verify with `adb logcat -d ReactNativeJS:V '*:S' | tail` — same expected
output, no Metro needed.

### iOS — one-time setup

CocoaPods via Bundler against system Ruby (rationale in §8a):

```bash
bundle config set --local path 'vendor/bundle'
bundle install
```

Pre-vendor the V1 iOS tarballs under `vendor/hermes-ios/` at the repo
root, sibling of `sample79/` (rationale in §8b):

```bash
../scripts/vendor-hermes-ios.sh
```

(Idempotent: skips files that are already present.)

### iOS — Debug app (iOS Simulator, Metro serves the JS)

```bash
cd ios
HERMES_ENGINE_TARBALL_PATH=$PWD/../../vendor/hermes-ios/hermes-ios-250829098.0.13-debug.tar.gz \
  bundle exec pod install

xcodebuild -workspace sample79.xcworkspace -scheme sample79 \
  -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  build
```

Boot the simulator (and open the GUI so you can see it) and launch:

```bash
xcrun simctl boot "iPhone 17"          # idempotent: "Device already booted" is fine
open -a Simulator                      # show the simulator window

APP=~/Library/Developer/Xcode/DerivedData/sample79-*/Build/Products/Debug-iphonesimulator/sample79.app
xcrun simctl install booted $APP

cd /path/to/sample79
npx react-native start &               # Metro (simulator reaches host's localhost directly — no `adb reverse` analog needed)

xcrun simctl launch booted org.reactjs.native.example.sample79
```

Verify V1 ran the bundle: the welcome screen renders **Engine: Hermes
250829098.0.13**. (Sample-screenshot confirmation; RN's
`ReactNativeJS:` log channel doesn't surface as cleanly via `log show`
on iOS as it does via `adb logcat` on Android.)

### iOS — Release app (HBC bundle baked in, no Metro)

iOS is simpler than Android here: the V1 iOS tarball ships its own
host `hermesc` at `destroot/bin/hermesc`, and RN's
`react-native-xcode.sh` finds it at that exact path automatically.
**No `hermes-compiler` npm install, no `HERMES_CLI_PATH` wiring.**

After the debug path works:

```bash
cd sample79/ios
HERMES_ENGINE_TARBALL_PATH=$PWD/../../vendor/hermes-ios/hermes-ios-250829098.0.13-release.tar.gz \
  bundle exec pod install

xcodebuild -workspace sample79.xcworkspace -scheme sample79 \
  -configuration Release -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  build

xcrun simctl uninstall booted org.reactjs.native.example.sample79
APP=~/Library/Developer/Xcode/DerivedData/sample79-*/Build/Products/Release-iphonesimulator/sample79.app
xcrun simctl install booted $APP
xcrun simctl launch booted org.reactjs.native.example.sample79
```

No Metro needed — the JS bundle is baked in at
`sample79.app/main.jsbundle`. Verify byte 8 of the bundle is the V1
HBC version (`0x62` = 98 decimal):

```bash
xxd -l 16 $APP/main.jsbundle
# expect: c61f bc03 c103 191f 6200 ...   ← byte 8 = 62 = HBC v98
```

Same Welcome-screen check for **Engine: Hermes 250829098.0.13**.

## 1. Create the project

(The committed `sample79/` is exactly what this command produces. Skip
unless you want to regenerate the baseline against a different RN
version.)

```bash
npx @react-native-community/cli init sample79 --version 0.79.5
```

Answer **no** to the CocoaPods prompt — the bootstrap was Android-first
and the prompt only controls whether the init runs `pod install` for
you, not whether the iOS scaffolding is generated. The iOS
`Podfile`/`xcodeproj` are scaffolded either way, and we run
`bundle exec pod install` manually later (§8a) once the V1 swap is in
place.

## 2. Build the debug APK on Android (prebuilt RN/Hermes from Maven)

This is the default RN build path: `react-android` and `hermes-android` come
as prebuilt AARs from Maven; only `libappmodules.so` (the autolinking JNI
shim) is compiled locally.

The Gradle wrapper will download Gradle 8.13 on first run, and the Android
build will auto-install NDK 27.1.12297006 and CMake 3.22.1 if missing.

```bash
cd sample79/android
./gradlew assembleDebug
```

Output APK (fat, ~116 MB, all 4 ABIs):

```
sample79/android/app/build/outputs/apk/debug/app-debug.apk
```

## 3. Start an Android emulator

```bash
emulator -list-avds                       # show available AVDs
emulator -avd Medium_Phone_API_36 &       # boot in background
adb devices                               # confirm it shows up
```

## 4. Install and run on Android

```bash
cd sample79
adb install -r android/app/build/outputs/apk/debug/app-debug.apk

# In one shell: start Metro and leave it running.
npx react-native start

# In another shell: forward Metro's port into the emulator and launch the app.
adb reverse tcp:8081 tcp:8081
adb shell am start -n com.sample79/.MainActivity
```

The first launch takes 10–30 seconds while Metro bundles. You should land on
the default RN welcome screen.

To stop the app:

```bash
adb shell am force-stop com.sample79
```

Debug builds expect Metro to serve the JS bundle at runtime. For a
self-contained APK with JS baked in, build `assembleRelease` (needs a signing
config) or pre-bundle with `npx react-native bundle`.

## 5. Build RN and Hermes from source (Android)

`node_modules/react-native/` ships its full Android source tree and a
`settings.gradle.kts` set up for Gradle's `includeBuild` workflow. We point
the app at it via dependency substitution, so `com.facebook.react:react-android`
and `com.facebook.react:hermes-android` resolve to the local subprojects
instead of Maven AARs.

### 5a. Wire up the composite build

Append to `sample79/android/settings.gradle`:

```groovy
includeBuild('../node_modules/react-native') {
    dependencySubstitution {
        substitute(module("com.facebook.react:react-android")).using(project(":packages:react-native:ReactAndroid"))
        substitute(module("com.facebook.react:hermes-android")).using(project(":packages:react-native:ReactAndroid:hermes-engine"))
    }
}
```

### 5b. Stub out `sdkmanager`

The `hermes-engine` module's `installCMake` task always *configures* a call
to `$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager`, even though it only
*runs* it when CMake is missing. Configuration fails if the binary doesn't
exist, so drop a no-op stub (the task itself never executes since we already
have CMake 3.22.1):

```bash
mkdir -p "$ANDROID_HOME/cmdline-tools/latest/bin"
printf '#!/bin/sh\nexit 0\n' > "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
chmod +x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
```

A real `cmdline-tools` install would also work but isn't necessary.

### 5c. Build

The Hermes source gets downloaded from GitHub on first run (commit pinned in
`node_modules/react-native/sdks/.hermesversion`) and unpacked into
`node_modules/react-native/sdks/hermes/`.

```bash
cd sample79/android
./gradlew --no-daemon assembleDebug
```

`--no-daemon` avoids a sandboxing issue with the Gradle daemon's localhost
socket; drop it if you're not running under sandbox restrictions.

First-time run: ~7-8 minutes (compiles `libreactnative.so`, `libhermes.so`,
and the rest of RN's C++ for all 4 ABIs). Subsequent incremental builds are
much faster.

Same APK path as before:

```
sample79/android/app/build/outputs/apk/debug/app-debug.apk
```

Reinstall and relaunch with the same commands from step 4.

## 6. Swap in Hermes V1 on Android

This builds RN 0.79.5's Android native side against Hermes V1
(`static_h` branch), consuming V1 as a Maven prebuilt instead of
building Hermes inline. See `CLAUDE.md` for the high-level rationale.
The iOS analog is in §8 (CocoaPods rather than Gradle/CMake, but
consumes the same V1 Maven artifacts).

Quick recap of the deltas:

- V1 lives at a new Maven coord: `com.facebook.hermes:hermes-android` (note
  the `hermes` group, not `react`). Latest version when these notes were
  written: `250829098.0.13`.
- The library is renamed `libhermes.so` → `libhermesvm.so`. Prefab module
  rename: `hermes-engine::libhermes` → `hermes-engine::hermesvm`. The prefab
  *package* name is still `hermes-engine`.
- V1 ships only Hermes headers in its AAR. JSI must come from elsewhere; we
  vendor the matching JSI from `facebook/hermes:static_h:API/jsi/jsi/` over
  RN 0.79's `ReactCommon/jsi/jsi/`.
- V1's Hermes API has shifted in places (sampling profiler, CDP vs. old
  inspector, `setFatalHandler`). We stub or `#ifdef` the affected RN
  code; sampling profiler stays sacrificed, but Chrome devtools is
  restored via a small CDP adapter shim (§6i, design notes in
  `CDP_ADAPTER_PLAN.md`).

You should have already done sections 1, 5a, and 5b above (the `includeBuild`
block in `settings.gradle`, and the `sdkmanager` stub). Section 5c is **not**
needed for V1.

### Two ways to apply the changes

All RN-side modifications are captured as patches under `patches/` in this
repo. You can either **apply the patches** (fast, exactly reproduces the
known-good state) or **walk through the steps manually** (slower, but you'll
understand each change). Both end at the same place.

#### Option A — apply the patches (recommended)

Four patch files cover the entire Android modification (patches 05/06
are iOS-only and live in §8):

- **`patches/01-jsi-vendoring.patch`** — wholesale replacement of RN 0.79's
  `ReactCommon/jsi/jsi/` with the JSI from
  `facebook/hermes:hermes-v250829098.0.13` (tag matching the V1 AAR — *not*
  branch HEAD, since JSI is source-stable only). 7 files, ~145 KB. Most of
  it is `jsi.h` (V1 added a lot of API surface). Pure upstream vendoring,
  no RN-authored content. Bumping the V1 AAR requires regenerating this
  patch from the corresponding tag.

- **`patches/02-rn-surgery.patch`** — the RN-side adaptation: 17 files,
  ~17 KB. Gradle wiring (Maven coord swap, dropped `:hermes-engine`
  subproject, jniLibs exclude), CMake renames (`libhermes` → `hermesvm`),
  `HERMES_ENABLE_DEBUGGER` removed from 8 spots, three small stubs/edits
  for V1 API drift (sampling profiler, `setFatalHandler`, one unconditional
  inspector include), and a `-Wno-overloaded-virtual` for JSC.

- **`patches/03-app-side.patch`** — the two app-side gradle edits documented
  in §6b (V1 Maven coord substitution in `android/settings.gradle`) and §7b
  (`hermesCommand` in `android/app/build.gradle`). Applied from `sample79/`,
  not from inside `node_modules/react-native/`. The §7a `npm install
  hermes-compiler` step is *not* covered by this patch — it's an `npm`
  command, not a source edit.

- **`patches/04-cdp-adapter.patch`** — the CDP-adapter shim that restores
  the legacy `hermes/inspector/*` API on top of V1's `hermes/cdp/*` API.
  Layers on top of patches 01 + 02; re-enables `HERMES_ENABLE_DEBUGGER`
  in the 8 CMake spots that patch 02 had stripped, adds two new
  source files under `ReactCommon/hermes/inspector/`
  (`RuntimeAdapter.{h,cpp}`, `chrome/CDPHandler.{h,cpp}`) and the
  CMake plumbing to build them as `hermes_inspector_shim` and bundle
  the objects into `libhermestooling.so`. See `CDP_ADAPTER_PLAN.md`
  at the repo root for design notes.

Apply, then build:

```bash
cd sample79/node_modules/react-native
patch -p1 -i ../../../patches/01-jsi-vendoring.patch
patch -p1 -i ../../../patches/02-rn-surgery.patch
patch -p1 -i ../../../patches/04-cdp-adapter.patch
cd ../..
patch -p1 -i ../patches/03-app-side.patch

cd android
./gradlew --no-daemon assembleDebug
```

Skip ahead to **6j** (build / install / run) once the patches are applied.
The rest of section 6 walks through the same changes manually:
§6a–§6h mirror what patches 01 + 02 do; §6i is the CDP-adapter shim
(patch 04), which §6e and §6g touch — see the cross-references in
those sections. The shim itself is too large to inline so §6i directs
you to apply patch 04 even within the manual walkthrough.

To regenerate these patches against a different RN snapshot or after
upstream JSI/Hermes changes, see `patches/REGENERATE.md` (sketch: download
a pristine RN tarball with `npm pack`, `diff -uN` per file with `--label
a/<rel>` and `--label b/<rel>`).

#### Option B — manual walkthrough

The rest of section 6 is a guided manual application of the same changes.
Useful if you want to understand each modification, adapt to a different RN
version, or see what V1 demanded of each subsystem.

### 6a. Vendor static_h JSI

Replace RN 0.79's JSI (`ReactCommon/jsi/jsi/`) with the version Hermes V1 was
built against. **Pin to the tag matching the V1 AAR you're consuming**, not
the `static_h` branch tip — JSI is source-stable not ABI-stable, so any
inline-function or vtable change between the AAR's snapshot and HEAD is
silent UB. The tag pattern is `hermes-v<aar-version>`:

```bash
TAG=hermes-v250829098.0.13          # match the hermes-android Maven version
JSI_DST="sample79/node_modules/react-native/ReactCommon/jsi/jsi"
files="CMakeLists.txt JSIDynamic.cpp JSIDynamic.h decorator.h \
       hermes-interfaces.h instrumentation.h jsi-inl.h jsi.cpp jsi.h \
       jsilib-posix.cpp jsilib-windows.cpp jsilib.h threadsafe.h"
for f in $files; do
  curl -sfL -o "$JSI_DST/$f" \
    "https://raw.githubusercontent.com/facebook/hermes/$TAG/API/jsi/jsi/$f"
done
```

`hermes-interfaces.h` is new (didn't exist in RN 0.79's JSI); the other 12
files are drop-in overwrites. The CMake `CXX_STANDARD` bumps from 14 to 17
which is fine since RN already compiles surrounding C++ at 17/20.

If you bump the V1 AAR version in §6b, update `TAG` here and re-vendor.

### 6b. Switch the Gradle substitution to the V1 prebuilt

(Covered by `patches/03-app-side.patch` if you took §6 Option A.)

In `sample79/android/settings.gradle`, change the hermes-android substitution
to point at the V1 Maven coord:

```groovy
includeBuild('../node_modules/react-native') {
    dependencySubstitution {
        substitute(module("com.facebook.react:react-android")).using(project(":packages:react-native:ReactAndroid"))
        substitute(module("com.facebook.react:hermes-android")).using(module("com.facebook.hermes:hermes-android:250829098.0.13"))
    }
}
```

### 6c. Remove the local `:hermes-engine` subproject

In `sample79/node_modules/react-native/settings.gradle.kts`, drop the two
`include`/`projectDir` lines for `:hermes-engine`. Keep only the
`:ReactAndroid` include.

In `sample79/node_modules/react-native/ReactAndroid/build.gradle.kts`:

- Replace the project dep with the V1 Maven coord:

  ```diff
  -  compileOnly(project(":packages:react-native:ReactAndroid:hermes-engine"))
  +  compileOnly("com.facebook.hermes:hermes-android:250829098.0.13")
  ```

- Drop the `preBuild` task ordering hook on `:hermes-engine`:

  ```diff
     prepareKotlinBuildScriptModel.dependsOn("preBuild")
  -  prepareKotlinBuildScriptModel.dependsOn(
  -      ":packages:react-native:ReactAndroid:hermes-engine:preBuild")
  ```

- Add the renamed library to the `jniLibs.excludes` so we don't double-pack
  it (V1's prefab AAR already provides it):

  ```diff
       jniLibs.excludes.add("**/libhermes.so")
  +    jniLibs.excludes.add("**/libhermesvm.so")
       jniLibs.excludes.add("**/libjsc.so")
  ```

### 6d. CMake: rename `hermes-engine::libhermes` → `hermes-engine::hermesvm`

8 sites in RN's CMake reference the old prefab module name. From
`sample79/node_modules/react-native`:

```bash
files="
  ReactCommon/hermes/inspector-modern/CMakeLists.txt
  ReactCommon/hermes/executor/CMakeLists.txt
  ReactCommon/react/runtime/hermes/CMakeLists.txt
  ReactAndroid/src/main/jni/CMakeLists.txt
  ReactAndroid/src/main/jni/react/runtime/hermes/jni/CMakeLists.txt
  ReactAndroid/src/main/jni/react/hermes/instrumentation/CMakeLists.txt
  ReactAndroid/src/main/jni/react/hermes/reactexecutor/CMakeLists.txt
  ReactAndroid/src/main/jni/react/hermes/tooling/CMakeLists.txt
"
for f in $files; do
  sed -i '' 's/hermes-engine::libhermes/hermes-engine::hermesvm/g' "$f"
done
```

### 6e. Disable HERMES_ENABLE_DEBUGGER

> **Note:** §6i later reverses this step (the CDP shim provides a
> working back-end so we keep `HERMES_ENABLE_DEBUGGER` on in the
> final state). The intermediate "off" state is what makes the
> inspector-modern code in §6f and §6g drop out cleanly without
> needing a shim yet — patch 02 captures exactly this state.
> If you only care about the final tree, you can fast-forward by
> applying patches 01+02+04 (i.e., switch to Option A above).

V1 replaces the old `hermes/inspector/*` headers with `hermes/cdp/*`. RN
0.79's "inspector-modern" code targets the old API and won't compile. The
inspector code is gated on `HERMES_ENABLE_DEBUGGER`, so undefining it makes
the offending code drop out. (Cost: no Chrome devtools debugging — until
§6i adds the shim.)

7 standalone `HERMES_ENABLE_DEBUGGER` lines can be deleted outright; from
`sample79/node_modules/react-native`:

```bash
for f in \
  ReactCommon/hermes/inspector-modern/CMakeLists.txt \
  ReactCommon/hermes/executor/CMakeLists.txt \
  ReactCommon/react/runtime/CMakeLists.txt \
  ReactCommon/react/runtime/hermes/CMakeLists.txt \
  ReactAndroid/src/main/jni/react/runtime/hermes/jni/CMakeLists.txt \
  ReactAndroid/src/main/jni/react/runtime/jni/CMakeLists.txt \
  ReactAndroid/src/main/jni/react/hermes/reactexecutor/CMakeLists.txt
do
  sed -i '' '/HERMES_ENABLE_DEBUGGER/d' "$f"
done
```

One spot needs hand-editing because the define shares a line with the
closing paren of `target_compile_options(...)`. In
`ReactAndroid/src/main/jni/CMakeLists.txt` change:

```diff
     -std=c++20
-    -DHERMES_ENABLE_DEBUGGER)
+    -std=c++20)
```

### 6f. Wrap one unconditional Hermes-inspector include

`ReactCommon/hermes/executor/HermesExecutorFactory.cpp` includes the old
`hermes/inspector/RuntimeAdapter.h` outside any `#ifdef`. Wrap it:

```diff
 #include <hermes/inspector-modern/chrome/HermesRuntimeTargetDelegate.h>
+#ifdef HERMES_ENABLE_DEBUGGER
 #include <hermes/inspector-modern/chrome/Registration.h>
 #include <hermes/inspector/RuntimeAdapter.h>
+#endif
```

(The other RN files referencing `hermes/inspector/*` already have the
includes inside `#ifdef HERMES_ENABLE_DEBUGGER`, so once 6e is done they
compile clean.)

### 6g. Stub V1 API drift in three files

These RN sources use Hermes APIs that shifted between RN 0.79's pinned
Hermes commit and `static_h`. Stubbed for now (functionality lost,
compilability gained). Mark the file with a comment so the next person
knows what's missing.

(§6i adds a fourth stub for `HermesRuntimeTargetDelegate.cpp`, which
is only needed once `HERMES_ENABLE_DEBUGGER` is back on — without §6e
it would belong here too.)

**`ReactCommon/hermes/inspector-modern/chrome/HermesRuntimeSamplingProfileSerializer.cpp`** —
V1's `sampling_profiler::ProfileSampleCallStackFrame` is a `std::variant`
instead of a class hierarchy with `getKind()`. Replace the file body with
an empty serializer:

```cpp
#include "HermesRuntimeSamplingProfileSerializer.h"

namespace facebook::react::jsinspector_modern::tracing {

/* static */ RuntimeSamplingProfile
HermesRuntimeSamplingProfileSerializer::serializeToTracingSamplingProfile(
    const hermes::sampling_profiler::Profile& /*hermesProfile*/) {
  return RuntimeSamplingProfile{
      "Hermes", std::vector<RuntimeSamplingProfile::Sample>{}};
}

} // namespace facebook::react::jsinspector_modern::tracing
```

**`ReactAndroid/src/main/jni/react/hermes/instrumentation/HermesSamplingProfiler.cpp`** —
the static `HermesRuntime::enable/disable/dumpSampledTraceToFile` entry
points moved off the runtime in V1. Stub the three method bodies:

```cpp
void HermesSamplingProfiler::enable(jni::alias_ref<jclass>) {}

void HermesSamplingProfiler::disable(jni::alias_ref<jclass>) {}

void HermesSamplingProfiler::dumpSampledTraceToFile(
    jni::alias_ref<jclass>,
    std::string /*filename*/) {}
```

**`ReactAndroid/src/main/jni/react/hermes/reactexecutor/OnLoad.cpp`** —
`HermesRuntime::setFatalHandler` was replaced by an `ICast`-based
`hermes::ISetFatalHandler` interface. Both call sites (lines ~60 and ~78)
become:

```cpp
    std::call_once(flag, []() {
      // Hermes V1 replaced the static setFatalHandler with an
      // ICast-based ISetFatalHandler interface; skipped permanently.
      // The original handler was just:
      //   LOG(ERROR) << "Hermes Fatal: " << reason;
      //   __android_log_assert(nullptr, "Hermes", "%s", reason.c_str());
      // which calls abort() internally — so dropping it costs us exactly
      // one extra logcat line before the SIGABRT. No red box, no JS
      // stack, no symbolication. Not worth restoring.
      (void)hermesFatalHandler;
    });
```

### 6h. Silence one warning in JSC

The new JSI added virtual overloads that JSCRuntime doesn't override,
tripping `-Werror -Woverloaded-virtual`. Add a single `-Wno-overloaded-virtual`
to JSC's compile options in
`sample79/node_modules/react-native/ReactCommon/jsc/CMakeLists.txt`:

```diff
 add_compile_options(
         -fexceptions
         -frtti
         -O3
         -Wno-unused-lambda-capture
+        -Wno-overloaded-virtual
         -DLOG_TAG=\"ReactNative\")
```

(JSC isn't actually used at runtime when `hermesEnabled=true`, but it's
still compiled. Properly fixing this means adding the missing JSI virtuals
in JSCRuntime; -Wno is the path of least resistance.)

### 6i. Add the CDP adapter shim (restores devtools)

§6e–§6h leave you with a working V1 build but no Chrome devtools.
This step re-enables `HERMES_ENABLE_DEBUGGER` and adds a small
adapter shim so RN's inspector-modern code can keep including the
old `hermes/inspector/*` headers while delegating to V1's
`hermes/cdp/CDPAgent`. The shim is captured in
**`patches/04-cdp-adapter.patch`** — apply it directly even within
the manual walkthrough; the new source files (~600 lines) are too
large to inline:

```bash
cd sample79/node_modules/react-native
patch -p1 -i ../../../patches/04-cdp-adapter.patch
```

What patch 04 does, at a glance:

- **Reverses §6e**: re-adds `-DHERMES_ENABLE_DEBUGGER=1` (or the
  `$<$<CONFIG:Debug>:...>` generator-expression equivalent) to the
  same 8 CMake spots §6e stripped. The §6f `#ifdef` wrap stays —
  it's defensive and harmless.
- **Adds a fourth stub** to §6g's list:
  `ReactCommon/hermes/inspector-modern/chrome/HermesRuntimeTargetDelegate.cpp`'s
  three sampling-profiler methods (`enableSamplingProfiler`,
  `disableSamplingProfiler`, `collectSamplingProfile`) — V1 moved the
  underlying `HermesRuntime` entry points to an `IHermesRootAPI`
  interface and removed `dumpSampledTraceToProfile` entirely. Same
  treatment as the other sampling-profiler stubs; the now-unused
  `HERMES_SAMPLING_FREQUENCY_HZ` constant is dropped to keep
  `-Werror=unused-const-variable` happy.
- **Adds new files** under `ReactCommon/hermes/inspector/`:
  `RuntimeAdapter.{h,cpp}` (re-exposes the old base class plus a new
  `enqueueRuntimeTask` virtual that the V1 CDP back-end requires) and
  `chrome/CDPHandler.{h,cpp}` (the actual V1-API translation, with a
  per-runtime refcounted `CDPDebugAPI` registry).
- **Adds a new CMake target** `hermes_inspector_shim` (an `OBJECT`
  library) built with `-DHERMES_ENABLE_DEBUGGER=1` (needed because
  `hermes/AsyncDebuggerAPI.h` gates the real V1 API on that define),
  registered as a sub-directory in
  `ReactAndroid/src/main/jni/CMakeLists.txt`, linked into
  `hermes_inspector_modern`, `hermes_executor_common`,
  `bridgelesshermes`, and `reactnative_unittest`, and aggregated
  into `libhermestooling.so` via `$<TARGET_OBJECTS:...>`.
- **Overrides `enqueueRuntimeTask`** in the two `RuntimeAdapter`
  subclasses (`HermesExecutorRuntimeAdapter` in
  `HermesExecutorFactory.cpp` and `HermesInstanceRuntimeAdapter` in
  `HermesInstance.cpp`), routing tasks through their existing
  `MessageQueueThread::runOnQueue`.

Design notes (open questions, MVP scope-cuts, risks) are in
`CDP_ADAPTER_PLAN.md` at the repo root.

### 6j. Build, install, run

```bash
cd sample79/android
./gradlew --no-daemon assembleDebug
```

Expected: `BUILD SUCCESSFUL`, around 2-3 minutes (the slow part is
`libreactnative.so` + per-ABI native compile of the RN side; Hermes itself
is a prebuilt now).

Install and launch as in step 4. Watch for proof of life:

```bash
adb logcat -d ReactNativeJS:V '*:S' | tail
# expect: ReactNativeJS: Running "sample79" with {...}
```

Verify the APK has V1 binaries:

```bash
unzip -l sample79/android/app/build/outputs/apk/debug/app-debug.apk \
  | grep -E 'libhermes|libreactnative'
# expect: libhermesvm.so (V1) and libreactnative.so present;
# NO libhermes.so
```

## 7. Release build on Hermes V1 (Android)

Debug builds get JS from Metro at runtime, so the bytecode compiler
(`hermesc`) isn't on the path. Release builds inline a precompiled HBC
(Hermes Bytecode) bundle into the APK, so they need a `hermesc` whose
**bytecode version** matches the runtime.

(iOS Release is much simpler — see §9 — because the V1 iOS tarball
ships its own host hermesc.)

- RN 0.79's bundled hermesc (`node_modules/react-native/sdks/hermesc/...`)
  emits **HBC v96** — Hermes V1 (`libhermesvm.so`) requires **HBC v98** and
  refuses anything older.
- The V1 AAR ships **no host binaries**.
- The matching host hermesc lives in the `hermes-compiler` npm package,
  versioned in lockstep with `hermes-android`.

### 7a. Install V1 hermesc

```bash
cd sample79
npm install hermes-compiler@250829098.0.13 --save-dev
```

Resulting binary (macOS): `node_modules/hermes-compiler/hermesc/osx-bin/hermesc`.
Sanity-check the bytecode version (look for `HBC bytecode version: 98`):

```bash
node_modules/hermes-compiler/hermesc/osx-bin/hermesc -version
```

### 7b. Point RN's gradle plugin at V1 hermesc

(Covered by `patches/03-app-side.patch` if you took §6 Option A.)

In `sample79/android/app/build.gradle`, set `hermesCommand` inside the
`react {}` block (the `%OS-BIN%` token is substituted by RN's gradle
plugin to the host-OS bin dir):

```diff
     /* Hermes Commands */
     //   The hermes compiler command to run. By default it is 'hermesc'
     // hermesCommand = "$rootDir/my-custom-hermesc/bin/hermesc"
+    hermesCommand = file("../../node_modules/hermes-compiler/hermesc/%OS-BIN%/hermesc").absolutePath
```

### 7c. Build, install, run

```bash
cd sample79/android
./gradlew --no-daemon assembleRelease
```

Output APK (~50 MB, signed with the bundled debug keystore — fine for
local testing, replace for production):

```
sample79/android/app/build/outputs/apk/release/app-release.apk
```

Install. Note: signed with a different keystore than any leftover debug
install, so uninstall first:

```bash
adb uninstall com.sample79
adb install sample79/android/app/build/outputs/apk/release/app-release.apk
adb shell am start -n com.sample79/.MainActivity
```

No Metro needed — the JS bundle is in the APK at
`assets/index.android.bundle`. Verify it's V1 bytecode (byte 8 of an HBC
file is the bytecode version, little-endian):

```bash
unzip -p sample79/android/app/build/outputs/apk/release/app-release.apk \
  assets/index.android.bundle | xxd -l 16
# expect byte 8 == 62 (hex) == 98 (decimal) = HBC v98
```

Watch logcat for `ReactNativeJS: Running "sample79"` to confirm V1
executed the bundle.

## 8. Swap in Hermes V1 on iOS

The iOS analog of §6. RN 0.79's iOS build uses CocoaPods rather than
Gradle/CMake, but consumes the same family of V1 prebuilts and reuses
patches 01–04 from §6. The two new patches add what's iOS-specific:

- `patches/05-ios.patch` — RN-side CocoaPods plumbing (the
  build-system analog of patch 02 for iOS).
- `patches/06-ios-app-side.patch` — app-side `Podfile` `post_install`
  hook (the analog of patch 03 for iOS).

Patches 02 and 03 from the Android path are also applied — most of
patch 02 is Android Gradle/CMake and inert when building iOS, but it
contains shared C++ source surgery (the `HermesExecutorFactory.cpp`
`#ifdef` wrap from §6f and the `HermesRuntimeSamplingProfileSerializer.cpp`
stub from §6g) that the iOS build also compiles. Patch 04 in turn
layers on patch 02. So the canonical apply-order for iOS is:

```bash
cd sample79/node_modules/react-native
patch -p1 -i ../../../patches/01-jsi-vendoring.patch
patch -p1 -i ../../../patches/02-rn-surgery.patch
patch -p1 -i ../../../patches/04-cdp-adapter.patch
patch -p1 -i ../../../patches/05-ios.patch
cd ../..
patch -p1 -i ../patches/03-app-side.patch
patch -p1 -i ../patches/06-ios-app-side.patch
```

(Patch 03 only edits Android Gradle files, so it's a no-op on the
iOS build but harmless — keeps the patch sequence uniform.)

Quick recap of the iOS-specific deltas vs §6:

- V1 iOS lives at a different Maven coord: `com.facebook.hermes:hermes-ios`
  (note the `-ios` suffix, sibling of `hermes-android`). Same version
  scheme `<YYMMDDxxx>.0.N`; same version `250829098.0.13`.
- The library rename is the same on iOS: `hermes.framework` →
  `hermesvm.framework` inside `hermesvm.xcframework`.
- The V1 iOS tarball **bundles JSI headers** under `destroot/include/jsi/`
  (unlike the Android AAR, which ships only Hermes headers). We still
  vendor JSI into RN's tree via patch 01 — the bundled tarball copy is
  ignored to avoid two competing `<jsi/*>` resolutions.
- The V1 iOS tarball also ships a **host macOS hermesc** at
  `destroot/bin/hermesc`. RN's `react-native-xcode.sh` finds it there
  by default — so unlike Android (§7), iOS Release does **not** need
  the `hermes-compiler` npm package.
- Independent issue: fmt 11.0.2 (which RN 0.79 pins) trips a `consteval`
  evaluation error under Xcode 26's clang. Patches 05 + 06 work around
  it; not part of the V1 swap proper.

You should have already done §1 (bootstrap).

### 8a. Set up CocoaPods via Bundler against system Ruby

`sample79/Gemfile` is pinned to `ruby ">= 2.6.10"` and a CocoaPods
version range that works with macOS's system Ruby (`/usr/bin/ruby`,
2.6.10). No rbenv/rvm/Homebrew Ruby is needed.

```bash
cd sample79
bundle config set --local path 'vendor/bundle'   # project-local install
bundle install                                   # installs CocoaPods + deps
bundle exec pod --version                        # sanity check; expect 1.15.x
```

The `--local` config writes `sample79/.bundle/config` and only affects
this project. Every subsequent `pod` call uses `bundle exec pod ...`.

### 8b. Pre-vendor the V1 iOS tarballs

CocoaPods needs the V1 prebuilt tarballs at install time. Download
them once and cache locally under `vendor/hermes-ios/` at the repo
root (sibling of `sample79/`, **not** inside it). We pass `-o` to
`curl` to give the files shorter local names — the Maven URLs
themselves have a `hermes-ios-<ver>-hermes-ios-<type>.tar.gz`
double-naming (artifact ID and classifier prefix happen to both be
`hermes-ios`) that's ugly to type later:

```bash
cd /path/to/directtv                    # repo root
mkdir -p vendor/hermes-ios && cd vendor/hermes-ios
curl -fLo hermes-ios-250829098.0.13-debug.tar.gz \
  https://repo1.maven.org/maven2/com/facebook/hermes/hermes-ios/250829098.0.13/hermes-ios-250829098.0.13-hermes-ios-debug.tar.gz
curl -fLo hermes-ios-250829098.0.13-release.tar.gz \
  https://repo1.maven.org/maven2/com/facebook/hermes/hermes-ios/250829098.0.13/hermes-ios-250829098.0.13-hermes-ios-release.tar.gz
```

Sizes: ~28 MB debug, ~22 MB release. Each Maven asset has accompanying
`.sha256` if you want to verify.

### 8c. Apply the patches

If you came from §6 you already have patches 01, 02, 03, 04 applied.
For iOS, additionally apply 05 and 06:

```bash
( cd sample79/node_modules/react-native && \
  patch -p1 -i ../../../patches/05-ios.patch )
( cd sample79 && \
  patch -p1 -i ../patches/06-ios-app-side.patch )
```

If you skipped §6 and want only the iOS path, apply the canonical
six-patch sequence shown at the top of §8 instead.

What patch 05 touches (RN-side, four files; full breakdown in
`patches/REGENERATE.md`):

- `sdks/hermes-engine/hermes-engine.podspec` — pin
  `spec.version = "250829098.0.13"`; rename every `hermes.framework` /
  `hermes.xcframework` → `hermesvm.*`; pull
  `destroot/include/jsi/hermes-interfaces.h` into the `Pre-built`
  subspec's `source_files` so the `hermes/hermes.h` umbrella include
  resolves.
- `sdks/hermes-engine/hermes-utils.rb` — `release_tarball_url` now
  points at `com.facebook.hermes:hermes-ios` (V1 coord) instead of
  the legacy `com.facebook.react:react-native-artifacts`.
- `ReactCommon/hermes/React-hermes.podspec` — glob `inspector/*.{cpp,h}`
  and `inspector/chrome/*.{cpp,h}` (where the patch-04 CDP shim files
  live) into `source_files`. Add `HERMES_ENABLE_DEBUGGER=1` to
  `pod_target_xcconfig` unconditionally — the shim's
  `<hermes/AsyncDebuggerAPI.h>` gates the V1 API on it. Safe wrt
  downstream pods because `HermesRuntimeTargetDelegate` is pImpl'd
  to be ABI-stable across this define.
- `third-party-podspecs/fmt.podspec` — add
  `FMT_USE_CONSTEVAL=0` to the preprocessor definitions. Workaround
  for fmt 11.0.2 + clang 19+ (Xcode 26+).

What patch 06 touches (app-side, one file): `sample79/ios/Podfile`
gets a `post_install` hook that wraps fmt's `FMT_USE_CONSTEVAL`
detection block in `#ifndef` so the podspec-level define from
patch 05 actually wins. Has to live in `post_install` because
CocoaPods makes pod files read-only and re-extracts the pod source
on each `pod install` — an in-tree edit to `Pods/fmt/...` would be
silently wiped on the next install.

### 8d. Install pods with the V1 tarball

```bash
cd sample79/ios
HERMES_ENGINE_TARBALL_PATH=$PWD/../../vendor/hermes-ios/hermes-ios-250829098.0.13-debug.tar.gz \
  bundle exec pod install
```

`HERMES_ENGINE_TARBALL_PATH` short-circuits `hermes-utils.rb`'s source
selection (`HermesEngineSourceType::LOCAL_PREBUILT_TARBALL`), so we
never need network access at pod-install time.

You'll see a `[fmt] Patched base.h to honour external -DFMT_USE_CONSTEVAL=0`
line during the post-install hook. If you don't, the patch is already
in place from a prior install.

### 8e. Build, install, run

Boot a simulator and bring the GUI up so you can see it:

```bash
xcrun simctl boot "iPhone 17"          # any installed iOS sim works
open -a Simulator                      # show the simulator window
```

Build:

```bash
cd sample79/ios
xcodebuild -workspace sample79.xcworkspace -scheme sample79 \
  -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  build
```

Cold ~3 min; incremental much faster. Verify the V1 framework is in
the built `.app`:

```bash
APP=~/Library/Developer/Xcode/DerivedData/sample79-*/Build/Products/Debug-iphonesimulator/sample79.app
ls $APP/Frameworks/
# expect: hermesvm.framework  (V1)
otool -l $APP/Frameworks/hermesvm.framework/hermesvm | grep "name @"
# expect: name @rpath/hermesvm.framework/hermesvm
```

Install, start Metro, launch:

```bash
xcrun simctl install booted $APP
cd /path/to/sample79
npx react-native start &               # Metro on localhost:8081
xcrun simctl launch booted org.reactjs.native.example.sample79
```

(No `adb reverse` analog needed — the iOS Simulator reaches the host's
`localhost` directly.)

The Welcome screen renders **Engine: Hermes 250829098.0.13**, which is
RN's built-in engine indicator pulling the version straight from the
running runtime — confirms V1 executed the Metro-served bundle.

## 9. Release build on iOS

The iOS-equivalent of §7. Much shorter because the V1 iOS tarball
bundles a host macOS `hermesc` at `destroot/bin/hermesc`, and RN's
`react-native-xcode.sh` (line 81) defaults `HERMES_CLI_PATH` to that
exact path. **No `hermes-compiler` npm install, no `HERMES_CLI_PATH`
wiring, no podspec edit beyond what patch 05 already does.**

Sanity-check the bundled hermesc emits HBC v98 (byte 8 of any
compiled `.hbc` is the bytecode version, little-endian):

```bash
echo "console.log('hi');" | \
  sample79/ios/Pods/hermes-engine/destroot/bin/hermesc \
  -emit-binary -out /tmp/test.hbc /dev/stdin
xxd -l 16 /tmp/test.hbc
# expect: c61f bc03 c103 191f 6200 ...   ← byte 8 = 62 = HBC v98
```

### 9a. Re-install pods with the release tarball

The debug + release tarballs differ in compile flags inside
`hermesvm.framework`; switch by re-running pod install with the
release tarball:

```bash
cd sample79/ios
HERMES_ENGINE_TARBALL_PATH=$PWD/../../vendor/hermes-ios/hermes-ios-250829098.0.13-release.tar.gz \
  bundle exec pod install
```

### 9b. Build, install, run

```bash
cd sample79/ios
xcodebuild -workspace sample79.xcworkspace -scheme sample79 \
  -configuration Release -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  build
```

Build output ends with `+ /path/to/Pods/hermes-engine/destroot/bin/hermesc -emit-binary -O -out .../sample79.app/main.jsbundle ...`
— that's the V1 hermesc compiling the Metro-emitted JS bundle to HBC
v98 and baking it into the app.

Install (uninstall first if a debug build of the app is around) and
launch. Note: **kill Metro first** — otherwise a release build that
silently hits Metro for some asset would mask a real failure.

```bash
pkill -f "react-native start"          # ensure no Metro

APP=~/Library/Developer/Xcode/DerivedData/sample79-*/Build/Products/Release-iphonesimulator/sample79.app
xcrun simctl uninstall booted org.reactjs.native.example.sample79
xcrun simctl install booted $APP
xcrun simctl launch booted org.reactjs.native.example.sample79
```

Verify the baked HBC is V1:

```bash
xxd -l 16 $APP/main.jsbundle
# expect: c61f bc03 c103 191f 6200 ...   ← byte 8 = 62 = HBC v98
```

Welcome screen renders the same **Engine: Hermes 250829098.0.13** —
this time with no Metro running.

## Status

Android:

- [x] Project bootstrapped (RN 0.79.5)
- [x] Debug APK builds (prebuilt AARs)
- [x] App runs on emulator against Metro
- [x] RN + Hermes built from source via `includeBuild`
- [x] Hermes V1 swapped in (`com.facebook.hermes:hermes-android`); JS runs on V1
- [x] Release APK builds and runs on V1 (V1 hermesc from `hermes-compiler` npm package)
- [x] Restore Chrome devtools (CDP, against `hermes/cdp/*`) — done via the shim in `patches/04-cdp-adapter.patch`; design notes in `CDP_ADAPTER_PLAN.md`. End-to-end smoke: `Debugger.enable` over the inspector WebSocket round-trips through V1's `CDPAgent` and emits `Debugger.scriptParsed`. MVP scope-cuts: breakpoints lost across reloads, `waitForDebugger` ignored, console-API ingestion not yet routed.
- [ ] Sampling profiler (against V1's `hermes/Public/SamplingProfiler.h`) — fatal handler intentionally dropped (see §6g)

iOS:

- [x] Hermes V1 swapped in (`com.facebook.hermes:hermes-ios`); Debug app runs in iOS Simulator against Metro; welcome screen renders `Engine: Hermes 250829098.0.13`
- [x] Release app builds and runs on V1 with the JS bundle baked in as HBC v98 (no Metro). V1 iOS tarball ships its own host hermesc — no `hermes-compiler` npm dep needed unlike Android.
- [x] Patch 04's CDP shim compiles into `libReact-hermes.a` on iOS too, but Chrome devtools end-to-end on iOS hasn't been smoke-tested yet (Android-side smoke covers the shim's correctness).
- [ ] Run on a physical iOS device (only validated on the Simulator).
