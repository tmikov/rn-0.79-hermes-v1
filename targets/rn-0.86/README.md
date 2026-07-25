# RN 0.86 — the easy path

RN 0.86.0 (`sample86/`, app id `com.sample86`) already consumes **Hermes
V1** (`static_h`) out of the box — no JSI vendoring, no CMake surgery, no
Maven-group swap. Getting it onto the *current* V1 stable
(`260318099.0.1`, one stable branch newer than RN 0.86's own
`250829098.0.14`) is close to a pure version bump. This is the "easy
path" referenced from the root [`README.md`](../../README.md) and
[`docs/choosing-the-path.md`](../../docs/choosing-the-path.md).

Read [`docs/hermes-v1-versioning.md`](../../docs/hermes-v1-versioning.md)
first if you haven't — it explains what Hermes V1 is and how it's
versioned. This README assumes that background.

## The swap

RN's Gradle plugin force-resolves
`com.facebook.hermes:hermes-android:<version>` from a single property:

```
node_modules/react-native/sdks/hermes-engine/version.properties
```

**Debug swap = one line** in that file:

```diff
 HERMES_VERSION_NAME=0.17.0
-HERMES_V1_VERSION_NAME=250829098.0.14
+HERMES_V1_VERSION_NAME=260318099.0.1
```

That's it — no re-vendored JSI. RN 0.86's bundled
`ReactCommon/jsi/jsi/jsi.h` is byte-identical to
`hermes-v260318099.0.1`'s `API/jsi/jsi/jsi.h`, so the JSI ABI RN already
ships already covers everything `260318099.0.1`'s `libhermesvm.so`
needs. (This is *not* true one RN version back — see "Why RN 0.86 and
not 0.85?" below.)

The one-line edit is captured as
[`patches/01-hermes-v1-bump.patch`](patches/01-hermes-v1-bump.patch),
applied by [`scripts/apply-patches.sh`](scripts/apply-patches.sh) — the
same marker-gated, idempotent pattern `targets/rn-0.79` uses. Re-running
the script after it's already applied is a no-op; delete
`sample86/node_modules/react-native/.hermes-v1-patches-applied` (or
just `rm -rf node_modules && npm install`) to force re-application.

## Prerequisites

Reuses the same Android environment as `targets/rn-0.79`:

- **NDK 27.1.12297006** and CMake 3.22.1 (Android Studio / `sdkmanager`
  will auto-install these on first build if missing).
- **JDK 17.**
- An **x86_64 emulator image** (e.g. an `android-36` x86_64 AVD). All
  builds in this walkthrough used `-PreactNativeArchitectures=x86_64`
  (already the default in `sample86/android/gradle.properties` as a
  commented example) to keep the native compile to one ABI for speed —
  drop it for a fat multi-ABI APK. On Linux, the x86_64 emulator needs
  KVM; if your user isn't in the `kvm` group in the current shell,
  launch it via `sg kvm -c 'emulator -avd <name> ...'`.

```bash
export JAVA_HOME=/path/to/temurin-17
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_HOME="$HOME/Android/Sdk"      # or ~/Library/Android/sdk on macOS
export PATH="$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$PATH"
```

## Debug build and run

```bash
cd sample86
npm install
../scripts/apply-patches.sh

cd android
./gradlew --no-daemon assembleDebug -PreactNativeArchitectures=x86_64
```

Boot the emulator and launch:

```bash
emulator -avd <your-x86_64-avd> &
adb install -r app/build/outputs/apk/debug/app-debug.apk

cd ..                                        # back to sample86/
npx react-native start &                     # Metro
adb reverse tcp:8081 tcp:8081
adb shell am start -n com.sample86/.MainActivity
```

**On-screen proof:** the welcome screen reads:

```
Version: 0.86.0
JS Engine: Hermes (260318099.0.1)
```

confirming the app is running against the newer stable, not the
`250829098.0.14` RN 0.86 ships by default.

## Release build

Debug builds get JS from Metro, so they never touch the bytecode
compiler. Release builds bake a precompiled HBC (Hermes Bytecode)
bundle into the APK, and that's where a pure artifact bump isn't quite
enough on its own.

- The `260318099.0.1` VM expects **HBC v99**.
- RN 0.86's stock `hermes-compiler` npm package (`250829098.0.14`)
  emits **HBC v98**.
- Shipping a v98 bundle to a v99 VM fails at runtime:
  `HermesVM: Compiling JS failed: Wrong bytecode version. Expected 99
  but got 98`.

The fix is an **npm override**, already committed in
`sample86/package.json`:

```json
"overrides": {
  "hermes-compiler": "260318099.0.1"
}
```

RN's Gradle plugin picks up `hermesc` from
`node_modules/hermes-compiler/hermesc/%OS-BIN%/hermesc` by default when
no explicit `hermesCommand` is set — so pinning the npm package is the
whole fix; there's no `app/build.gradle` edit to make (unlike the
`targets/rn-0.79` hard path, which has to point `hermesCommand` at a
manually-installed `hermes-compiler`).

```bash
cd sample86
npm install                                   # picks up the override
```

**Clean-rebuild caveat:** the JS-bundle task caches its output keyed on
inputs that don't include "which hermesc binary is on disk," so a plain
`assembleRelease` after swapping `hermes-compiler` can silently reuse a
stale v98 bundle. Force a clean rebuild:

```bash
cd android
./gradlew clean
./gradlew --no-daemon assembleRelease -PreactNativeArchitectures=x86_64
```

The release build type uses the debug signing config here, so
`assembleRelease` produces a directly-installable APK:

```bash
adb uninstall com.sample86                    # if a debug build is installed
adb install app/build/outputs/apk/release/app-release.apk
adb shell am start -n com.sample86/.MainActivity
```

No Metro needed. Verify the baked bundle is v99 (byte 8 of an HBC file
is the bytecode version):

```bash
unzip -p app/build/outputs/apk/release/app-release.apk \
  assets/index.android.bundle | xxd -l 16
# expect: c6 1f bc 03 c1 03 19 1f 63 ...   <- byte 8 = 0x63 = HBC v99
```

and watch for `ReactNativeJS: Running "sample86"` in logcat with no
Metro running.

## Verification one-liners

```bash
# Engine lib present is the V1 one, not the legacy one.
unzip -l <apk> | grep -E 'libhermes'
# expect: libhermesvm.so present, NO libhermes.so

# Resolved Maven artifact.
./gradlew :app:dependencies --configuration debugRuntimeClasspath | grep hermes-android
# expect: com.facebook.hermes:hermes-android:260318099.0.1

# Release HBC version (byte 8 of the baked bundle).
unzip -p <release-apk> assets/index.android.bundle | xxd | head -1
# byte 8 = 63 (hex) = 99 (decimal) for 260318099.0.1

# On-screen: welcome screen prints "JS Engine: Hermes (260318099.0.1)"
```

## Why RN 0.86 and not 0.85?

This target used to be built on RN 0.85, and the reason it moved is the
headline finding of this whole repo's easy-path story, not a footnote:
**an artifact bump only stays "easy" if the RN prebuilt's JSI ABI
already exports every symbol the newer Hermes needs.**

The V1 Hermes AAR **ships no JSI at all**. On Android, JSI comes
entirely from RN's own prebuilt `libjsi.so` (baked into
`libreactnative.so`). `libhermesvm.so` is linked against — and at
`dlopen` time resolves symbols against — whatever JSI RN happened to
bundle. If the target Hermes references a JSI symbol RN's prebuilt
doesn't define, the bump *builds* fine and then **crashes at load
time**.

That's exactly what happens on RN 0.85:

- `jsi::Runtime::isTypedArray(const jsi::Object&)` entered JSI at
  static_h **`250829098.0.11`**.
- **RN 0.85 pins `250829098.0.10`** — the one stable patch *before*
  that symbol existed. Its prebuilt `libjsi.so` doesn't define
  `isTypedArray`.
- Bumping RN 0.85 to `260318099.0.1` (or any `.0.11`+) builds cleanly,
  then fails at startup:
  `dlopen: cannot locate symbol jsi::Runtime::isTypedArray(const
  jsi::Object&) referenced by libhermesvm.so`.
- Reaching current V1 on RN 0.85 for real means re-vendoring JSI and
  rebuilding RN's native libs from source — i.e., falling back to the
  `targets/rn-0.79` hard path's JSI-vendoring step, on a checkout that
  otherwise looked "easy."

**RN 0.86 pins `250829098.0.14`**, which already has `isTypedArray` (and
everything else `260318099.0.1` needs), so the pure bump links and runs
clean. That's the entire reason this worked example moved from 0.85 to
0.86.

**Before you bump on any RN checkout**, check whether you're on the
easy side of that line: diff the RN checkout's bundled
`node_modules/react-native/ReactCommon/jsi/jsi/jsi.h` against the
target Hermes tag's `API/jsi/jsi/jsi.h` (`hermes-v<target-version>` on
`facebook/hermes`). Identical (or a strict superset) → the pure bump is
safe. Missing symbols the target added → you're on the hard path for
JSI, regardless of how new your RN is otherwise.

See [`docs/hermes-v1-versioning.md`](../../docs/hermes-v1-versioning.md)
for the full versioning background, including where this ceiling is
documented as its own subsection.

## iOS

Not built or tested here — this work ran on a Linux server, and iOS builds
only on a Mac. iOS bring-up for this target is sketched but unvalidated.
