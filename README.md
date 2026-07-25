# Running React Native on current Hermes V1

This repo is a guide, with worked examples, for getting a React Native app
onto a current build of Hermes V1, whatever RN version you're starting from.
How much work that takes depends entirely on how old your RN is. A recent RN
already consumes V1 by default, so it's mostly a version bump; an older RN
predates V1 and needs real surgery. Both cases are built out here end to end,
on Android.

## The mental model

Hermes V1 is the `facebook/hermes` `static_h` line: Hermes built and
versioned independently of React Native, rather than compiled inline as part
of the RN build. A given RN checkout records which V1 build it pins in
`packages/react-native/sdks/.hermesv1version`; if that file doesn't exist,
the checkout predates V1 entirely. See
[`docs/hermes-v1-versioning.md`](docs/hermes-v1-versioning.md) for the full
story, including the trap of confusing that file with the similarly named
(but unrelated) legacy `.hermesversion` pin.

## Which path is yours?

| RN version | Consumes | Effort |
|---|---|---|
| ≥ 0.84 | V1 by default (`com.facebook.hermes`) | Usually just a version bump, but ABI-gated (see the catch below) |
| 0.82–0.83 | V1 opt-in / source-build | Medium |
| ≤ 0.81 | legacy inline `libhermes.so` (`com.facebook.react`) | Hard: vendor JSI, retarget CMake, swap Maven group |

**The catch: "≥ 0.84 = easy" is not a given.** JSI is designed to grow
without breaking its ABI. New capabilities show up as optional interfaces
you query for at runtime, so they leave the core vtable alone. The ABI only
breaks when a primary interface, `jsi::Runtime` itself, changes — say, a
method added straight to it. Hermes does that rarely and on purpose, and only
to the primary interfaces, where a cleaner API is worth the break.

Here's why that gates the bump. On Android the V1 Hermes AAR ships no JSI at
all; the JSI symbols a Hermes build needs come from your RN's own prebuilt
`libjsi.so`. So the bump stays trivial as long as no primary-interface change
landed between the build your RN ships and the one you're moving to. When one
did, you get the annoying kind of failure: the app builds fine, then dies at
`dlopen` on the missing symbol. Fixing it means re-vendoring JSI and
rebuilding RN's native libs from source, which is the hard path's JSI step on
an otherwise-easy RN.

RN 0.84 and 0.85 land on the wrong side of this for the `260318099.0.1`
target: both pin a JSI from just before `jsi::Runtime::isTypedArray` was added
to the `Runtime` interface. RN 0.86 doesn't, which is why it's the easy-path
example here. If you need 0.84 or 0.85 on this target, that's the JSI-rebuild
path; open an issue and the instructions can be added.

See [`docs/choosing-the-path.md`](docs/choosing-the-path.md) for the
classification command and the ABI check that tells the two cases apart.

## Worked examples

Both examples land on the same target build,
`com.facebook.hermes:hermes-android:260318099.0.1`:

- [`targets/rn-0.79/`](targets/rn-0.79/) — the hard path. RN 0.79.5 predates
  V1, so it gets the full swap: JSI vendored from `static_h`, CMake retargeted
  from `hermes-engine::libhermes` to `hermes-engine::hermesvm`, the Maven
  group swapped, and a CDP adapter shim to keep Chrome DevTools working.
- [`targets/rn-0.86/`](targets/rn-0.86/) — the easy path. RN 0.86 already
  consumes V1 out of the box; here it's moved onto a newer `static_h` stable
  than the one it ships with.

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

Not yet. Everything above is Android. iOS builds only on a Mac, and running
agents on a Mac is less convenient than on the Linux server this was built
on, so it hasn't happened yet. It will.
