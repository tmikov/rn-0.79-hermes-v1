# iOS handoff — Hermes V1 on macOS/Xcode

**Nothing in this document has been run.** Everything below was written and
verified from a Linux box (no Xcode, no iOS Simulator, no CocoaPods
toolchain) — file edits, line numbers, and Maven-artifact checks are
grounded in the actual repo contents and in `HEAD` requests against Maven
Central, not in a build. Every "build+run" step is a to-do for the
maintainer on a Mac. Where a fact *was* independently verified without a
build (e.g. a byte-for-byte header diff via the GitHub API, or an HTTP
existence check against Maven Central), that's called out explicitly so
you know which claims are load-bearing and which are still assumptions to
confirm.

## Where things stand

Both worked examples in this repo are validated on **Android** at Hermes
V1 `260318099.0.1`:

- `targets/rn-0.86/` (easy path) — Debug and Release both confirmed on the
  Android emulator.
- `targets/rn-0.79/` (hard path) — Android Debug + Release confirmed on the
  emulator at `260318099.0.1`.

**Target Hermes for iOS is the same `260318099.0.1`**, for consistency
across both targets and both platforms. This document covers two
independent workstreams to get there on iOS, both requiring a Mac:

1. **Workstream 1** — bump `targets/rn-0.79/`'s existing iOS swap
   (currently pinned to `250829098.0.13`, see README §§8–9) to
   `260318099.0.1` and re-validate Debug + Release in the Simulator.
2. **Workstream 2** — bring up `targets/rn-0.86/`'s iOS side at
   `260318099.0.1`, the iOS analog of that target's one-line Android
   version bump.

Background reading, if you haven't: [`hermes-v1-versioning.md`](hermes-v1-versioning.md)
(what Hermes V1 is and how it's versioned) and
[`../targets/rn-0.79/README.md`](../targets/rn-0.79/README.md) §§8–9 (the
existing iOS walkthrough this workstream re-validates).

## Prerequisites (macOS/Xcode)

Same as `targets/rn-0.79/README.md`'s "iOS prerequisites" section: macOS,
Xcode 26.x, the matching iOS Simulator runtime, CocoaPods via Bundler
against system Ruby. Not repeated here — follow that section verbatim
before starting either workstream.

---

## Workstream 1 — `targets/rn-0.79` iOS re-validation at `260318099.0.1`

### 1. Bump the version strings

Two files carry the `250829098.0.13` pin on the iOS side; one edit in
each is functionally required.

**`targets/rn-0.79/patches/05-ios.patch`** — patch line 11, inside the
hunk against `sdks/hermes-engine/hermes-engine.podspec`:

```diff
-version = "250829098.0.13"
+version = "260318099.0.1"
```

This is the only functional change in that patch. It lands as line 26 of
the patched `hermes-engine.podspec` (confirmed against the currently
checked-out, already-patched `sample79/node_modules/react-native/sdks/hermes-engine/hermes-engine.podspec:26`)
and drives both the podspec's own `spec.version` and, downstream, the
`hermes-ios` Maven tarball URL that CocoaPods resolves.

The patch's *second* occurrence of `250829098.0.13` is cosmetic: patch
line 69, inside a `hermes-utils.rb` comment that shows a sample Maven URL
for illustration:

```diff
-    # https://repo1.maven.org/maven2/com/facebook/hermes/hermes-ios/250829098.0.13/hermes-ios-250829098.0.13-hermes-ios-debug.tar.gz
+    # https://repo1.maven.org/maven2/com/facebook/hermes/hermes-ios/260318099.0.1/hermes-ios-260318099.0.1-hermes-ios-debug.tar.gz
```

The actual code two lines below that comment (`release_tarball_url`)
already builds the URL from `#{version}` interpolation, so this comment
is display-only — update it for accuracy, but the tarball URL is correct
either way.

**`targets/rn-0.79/scripts/vendor-hermes-ios.sh`**, line 13:

```diff
-VERSION="250829098.0.13"
+VERSION="260318099.0.1"
```

**Not required for the build, but worth a follow-up pass:**
`targets/rn-0.79/README.md` §§8–9 still narrate `250829098.0.13` in
prose and example output in ~20 places (version strings, tarball
filenames, welcome-screen text, HBC-byte examples). None of it is
consumed by tooling — it's documentation only — so it doesn't block this
workstream, but it should eventually be swept to match once §§8–9 are
re-validated at the new version:

```bash
grep -n '250829098.0.13' targets/rn-0.79/README.md
```

### 2. Re-vendor the hermes-ios tarballs

Both the debug and release `hermes-ios` tarballs for `260318099.0.1`
exist on Maven Central — confirmed with an HTTP HEAD check from this
box:

```
https://repo1.maven.org/maven2/com/facebook/hermes/hermes-ios/260318099.0.1/hermes-ios-260318099.0.1-hermes-ios-debug.tar.gz    → 200
https://repo1.maven.org/maven2/com/facebook/hermes/hermes-ios/260318099.0.1/hermes-ios-260318099.0.1-hermes-ios-release.tar.gz  → 200
```

So the version bump above is sufficient; re-run the vendor script (it's
idempotent and skips files already present, so the stale
`250829098.0.13-*.tar.gz` files can stay alongside):

```bash
cd targets/rn-0.79
../scripts/vendor-hermes-ios.sh
```

Expect `vendor/hermes-ios/hermes-ios-260318099.0.1-debug.tar.gz` and
`hermes-ios-260318099.0.1-release.tar.gz` (NOT RUN HERE — the script
needs network access this sandbox has, but the resulting `.app` needs
Xcode/Simulator this sandbox doesn't have).

### 3. Debug: pod install, build, run — NOT RUN HERE

Mirrors README §8d/§8e with the new tarball name:

```bash
cd sample79/ios
HERMES_ENGINE_TARBALL_PATH=$PWD/../../vendor/hermes-ios/hermes-ios-260318099.0.1-debug.tar.gz \
  bundle exec pod install

xcodebuild -workspace sample79.xcworkspace -scheme sample79 \
  -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  build
```

Verify the V1 framework landed in the built `.app` (same checks as
README §8e, still expected to hold — only the version number inside the
binary changes):

```bash
APP=~/Library/Developer/Xcode/DerivedData/sample79-*/Build/Products/Debug-iphonesimulator/sample79.app
ls $APP/Frameworks/
# expect: hermesvm.framework   (the V1 rename; NOT hermes.framework)

otool -l $APP/Frameworks/hermesvm.framework/hermesvm | grep "name @"
# expect: name @rpath/hermesvm.framework/hermesvm
```

Install, start Metro, launch (same as README §8e), then confirm the
welcome screen now reads **Engine: Hermes 260318099.0.1** (was
`250829098.0.13`).

### 4. Release: pod install, build, run — NOT RUN HERE

```bash
cd sample79/ios
HERMES_ENGINE_TARBALL_PATH=$PWD/../../vendor/hermes-ios/hermes-ios-260318099.0.1-release.tar.gz \
  bundle exec pod install

xcodebuild -workspace sample79.xcworkspace -scheme sample79 \
  -configuration Release -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  build
```

**HBC-match requirement (the same trap the Android re-validation hit):**
`260318099.0.1`'s `libhermesvm`/`hermesvm.framework` expects **HBC v99**,
not the v98 that `250829098.0.13` needed. README §9's iOS Release path
relies on the vendored tarball's *own* bundled host `hermesc` at
`destroot/bin/hermesc` (no `hermes-compiler` npm install, unlike
Android) — that only works here if the freshly-vendored
`260318099.0.1` tarball's `hermesc` itself emits v99. It almost
certainly does, since it's built from the same release tag as the VM,
but **verify it rather than assume it**, the same way Android's stock
hermesc turned out to emit the wrong version for its VM:

```bash
echo "console.log('hi');" | \
  sample79/ios/Pods/hermes-engine/destroot/bin/hermesc \
  -emit-binary -out /tmp/test.hbc /dev/stdin
xxd -l 16 /tmp/test.hbc
# expect byte 8 == 63 (hex) == 99 (decimal). If it's still 62 (98),
# the vendored hermesc is stale/mismatched — needs investigation before
# trusting the baked bundle.
```

Then verify the actual baked bundle in the built app:

```bash
xxd -l 16 $APP/main.jsbundle
# expect: c6 1f bc 03 c1 03 19 1f 63 ...   <- byte 8 = 0x63 = HBC v99
```

Install (uninstall any Debug build first — different keystore/signing
state), kill Metro, launch, and confirm **Engine: Hermes 260318099.0.1**
with no Metro running (same as README §9b).

### 5. JSI — no re-vendor needed for this bump

Verified directly (not assumed): `API/jsi/jsi/jsi.h` is **byte-identical**
between `hermes-v250829098.0.13` and `hermes-v260318099.0.1` on
`facebook/hermes`:

```bash
diff \
  <(gh api "repos/facebook/hermes/contents/API/jsi/jsi/jsi.h?ref=hermes-v250829098.0.13" --jq '.content' | base64 -d) \
  <(gh api "repos/facebook/hermes/contents/API/jsi/jsi/jsi.h?ref=hermes-v260318099.0.1" --jq '.content' | base64 -d)
# => (empty)
```

So `patches/01-jsi-vendoring.patch` (the wholesale JSI replacement) does
**not** need to be regenerated for this bump — only the two version
strings above need to change. This is the same "JSI-ABI ceiling" check
documented in [`hermes-v1-versioning.md`](hermes-v1-versioning.md); it
happens to come back clean here because both versions sit on the same
`static_h` line the JSI vendoring already targets.

---

## Workstream 2 — `targets/rn-0.86` iOS bring-up at `260318099.0.1`

RN 0.86 already consumes `hermes-ios` V1 by default, so this is a version
override, not a framework rename or podspec surgery (there is no
`05-ios`/`06-ios-app-side`-equivalent patch needed for this target).

### 1. Where the version is set — same file drives both platforms

`sample86/node_modules/react-native/sdks/hermes-engine/hermes-engine.podspec`
(unpatched, native RN 0.86 code) reads its `spec.version` — the value
that ultimately selects which `hermes-ios` Maven tarball CocoaPods
downloads — from the **same** `version.properties` file that already
backs the Android bump:

```ruby
# hermes-engine.podspec, lines 22-29
package = JSON.parse(File.read(File.join(react_native_path, "package.json")))
versionProperties = Hash[*File.read("version.properties").split(/[=\n]+/)]

if ENV['RCT_HERMES_V1_ENABLED'] == "0"
  version = versionProperties['HERMES_VERSION_NAME']
else
  version = versionProperties['HERMES_V1_VERSION_NAME']
end
```

and `hermes-utils.rb`'s `release_tarball_url` builds the `hermes-ios`
download URL from that same `version` (`com/facebook/hermes/hermes-ios/#{version}/...`).

**Practical consequence:** the Android-side one-line bump this target
already made —

```
node_modules/react-native/sdks/hermes-engine/version.properties
 HERMES_VERSION_NAME=0.17.0
-HERMES_V1_VERSION_NAME=250829098.0.14
+HERMES_V1_VERSION_NAME=260318099.0.1
```

— committed as `targets/rn-0.86/patches/01-hermes-v1-bump.patch` and
already applied in the checked-out `sample86/` tree, **is also the iOS
override**. There is nothing additional to edit in the `Podfile` or any
podspec for the version bump itself; `pod install` alone will pick up
the new version on the iOS side once that patch is applied (it already
is, in this checkout).

### 2. `pod install` — expected to auto-download, no local tarball needed

Unlike `targets/rn-0.79` (which pins a `HERMES_ENGINE_TARBALL_PATH` to a
manually-vendored tarball), `sample86/ios/Podfile` sets no such override,
so CocoaPods falls through to `hermes_source_type`'s default: if a
release tarball exists on Maven for the resolved version, it downloads
it automatically (`DOWNLOAD_PREBUILD_RELEASE_TARBALL`). Both the debug
and release `hermes-ios` tarballs for `260318099.0.1` were confirmed to
exist on Maven Central (HTTP 200, same check as Workstream 1 above), so
a single `pod install` should fetch both, and the podspec's own
`script_phase` (`hermes-engine.podspec` lines ~106-121, "Replace Hermes
for the right configuration, if needed") swaps between them per Xcode
build configuration automatically — **no need to re-run `pod install`
between Debug and Release builds**, unlike the `targets/rn-0.79` flow.

```bash
cd sample86/ios
bundle exec pod install   # sample86 has a Gemfile too; verify `bundle exec pod --version` first
```

(NOT RUN HERE — needs the CocoaPods/Xcode toolchain.)

### 3. Debug build — NOT RUN HERE

```bash
xcodebuild -workspace sample86.xcworkspace -scheme sample86 \
  -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  build
```

Expected to be a **clean pure override** — RN 0.86's bundled JSI ABI
already matches `260318099.0.1` on Android (RN 0.86's
`ReactCommon/jsi/jsi/jsi.h` is byte-identical to
`hermes-v260318099.0.1`'s `API/jsi/jsi/jsi.h`), and iOS shares the same
`node_modules/react-native/ReactCommon/jsi/jsi/` tree, so the same "no
JSI re-vendor" conclusion should carry over unchanged. Verify:

```bash
APP=~/Library/Developer/Xcode/DerivedData/sample86-*/Build/Products/Debug-iphonesimulator/sample86.app
ls $APP/Frameworks/
# expect: hermesvm.framework

otool -l $APP/Frameworks/hermesvm.framework/hermesvm | grep "name @"
# expect: name @rpath/hermesvm.framework/hermesvm
```

Install/launch (bundle id `org.reactjs.native.example.sample86`, same
pattern as `targets/rn-0.79`), and check the welcome screen reads
`JS Engine: Hermes (260318099.0.1)`.

### 4. Release build — verify, don't assume, which hermesc runs

This is the one open question this workstream needs the Mac to settle.
Reading `hermes-engine.podspec` closely: the `HERMES_CLI_PATH` used to
compile the JS bundle is **not always** the vendored tarball's own
`destroot/bin/hermesc`. It depends on `source_type`:

- If CocoaPods used a **local tarball override**
  (`HERMES_ENGINE_TARBALL_PATH`, `targets/rn-0.79`'s approach), no
  `user_target_xcconfig` override is set, and RN's
  `react-native-xcode.sh` falls back to the tarball's own
  `destroot/bin/hermesc` by default.
- If CocoaPods **auto-downloaded** the release tarball (the expected
  path for `targets/rn-0.86`, per step 2 above — `source_type !=
  LOCAL_PREBUILT_TARBALL`), `hermes-engine.podspec` (lines ~90-98)
  instead points `HERMES_CLI_PATH` at
  `<hermes-compiler npm package>/hermesc/osx-bin/hermesc`, resolved via
  Node's `require.resolve("hermes-compiler")` — i.e. the **npm package
  hermesc, not the tarball's hermesc**.

That means the Android fix already committed in `sample86/package.json`:

```json
"overrides": { "hermes-compiler": "260318099.0.1" }
```

(confirmed installed: `node_modules/hermes-compiler/package.json` shows
`"version": "260318099.0.1"`, and it ships an `osx-bin/` alongside
`linux64-bin/` and `win64-bin/`) is very likely **also the fix for iOS
Release** on this target — no additional pinning should be needed. But
this is a code-reading inference, not something built and observed, so
treat it as a hypothesis to confirm on the Mac, not a given:

```bash
cd sample86
npm install                                    # picks up the override if not already applied

cd ios
xcodebuild -workspace sample86.xcworkspace -scheme sample86 \
  -configuration Release -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  build

APP=~/Library/Developer/Xcode/DerivedData/sample86-*/Build/Products/Release-iphonesimulator/sample86.app
xxd -l 16 $APP/main.jsbundle
# expect: byte 8 == 63 (hex) == 99 (decimal) = HBC v99.
# If it's 62 (98) instead, the build picked up a stale/mismatched
# hermesc — check which HERMES_CLI_PATH the build log actually used.
```

Install/launch with Metro killed, confirm `JS Engine: Hermes
(260318099.0.1)` with the baked bundle.

---

## Verification checklist (both workstreams)

| Check | Command | Expect |
|---|---|---|
| V1 framework present | `ls $APP/Frameworks/` | `hermesvm.framework` (not `hermes.framework`) |
| Install-name is V1 | `otool -l $APP/Frameworks/hermesvm.framework/hermesvm \| grep "name @"` | `name @rpath/hermesvm.framework/hermesvm` |
| Release HBC version | `xxd -l 16 $APP/main.jsbundle` | byte 8 = `63` (hex) = v99 |
| On-screen engine version | welcome screen | `Hermes (260318099.0.1)` / `Engine: Hermes 260318099.0.1` |

## What was NOT done here (Mac-only, still to do)

- Everything under "Re-vendor" / "pod install" / "build" / "run" /
  "install" / "launch" in both workstreams above — this box has no
  Xcode, no iOS Simulator runtime, and no CocoaPods toolchain.
- Confirming the vendored `260318099.0.1` iOS tarball's bundled
  `hermesc` actually emits HBC v99 (Workstream 1, step 4) — only its
  *existence* on Maven was checked, not its contents.
- Confirming whether `targets/rn-0.86`'s iOS Release build needs the
  `hermes-compiler` npm override at all, or picks the right `hermesc` by
  some other path not visible from reading the podspec alone
  (Workstream 2, step 4).
- Regenerating `targets/rn-0.79/patches/05-ios.patch` /
  `06-ios-app-side.patch` against the bumped tree and re-diffing, once
  the manual edits above are applied and confirmed working.
- The `targets/rn-0.79/README.md` §§8–9 prose sweep for the ~20 stale
  `250829098.0.13` mentions once the version bump above is confirmed
  working end to end.

What *was* independently verified without a build, and can be trusted as
given: the Maven existence of both `260318099.0.1` `hermes-ios` tarballs
(debug + release), and the byte-identical `jsi.h` between
`hermes-v250829098.0.13` and `hermes-v260318099.0.1` (Workstream 1) —
both checked live against GitHub/Maven from this box.
