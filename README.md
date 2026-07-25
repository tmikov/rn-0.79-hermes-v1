# Running React Native on current Hermes V1

This repo is a guide, with worked examples, for getting a React Native app
onto a **current** build of Hermes V1 — regardless of which RN version
you're starting from. How much work that takes depends entirely on how old
your RN is: a recent RN already consumes V1 by default and it's mostly a
version bump; an older RN predates V1 and needs real surgery. Both cases are
built out here end to end, on Android.

## The mental model

Hermes V1 is the `facebook/hermes` **`static_h`** line — Hermes built and
versioned independently of React Native, rather than compiled inline as
part of the RN build. A given RN checkout records exactly which V1 build it
pins in `packages/react-native/sdks/.hermesv1version`; if that file doesn't
exist, the checkout predates V1 entirely. See
[`docs/hermes-v1-versioning.md`](docs/hermes-v1-versioning.md) for the full
explanation, including the trap of confusing this with the similarly-named
(but unrelated) legacy `.hermesversion` pin.

## Which path is yours?

| RN version | Consumes | Effort |
|---|---|---|
| ≥ 0.84 | V1 by default (`com.facebook.hermes`) | Usually just a version bump — but ABI-gated; see the catch below |
| 0.82–0.83 | V1 opt-in / source-build | Medium |
| ≤ 0.81 | legacy inline `libhermes.so` (`com.facebook.react`) | Hard — vendor JSI, retarget CMake, swap Maven group |

**The catch — "≥ 0.84 = easy" is not a given.** JSI is designed to grow
*without* breaking its ABI: new capabilities are added as **optional
interfaces** you query for at runtime, so they leave the core vtable
untouched. The ABI breaks only when a **primary** interface — `jsi::Runtime`
itself — is changed, e.g. a method added directly to it. Hermes does that
rarely and deliberately, reserved for the primary interfaces where the API
is judged worth the break. On Android the V1 Hermes AAR ships **no JSI** —
the JSI symbols a Hermes build needs come from your RN's *own* prebuilt
`libjsi.so`. So a newer-Hermes bump is trivial **unless a primary-interface
change landed between the build your RN ships and your target**; short of
that it's a one-line version bump (the `rn-0.86` example). If such a change
did land — a `jsi::Runtime` method your RN's prebuilt JSI doesn't export —
the app builds fine and then dies at `dlopen`, and the fix is re-vendoring
JSI + rebuilding RN's native libs from source (the hard path's JSI step, on
an otherwise-easy RN).

**RN 0.84 and 0.85 are exactly this case** for the `260318099.0.1` target:
both pin a JSI from just before `jsi::Runtime::isTypedArray` was added to
the `Runtime` interface. **RN 0.86 isn't**, which is why it's the easy-path
example here. Want 0.84 or 0.85 on this target? It's the JSI-rebuild path —
open an issue and the instructions can be added.

See [`docs/choosing-the-path.md`](docs/choosing-the-path.md) for the
classification command and the ABI check that tells the two cases apart.

## Worked examples

Both examples land on the same target build,
`com.facebook.hermes:hermes-android:260318099.0.1`:

- [`targets/rn-0.79/`](targets/rn-0.79/) — **hard path.** RN 0.79.5, which
  predates V1, swapped onto it: JSI vendored from `static_h`, CMake
  retargeted from `hermes-engine::libhermes` to `hermes-engine::hermesvm`,
  Maven group swapped, plus a CDP adapter shim to keep Chrome DevTools
  working.
- [`targets/rn-0.86/`](targets/rn-0.86/) — **easy path.** RN 0.86, which
  already consumes V1 out of the box, moved onto a newer `static_h` stable
  than the one it ships with by default.

## Repo layout

```
.
├── README.md                   # you are here
├── CLAUDE.md                   # project context for agentic work in this repo
├── docs/
│   ├── hermes-v1-versioning.md # canonical reference: what V1 is, how it's versioned
│   ├── choosing-the-path.md    # decision tree for classifying a checkout
│   ├── cdp-adapter.md          # design notes for the CDP (Chrome DevTools) shim
│   └── ios-handoff.md          # iOS bring-up runbook — maintainer to-do (see CLAUDE.md)
└── targets/
    ├── rn-0.79/                # hard path: full worked example + patches
    └── rn-0.86/                # easy path: full worked example
```

## iOS status

Not yet — everything above is Android. iOS builds only on a Mac, and
running agents on a Mac is less convenient than on the Linux server this was
built on, so it hasn't been done yet. It will be.
