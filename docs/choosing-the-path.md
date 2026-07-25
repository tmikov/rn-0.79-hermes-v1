# Choosing your path

Every React Native checkout consumes Hermes differently depending on its
version, and that determines how much surgery you need to do to get onto
current Hermes V1. This doc is a short flow to classify *your* checkout and
point you at the right worked example. For the facts behind the
classification (what Hermes V1 is, how it's versioned, the trap of confusing
it with the legacy `.hermesversion` pin), see
[`docs/hermes-v1-versioning.md`](hermes-v1-versioning.md) — this doc doesn't
restate that, it just tells you which row you're in.

## Step 1: classify your checkout

Run this in your RN checkout:

```bash
cat node_modules/react-native/sdks/.hermesv1version 2>/dev/null || echo "pre-V1 (no .hermesv1version) — hard path"
```

- **File missing** → your RN predates V1 entirely (RN ≤ 0.81). Hard path.
- **File present, contents a raw commit SHA** → V1 opt-in, source-build only
  (RN 0.82). Medium path.
- **File present, contents a `hermes-v<date-version>` tag** → V1 is at least
  available as a prebuilt (RN ≥ 0.83); whether it's the *default* engine or
  still opt-in depends on the exact version — see the table below.

## Step 2: pick your effort level

| RN version | Consumes | Effort | Worked example |
|---|---|---|---|
| ≥ 0.84, JSI ABI covers the target | V1 by default (`com.facebook.hermes`, `250829098.x`) | Easy — override artifact to a newer static_h stable; re-vendor JSI + matching hermesc only if required | `targets/rn-0.86` |
| 0.82–0.83, or ≥ 0.84 with an insufficient JSI ABI | V1 opt-in / source-build, or V1-by-default but blocked on JSI | Medium-to-hard — see caveat below | documented, not built |
| ≤ 0.81 | old inline `libhermes.so` (`com.facebook.react`) | Hard — vendor static_h JSI, CMake `libhermes`→`hermesvm`, swap Maven group, CDP shim | `targets/rn-0.79` |

**"RN ≥ 0.84 = Easy" has a condition attached, not a given.** The V1
Hermes AAR ships no JSI — on Android, the JSI a Hermes build links
against comes from *RN's own prebuilt* `libjsi.so`. A pure artifact bump
only stays easy when that prebuilt already exports every JSI symbol the
newer Hermes references. If the target Hermes added `jsi::Runtime`
methods since the JSI your RN bundles, the bump builds fine and then
fails at `dlopen` time — and fixing it means re-vendoring JSI and
rebuilding RN's native libs from source, i.e. the hard path's JSI step,
regardless of how new your RN otherwise is.

**The concrete check, before you bump:** diff your RN checkout's bundled

```
node_modules/react-native/ReactCommon/jsi/jsi/jsi.h
```

against the target Hermes tag's

```
API/jsi/jsi/jsi.h    (facebook/hermes, tag hermes-v<target-version>)
```

Identical (or a strict superset) → the pure bump is safe, you're on the
easy path. Missing methods the target added → degrade to the hard path
for JSI. RN 0.85 vs. RN 0.86 is the concrete boundary case: RN 0.85
pins a JSI one patch too old (missing `jsi::Runtime::isTypedArray`) and
hits this wall; RN 0.86 doesn't. Full story in
[`docs/hermes-v1-versioning.md`](hermes-v1-versioning.md#the-jsi-abi-ceiling-why-a-pure-bump-isnt-always-safe).

## Where to go next

- **Easy** (RN ≥ 0.84, JSI ABI check above passes): go to
  [`targets/rn-0.86/`](../targets/rn-0.86/) — overriding the Maven
  artifact version is close to the whole job.
- **Medium** (RN 0.82–0.83, or RN ≥ 0.84 stuck behind the JSI-ABI
  ceiling): not built out in this repo yet. The shape of the work sits
  between the other two rows: V1 is reachable, but you may still be
  source-building it, opting into it explicitly, or re-vendoring JSI
  rather than getting a clean prebuilt bump. Expect a mix of the "easy"
  override and a slice of the "hard" path's JSI-vendoring concerns.
- **Hard** (RN ≤ 0.81): go to [`targets/rn-0.79/`](../targets/rn-0.79/) —
  this is the full surgery: vendoring JSI, retargeting CMake, swapping the
  Maven group, and (if you need Chrome DevTools) the
  [CDP adapter shim](cdp-adapter.md).
