# Project context

## Goal

This repo teaches how to get a React Native app running on **current
Hermes V1** (the `facebook/hermes` `static_h` line), regardless of which RN
version you start from. How much surgery that takes depends on how old the
RN checkout is — that's the whole reason this is a guide and not a single
patch. Two worked examples, both landing on the same target build
`com.facebook.hermes:hermes-android:260318099.0.1`:

- **`targets/rn-0.79/`** — hard path. RN 0.79.5 predates V1 entirely (no
  `.hermesv1version` file), so it needs full surgery: vendored JSI,
  retargeted CMake, swapped Maven group, a CDP adapter shim. This is the
  original scope of this repo and the most-developed example; the rest of
  this file (below "Where things live") documents that hard path in detail.
- **`targets/rn-0.86/`** — easy path. RN 0.86 already consumes V1 by
  default; getting onto a newer `static_h` stable is close to just an
  artifact-version bump.

RN's own pin for which V1 build it consumes lives at
`packages/react-native/sdks/.hermesv1version` — see
`docs/hermes-v1-versioning.md` for the full versioning story, including the
trap of confusing that file with the unrelated legacy `.hermesversion` pin.

## Where things live

- `targets/rn-0.79/`, `targets/rn-0.86/` — the worked examples, each with
  its own README covering setup and build instructions for that target.
- `docs/hermes-v1-versioning.md` — canonical reference for what Hermes V1
  is and how it's versioned.
- `docs/choosing-the-path.md` — decision tree for classifying any RN
  checkout into easy/medium/hard.
- `docs/cdp-adapter.md` — design notes for the CDP (Chrome DevTools) shim
  used by the hard path.
- `docs/ios-handoff.md` — the Mac-side runbook for iOS bring-up on
  `260318099.0.1` (both targets). Not linked from the reader-facing
  READMEs on purpose: it's a maintainer to-do, not user documentation.
  Whoever picks up the iOS work starts here.
- Root `README.md` — short landing page; this file is deeper project
  context, scoped mostly to the hard path (`rn-0.79`) below.

## Hard path (`targets/rn-0.79`): why this is non-trivial

RN 0.79 was built before Hermes split off as a standalone artifact, so its
Gradle/CMake setup deeply integrates the Hermes build:

- `:packages:react-native:ReactAndroid:hermes-engine` builds Hermes inline
  during the RN build, producing `libhermes.so` next to `libreactnative.so`.
- Headers, hermesc, and the `.so` are all sourced from
  `node_modules/react-native/sdks/hermes/`.
- `libreactnative.so` is compiled against those exact JSI headers.

Hermes V1 changed both: it builds independently of RN, and **the library
itself is renamed**. Newer RN versions (like `rn-0.86`) adopted this cleaner
model; RN 0.79 did not. The integration shims we need to write live
entirely on the RN side — the Hermes side is just a library + headers.

## Strategy (hard path)

Start with the **Hermes V1 prebuilts** rather than building Hermes from
source. The hard work (rewiring RN 0.79's build to consume a renamed library
+ different JSI headers) is the same either way; building Hermes ourselves
just adds a multi-ABI cross-compile per iteration. Switch to a source build
only if we need to patch Hermes.

Note: hermesc isn't needed for debug builds — they get JS from Metro at
runtime. It's needed (the prebuilt host hermesc, or the `hermes-compiler`
npm package) before building a release APK.

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

## Hermes V1 facts (gathered 2026-05-07; version pin updated 2026-07-25)

- Maven: `com.facebook.hermes:hermes-android:260318099.0.1` — the target
  version for both worked examples in this repo (note the group is
  `com.facebook.hermes`, not `com.facebook.react`).
  - Old Hermes lives at `com.facebook.react:hermes-android:<RN-version>`
    and is versioned alongside RN.
  - V1 versions follow `<YYMMDDxxx>.0.N`. Classifiers: `debug`,
    `debugOptimized`, `release`.
  - RN pins the V1 build it consumes in
    `packages/react-native/sdks/.hermesv1version`; absence of that file
    means the checkout predates V1 (hard path). See
    `docs/hermes-v1-versioning.md` for the full versioning story.
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

## RN-side surgery checklist (hard path — rn-0.79)

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
   `hermes-android`, e.g. `260318099.0.1`) and point RN's gradle
   plugin at it via `react.hermesCommand` in `app/build.gradle`. RN
   0.79's bundled hermesc emits HBC v96; V1 needs v98.
