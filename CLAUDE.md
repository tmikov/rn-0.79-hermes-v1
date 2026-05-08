# Project context

## Goal

Get RN 0.79.5's Android app running on **Hermes V1** instead of the Hermes
that RN 0.79 ships with. We're using a stock `sample79/` app as the host
(see README for setup and build instructions).

## Why this is non-trivial

RN 0.79 was built before Hermes split off as a standalone artifact, so its
Gradle/CMake setup deeply integrates the Hermes build:

- `:packages:react-native:ReactAndroid:hermes-engine` builds Hermes inline
  during the RN build, producing `libhermes.so` next to `libreactnative.so`.
- Headers, hermesc, and the `.so` are all sourced from
  `node_modules/react-native/sdks/hermes/`.
- `libreactnative.so` is compiled against those exact JSI headers.

Hermes V1 changed both: it builds independently of RN, and **the library
itself is renamed**. Newer RN versions adopted this cleaner model; RN 0.79
did not. The integration shims we'll need to write live entirely on the RN
side — the Hermes side is just a library + headers.

## Strategy

Start with the **Hermes V1 prebuilts** rather than building Hermes from
source. The hard work (rewiring RN 0.79's build to consume a renamed library
+ different JSI headers) is the same either way; building Hermes ourselves
just adds a multi-ABI cross-compile per iteration. Switch to a source build
only if we need to patch Hermes.

Note: hermesc isn't needed yet — debug builds get JS from Metro at runtime.
We'll need it (or the prebuilt host hermesc) before we can build a release
APK.

## Known risks

- **C++ ABI / toolchain skew.** The Hermes V1 prebuilts may have been built
  with a different NDK / libc++ / compiler flags than our RN build uses.
  Symbol mangling, libc++ version, exception handling, etc. can mismatch in
  subtle ways. Hoping for the best; if we see weird link or runtime errors,
  this is the first place to look.
  - Mostly de-risked: V1 prefab `abi.json` reports NDK 27, API 24,
    `c++_shared` — matches RN 0.79's NDK 27.1.12297006 and STL choice.
- **JSI evolution.** JSI is source-stable, not ABI-stable, and newer Hermes
  takes hard dependencies on newer JSI features. We can't keep RN 0.79's
  old JSI headers — we have to vendor in the JSI that Hermes V1 expects and
  rebuild `libreactnative.so` against it. This is the main RN-side surgery.

## Hermes V1 facts (gathered 2026-05-07)

- Maven: `com.facebook.hermes:hermes-android:250829098.0.13` (note the
  group is `com.facebook.hermes`, not `com.facebook.react`).
  - Old Hermes lives at `com.facebook.react:hermes-android:<RN-version>`
    and is versioned alongside RN.
  - V1 versions follow `<YYMMDDxxx>.0.N`. Classifiers: `debug`,
    `debugOptimized`, `release`.
- Source: `facebook/hermes` branch **`static_h`**.
- **Library renamed** `libhermes.so` → `libhermesvm.so`.
- **Prefab package name unchanged** (`hermes-engine`), so
  `find_package(hermes-engine REQUIRED)` keeps working. The module rename
  hits CMake `target_link_libraries`:
  `hermes-engine::libhermes` → `hermes-engine::hermesvm`.
- **JSI lives in the Hermes repo now**: `static_h:API/jsi/jsi/`. Same
  filenames as RN's `ReactCommon/jsi/jsi/`, plus an extra
  `hermes-interfaces.h`. New JSI types V1 depends on: `jsi::ICast`,
  `jsi::UUID`. RN 0.79's JSI has neither.
- The V1 AAR ships **only Hermes headers** (`prefab/.../include/hermes/`,
  `hermes_abi/`, `hermes_sandbox/`) — **no JSI**. The consumer must
  provide JSI matching what V1 was built against.
- Hermes V1 still depends on `com.facebook.fbjni:fbjni:0.7.0`.

## RN-side surgery checklist (rough)

1. Replace `node_modules/react-native/ReactCommon/jsi/jsi/*` with the
   `static_h:API/jsi/jsi/*` versions (drop-in: same files + new
   `hermes-interfaces.h`).
2. Rip out the `:packages:react-native:ReactAndroid:hermes-engine`
   subproject (or stub it) and substitute the V1 Maven artifact in
   `settings.gradle`.
3. In RN's CMake, retarget `hermes-engine::libhermes` →
   `hermes-engine::hermesvm`.
4. Audit any RN C++ that includes Hermes-specific headers
   (`HermesRuntime`, `DebuggerAPI`, `CDPAgent`, etc.) — header names look
   the same but the contents may have shifted between RN 0.79's pinned
   Hermes (`hermes-2025-06-04-RNv0.79.3-7f9a871e...`) and `static_h`.
5. hermesc: not needed for debug/Metro. For release, install the
   `hermes-compiler` npm package (versioned in lockstep with
   `hermes-android`, e.g. `250829098.0.13`) and point RN's gradle
   plugin at it via `react.hermesCommand` in `app/build.gradle`. RN
   0.79's bundled hermesc emits HBC v96; V1 needs v98.
