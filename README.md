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
| ≥ 0.84 | V1 by default (`com.facebook.hermes`) | Easy — bump the artifact version |
| 0.82–0.83 | V1 opt-in / source-build | Medium |
| ≤ 0.81 | legacy inline `libhermes.so` (`com.facebook.react`) | Hard — vendor JSI, retarget CMake, swap Maven group |

See [`docs/choosing-the-path.md`](docs/choosing-the-path.md) for the
classification command and details on each row.

## Worked examples

Both examples land on the same target build,
`com.facebook.hermes:hermes-android:260318099.0.1`:

- [`targets/rn-0.79/`](targets/rn-0.79/) — **hard path.** RN 0.79.5, which
  predates V1, swapped onto it: JSI vendored from `static_h`, CMake
  retargeted from `hermes-engine::libhermes` to `hermes-engine::hermesvm`,
  Maven group swapped, plus a CDP adapter shim to keep Chrome DevTools
  working.
- [`targets/rn-0.85/`](targets/rn-0.85/) — **easy path.** RN 0.85, which
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
│   └── ios-handoff.md          # iOS bring-up, run on a Mac (see below)
└── targets/
    ├── rn-0.79/                # hard path: full worked example + patches
    └── rn-0.85/                # easy path: full worked example
```

## iOS status

Everything above is validated on Android; this guide's build/test loop runs
on Linux, which can't build or run iOS. iOS bring-up for both worked
examples is written up separately for a Mac in
[`docs/ios-handoff.md`](docs/ios-handoff.md).
