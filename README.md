# React Native Hermes-swap experiment

Notes for setting up a baseline RN 0.79.5 Android app and rebuilding its
native side (including Hermes) from source, as a stepping stone toward
swapping in a newer Hermes/JSI.

## Prerequisites

- Node.js (with `npx`)
- Android Studio (for the SDK + emulator)
- An AVD created in Android Studio (we use `Medium_Phone_API_36`)
- **JDK 17** — RN 0.79's Gradle build trips `-Werror` on JDK 21's
  source/target=8 deprecation warnings, so we install Temurin 17:

  ```bash
  brew install --cask temurin@17
  ```

Common environment for all later steps:

```bash
export JAVA_HOME="/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$PATH"
```

## 1. Create the project

```bash
npx @react-native-community/cli init sample79 --version 0.79.5
```

Answer **no** to the CocoaPods prompt (we're targeting Android only).

## 2. Build the debug APK (prebuilt RN/Hermes from Maven)

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

## 3. Start an emulator

```bash
emulator -list-avds                       # show available AVDs
emulator -avd Medium_Phone_API_36 &       # boot in background
adb devices                               # confirm it shows up
```

## 4. Install and run

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

## 5. Build RN and Hermes from source

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

## 6. Swap in Hermes V1

This builds RN 0.79.5's native side against Hermes V1 (`static_h` branch),
consuming V1 as a Maven prebuilt instead of building Hermes inline. See
`CLAUDE.md` for the high-level rationale. Quick recap of the deltas:

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
  inspector, `setFatalHandler`). We stub or `#ifdef` the affected RN code —
  Chrome devtools / sampling profiler features are sacrificed for now.

You should have already done sections 1, 5a, and 5b above (the `includeBuild`
block in `settings.gradle`, and the `sdkmanager` stub). Section 5c is **not**
needed for V1.

### Two ways to apply the changes

All RN-side modifications are captured as patches under `patches/` in this
repo. You can either **apply the patches** (fast, exactly reproduces the
known-good state) or **walk through the steps manually** (slower, but you'll
understand each change). Both end at the same place.

#### Option A — apply the patches (recommended)

Two patch files cover the entire RN-side modification:

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

Apply, then build:

```bash
cd sample79/node_modules/react-native
patch -p1 -i ../../../patches/01-jsi-vendoring.patch
patch -p1 -i ../../../patches/02-rn-surgery.patch

# Then also do step 6b's sample79/android/settings.gradle edit
# (it's an app-level change, not in the RN-side patches), then build:
cd ../../android
./gradlew --no-daemon assembleDebug
```

Skip ahead to **6i** (build / install / run) once the patches are applied
and the `settings.gradle` substitution is updated. The remainder of section
6 (6a–6h) is the same content presented as manual steps.

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

V1 replaces the old `hermes/inspector/*` headers with `hermes/cdp/*`. RN
0.79's "inspector-modern" code targets the old API and won't compile. The
inspector code is gated on `HERMES_ENABLE_DEBUGGER`, so undefining it makes
the offending code drop out. (Cost: no Chrome devtools debugging until
inspector-modern is rewritten against `hermes/cdp/*`.)

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
      // ICast-based ISetFatalHandler interface; skipped for now.
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

### 6i. Build, install, run

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

## Status

- [x] Project bootstrapped (RN 0.79.5)
- [x] Debug APK builds (prebuilt AARs)
- [x] App runs on emulator against Metro
- [x] RN + Hermes built from source via `includeBuild`
- [x] Hermes V1 swapped in (`com.facebook.hermes:hermes-android`); JS runs on V1
- [ ] Restore Chrome devtools / sampling profiler / fatal handler against V1 APIs
