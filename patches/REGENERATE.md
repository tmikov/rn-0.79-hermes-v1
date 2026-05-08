# Regenerating the patches

Both patches in this directory describe the diff between **pristine RN
0.79.5 from npm** and our **modified `node_modules/react-native/`** in
`sample79/`. Regenerate when:

- you bump the Hermes V1 AAR version (must re-vendor JSI from the matching
  `hermes-v<aar-version>` tag — see "JSI tag pinning" below);
- you re-vendor JSI for any other reason;
- you edit anything in the modified `node_modules/react-native/` tree.

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

Applying both patches to a pristine copy must reproduce the modified tree
exactly:

```bash
TMP=$(mktemp -d) && cp -R "$PRISTINE" "$TMP/rn"
( cd "$TMP/rn" && patch -p1 -i "$PATCHDIR/01-jsi-vendoring.patch" \
                && patch -p1 -i "$PATCHDIR/02-rn-surgery.patch" )
diff -ruN -x .gradle -x sdks -x .cxx -x build -x node_modules \
  "$TMP/rn" "$MODIFIED" | wc -l    # must be 0
rm -rf "$TMP"
```

## What's *not* in the patches

The patches only cover `node_modules/react-native/`. Two changes live
elsewhere and have to be applied separately:

- `sample79/android/settings.gradle` — the `dependencySubstitution` block
  (covered in README §6b). This is in the app, not RN.
- The `sdkmanager` stub at `$ANDROID_HOME/cmdline-tools/latest/bin/`
  (covered in README §5b). Filesystem-level, not in any source tree.
