# Universal Hermes V1 multi-version repo — design

**Date:** 2026-07-25
**Status:** approved — structure and scope decided (see Decisions)

## Decisions (from spec review)

1. **Android only this pass.** This work happens on a Linux box; iOS can't be
   built or tested here. Do full **Android Debug + Release**. iOS is deferred to
   a **handoff document** (`docs/ios-handoff.md`) that the maintainer runs on a
   Mac.
2. **Container name `targets/`** — confirmed.
3. **Both targets use the same Hermes V1 version, `260318099.0.1`.** Different
   targets on different Hermes versions would be confusing. This means the
   existing 0.79 port is **re-validated at the newer static_h stable**, not left
   on its current `250829098.0.13` — a real task, not a string swap (see
   "Bumping the 0.79 port").

## Goal

Turn this single-target repo (RN 0.79.5 → Hermes V1) into a universal guide plus
tested worked examples for running **current Hermes V1** (`static_h`) on
**different React Native versions**. Prove the method on one new version now —
**RN 0.85** — structured so future already-V1 RN versions follow the same
process until some unknown upstream change breaks it.

The existing RN 0.79 port stays as the fully-worked **hard case** (a version
that predates standalone Hermes). The new RN 0.85 port is the **easy case** (a
version that already ships Hermes V1 by default, where the task is bumping the
engine to a newer static_h stable).

## Background: the conceptual core (version-independent)

This is the reusable knowledge the guide must teach. All of it was verified
against `facebook/hermes` and `facebook/react-native` on 2026-07-25.

- **Hermes V1 = the `facebook/hermes` `static_h` branch.** Library renamed
  `libhermes.so` → `libhermesvm.so`. Maven group `com.facebook.hermes`
  (old/classic Hermes was `com.facebook.react:hermes-android`, versioned with
  RN).
- **static_h self-versions on a date scheme `YYMMDDxxx.0.N`.** The `YYMMDDxxx`
  is the date a `-stable` branch was cut from `static_h`. Verified: `static_h`'s
  own `npm/hermes-compiler/package.json` reads `260318099.0.0`; the
  `250829098.0.0-stable` branch merge-base decodes to 2025-08-29 and
  `260318099.0.0-stable` to 2026-03-18. Current stable branches:
  `250829098` (2025-08-29) and `260318099` (2026-03-18).
- **RN pins Hermes V1 via `packages/react-native/sdks/.hermesv1version`.**
  Verified: RN 0.84 → `hermes-v250829098.0.9`, RN 0.85 → `hermes-v250829098.0.10`,
  RN 0.86 → `hermes-v250829098.0.14`. The sibling `.hermesversion` file
  (semver `hermes-v0.15.1` … `0.17.0`) is the **legacy classic-Hermes** pin —
  a *different lineage* (`release-vNN` branches, direct descendant of the old
  `hermes-YYYY-MM-DD-RNvX.Y` tags) that diverged from `static_h` on
  2022-08-19. It is **not** V1. Do not confuse the two files.
- **RN 0.84 is the first version with Hermes V1 as the default engine and
  prebuilt support** (no source build). RN 0.85 and 0.86 continue on the
  `250829098` stable branch at rising patch levels.
- **Newest static_h stable not yet shipped in any released RN = `260318099.0.1`**
  (Maven `<release>`, published 2026-07-23). Every shipped RN still pins
  `250829098.x`. This is the artifact the new proof point upgrades to.

The full versioning/fork explainer lands in `docs/hermes-v1-versioning.md`.

## The method (what the guide generalizes)

One operation — *"point a given RN at a chosen Hermes V1 stable artifact"* —
whose difficulty depends on how that RN version consumes Hermes:

| RN version | Ships / consumes | Effort | Worked example |
|---|---|---|---|
| ≥ 0.84 | Hermes V1 by default (`com.facebook.hermes`, `250829098.x`) | **Easy** — override the artifact version to a newer static_h stable; re-vendor JSI + matching hermesc only if the newer Hermes requires it | `targets/rn-0.85` |
| 0.82–0.83 | Hermes V1 opt-in / source-build only | Medium | documented, not built |
| ≤ 0.81 | Old inline Hermes (`libhermes.so`, `com.facebook.react`) | **Hard** — vendor static_h JSI, CMake `libhermes`→`hermesvm` rename, swap Maven group, CDP shim | `targets/rn-0.79` |

## Repo structure

```
/
├── README.md                 # NEW universal guide (short): what this is → mental
│                             #   model → path-selection table → links to examples
├── CLAUDE.md                 # updated: project is multi-version, not just 0.79
├── docs/
│   ├── hermes-v1-versioning.md   # date-line vs semver, the 2022 static_h fork,
│   │                             #   .hermesv1version vs .hermesversion — the most
│   │                             #   reusable doc, distilled from this investigation
│   ├── choosing-the-path.md      # decision tree: identify what your RN ships,
│   │                             #   how hard the swap is
│   ├── cdp-adapter.md            # moved from CDP_ADAPTER_PLAN.md (0.79-specific)
│   └── ios-handoff.md            # what the maintainer runs on a Mac: iOS bring-up
│                                 #   for rn-0.85 + rn-0.79 iOS re-validation at 260318099.0.1
└── targets/
    ├── rn-0.79/              # HARD case — current content relocated intact
    │   ├── README.md         # the current ~46 KB diary, otherwise as-is
    │   ├── patches/          # 01–06 + REGENERATE.md
    │   ├── scripts/          # apply-patches.sh, vendor-hermes-ios.sh (paths fixed)
    │   └── sample79/
    └── rn-0.85/              # EASY case — new; built after the reorg
        ├── README.md
        ├── patches/          # expected small: artifact override (+ JSI/hermesc if needed)
        ├── scripts/
        └── sample85/
```

Rejected alternatives: flat/prefixed dirs at root (`patches-0.79/`,
`patches-0.85/` — crowds the root); branch-per-version (invisible; defeats a
comparative guide).

## Deliverables

1. **Reorg (mechanical, history-preserving).** `git mv` all current top-level
   content into `targets/rn-0.79/`. Fix the now-broken relative paths in
   `scripts/apply-patches.sh` and `scripts/vendor-hermes-ios.sh` (they resolve
   `REPO_ROOT` as the script's grandparent and reference `sample79/`).
2. **Universal `README.md`** at root: what the repo is, the one-paragraph mental
   model, the path-selection table above, links to both worked examples.
3. **`docs/hermes-v1-versioning.md`** — the fork/versioning explainer distilled
   from this session's investigation, with the verification commands.
4. **`docs/choosing-the-path.md`** — the decision tree.
5. **`targets/rn-0.85/`** — the new worked example (see next section).
6. **Bump `targets/rn-0.79/` to `260318099.0.1`** — re-validate the existing
   port at the newer static_h stable (see "Bumping the 0.79 port").
7. **`docs/ios-handoff.md`** — Mac-side instructions for the iOS work this pass
   defers.
8. **`CLAUDE.md`** update — reframe project goal as multi-version.

## `targets/rn-0.85` — scope and acceptance

- **Base:** RN 0.85.3, a fresh stock app (`sample85`, mirroring how `sample79`
  was created).
- **Swap:** move Hermes V1 from the `250829098.0.10` that RN 0.85 ships to
  **`com.facebook.hermes:hermes-android:260318099.0.1`**.
- **Discovery unknowns (resolved during implementation, not now):**
  - Does `260318099` expose JSI symbols/headers newer than what RN 0.85
    vendors? If so, re-vendor `static_h:API/jsi/jsi/*` (same operation as
    patch 01, but far smaller if RN 0.85's JSI is already close).
  - Does a release build need a matching `hermes-compiler` (V1 hermesc at
    `260318099.0.1`) to emit the right HBC version?
  - Does anything in RN 0.85's Hermes integration hard-code the `250829098`
    version or assume its ABI?
- **Effort scope this pass:** Android **Debug + Release** building and running
  on `260318099.0.1`. iOS is deferred to `docs/ios-handoff.md`.
- **Acceptance:** the app launches on an emulator; `libhermesvm.so` is present
  (no `libhermes.so`); the engine reports the V1 version; the release APK runs
  with the JS baked in as HBC and no Metro.

## Bumping the 0.79 port to `260318099.0.1`

The existing 0.79 port targets `250829098.0.13`. Moving it to `260318099.0.1`
(one static_h stable branch newer, 2026-03-18 vs 2025-08-29) is a re-validation,
not a rename:

- Update the version string wherever the patches hard-code it (the Gradle
  substitution in patch 02, the iOS vendor script/Podfile in patches 05/06,
  the release hermesc `hermes-compiler` version).
- Re-vendor `static_h:API/jsi/jsi/*` (patch 01) **if** the newer stable's JSI
  drifted from what patch 01 currently ships. Diff before assuming.
- Re-check the CDP shim (patch 04) against `260318099`'s `hermes/cdp/*` — the
  same drift that motivated the shim could have shifted again.
- Confirm the V1 hermesc at `260318099.0.1` still emits the HBC version RN 0.79
  loads.
- **Android is validated here; iOS re-validation goes to the handoff doc.**

If the bump turns out to be more than mechanical, that discovery is itself a
useful data point for the guide (it shows what "newer static_h stable" can cost
even on the hard path).

## History preservation

Use `git mv` for the relocation so `git log --follow` still works on the
patches (the crown jewels). Script path fixes are a follow-up commit on the
moved files.

## Out of scope

- Building/testing RN versions other than 0.79 and 0.85.
- Building the 0.82–0.83 opt-in path (documented only).
- iOS builds/tests on this Linux box — deferred to `docs/ios-handoff.md` for the
  maintainer to run on a Mac (covers both rn-0.85 iOS bring-up and rn-0.79 iOS
  re-validation at `260318099.0.1`).

---

## Amendment (2026-07-25): easy-path base pivoted RN 0.85 → RN 0.86 (JSI-ABI ceiling)

During execution the RN 0.85 easy-path target **built but crashed at runtime**:
`dlopen: cannot locate symbol jsi::Runtime::isTypedArray(const jsi::Object&)`
referenced by `libhermesvm.so`.

Root cause (verified): the pure artifact bump is gated by the RN prebuilt's
**JSI ABI**, because the V1 AAR ships no JSI — RN's own `libjsi.so` must export
every JSI symbol the newer `libhermesvm.so` references.

- `jsi::Runtime::isTypedArray` entered JSI at static_h **`250829098.0.11`**.
- **RN 0.85 pins `250829098.0.10`** — the single last JSI patch *before* that
  symbol — so its prebuilt `libjsi.so` cannot satisfy any newer stable. Reaching
  `260318099.0.1` on RN 0.85 would require re-vendoring JSI and rebuilding RN's
  native libs from source (the hard-path surgery).
- **RN 0.86 pins `250829098.0.14`**; its bundled `jsi.h` is byte-identical to
  `260318099.0.1`'s, so a pure one-line bump links and runs clean.

**Decision (user-approved): move the easy-path proof point to RN 0.86.** Verified
end-to-end: welcome screen reads `JS Engine: Hermes (260318099.0.1)`. The RN 0.85
wall is retained as a documented caveat — it is the concrete illustration of the
rule: *the easy pure-bump only reaches Hermes builds within your RN prebuilt's
JSI-ABI window.* `targets/rn-0.85` is removed; `targets/rn-0.86` replaces it.

This also refines the path-selection guidance: "RN ≥ 0.84 = easy" becomes
"RN ≥ 0.84 = easy **iff** the RN prebuilt's JSI ABI already includes the symbols
the target Hermes needs; otherwise it degrades to the hard path (source rebuild)."
