# Hermes V1 versioning, and the trap it's easy to fall into

This is the canonical reference for "what is Hermes V1, how is it
versioned, and which file does a given React Native checkout use to pin
it." Every other doc in this repo that talks about Hermes versions links
back here instead of re-explaining it.

The short version: Hermes has **two live version lineages** in the same
`facebook/hermes` repo, and they look similar enough (both are "the Hermes
version RN pins") that conflating them produces confidently wrong answers.
Only one of them is Hermes V1.

## What Hermes V1 is

Hermes V1 is built from the `facebook/hermes` **`static_h`** branch. It's
a rewrite of Hermes's build and packaging model: Hermes builds
independently of React Native and ships as its own artifact, rather than
being compiled inline as part of the RN build.

Two concrete, easy-to-check fingerprints distinguish a V1 artifact from
the legacy one it replaces:

- **The library is renamed.** `libhermes.so` (legacy) becomes
  `libhermesvm.so` (V1). The CMake prefab package name is unchanged
  (`hermes-engine`), but the target inside it moves from
  `hermes-engine::libhermes` to `hermes-engine::hermesvm`.
- **The Maven group changes.** Legacy Hermes ships as
  `com.facebook.react:hermes-android:<RN-version>`, versioned in lockstep
  with React Native itself. V1 ships as
  `com.facebook.hermes:hermes-android:<date-version>`, versioned on its
  own independent date-based schedule (below). The group name alone tells
  you which lineage you're looking at.

## The date versioning scheme

V1 releases use the version format:

```
YYMMDDxxx.0.N
```

`YYMMDDxxx` is not an arbitrary build number — it's (a zero-padded
encoding of) **the date a `-stable` branch was cut from `static_h`**. The
trailing `.0.N` is a patch counter for fixes cherry-picked onto that
stable branch after the cut.

This is verifiable directly against the repo. `static_h`'s own
`npm/hermes-compiler/package.json` carries the version of the *tip* of
`static_h` at any given moment — as of this writing that's
`260318099.0.0`, meaning the newest cut stable branch was cut on
2026-03-18. And the stable branches confirm the date encoding directly:

| Stable branch | Cut from `static_h` on |
|---|---|
| `250829098.0.0-stable` | 2025-08-29 |
| `260318099.0.0-stable` | 2026-03-18 |

(`git merge-base static_h <stable-branch>` gives the exact commit where
the branch diverged; its committer date is the date encoded in the
version number. See the appendix for the exact commands.)

The target version for this repo's worked examples is **`260318099.0.1`**
— the newest `static_h` stable release, one patch past the branch cut,
**not yet shipped in any released version of React Native** (as of
2026-07-25, the newest released RN, 0.86, still ships `250829098.0.14`;
see "Adoption timeline" below).

## How React Native pins V1

A React Native checkout that consumes Hermes V1 records the exact version
in:

```
packages/react-native/sdks/.hermesv1version
```

The file's content is a tag name of the form `hermes-v<version>`, e.g.
`hermes-v250829098.0.10`. This is the file to read (or the artifact
version to override) when you want to know, or change, which V1 build an
RN checkout uses. Confirmed on real RN releases:

| RN version | `.hermesv1version` |
|---|---|
| 0.84.1 | `hermes-v250829098.0.9` |
| 0.85.3 | `hermes-v250829098.0.10` |
| 0.86.0 | `hermes-v250829098.0.14` |

Note these are all patch bumps on the *same* stable branch
(`250829098`) — RN 0.84 through 0.86 haven't yet moved to the
`260318099` line.

## The trap: `.hermesversion` is a different Hermes

Sitting right next to `.hermesv1version` in the same directory is a
sibling file:

```
packages/react-native/sdks/.hermesversion
```

This file *also* pins "the Hermes version," and it *also* lives in the
`facebook/hermes` repo, which makes it very easy to assume it's just an
older way of expressing the same V1 pin. **It isn't.** It's a pointer
into the **legacy classic-Hermes lineage** — plain semver tags
(`hermes-v0.15.1` … `hermes-v0.17.0`, e.g. RN 0.85.3 pins
`hermes-v0.16.0`) built from `release-vNN` branches, which themselves
descend from the old date-stamped tags
(`hermes-YYYY-MM-DD-RNvX.Y-...`) that predate `static_h` entirely.

The two lineages are not "V1 vs. an earlier V1 draft" — they **diverged**.
`static_h` and `release-v0.17` share a common ancestor, and nothing
since: their merge-base commit is dated **2022-08-19**. Everything
`static_h` has picked up since then — including the entire V1 rewrite —
is absent from the `release-vNN` line, and vice versa for whatever
Hermes-team fixes have landed on `release-vNN` since the split.

So: **both `.hermesv1version` and `.hermesversion` name real, currently
maintained things in `facebook/hermes`.** Only `.hermesv1version` /
`static_h` / the date-based scheme is Hermes V1. If you see a bare semver
like `hermes-v0.16.0`, you are looking at the legacy classic-Hermes pin,
and it tells you nothing about V1 adoption in that RN checkout — check
`.hermesv1version` (and whether the file exists at all) for that.

## Adoption timeline

How React Native's relationship with V1 evolved, release by release:

| RN version | V1 status |
|---|---|
| ≤ 0.81 | No `.hermesv1version` file at all — the file doesn't exist. RN builds the legacy inline `libhermes.so` from `com.facebook.react:hermes-android`. |
| 0.82 | V1 opt-in, source build only. `.hermesv1version` exists but pins a raw `static_h` commit SHA rather than a released version tag — there's no prebuilt artifact yet, so consuming it means building Hermes from source. |
| 0.83 | V1 becomes the default *packaging*, with real prebuilt versions (`.hermesv1version` pins an actual `250829098.x` release, e.g. `hermes-v250829098.0.4`). |
| 0.84 | First release where V1 is both default **and** ships prebuilts as the primary path — the "easy path" this repo's `targets/rn-0.85` worked example exploits. |
| 0.84 – 0.86 | All three releases stay on the `250829098` stable branch, only bumping the patch component (`.0.9` → `.0.10` → `.0.14`). None has moved to `260318099` yet. |

## Appendix: verification commands

These are the exact commands used to derive every fact above. Re-run them
against a future state of either repo to check whether anything has
drifted — dates and version numbers here are current as of **2026-07-25**.

```bash
# 1. The date scheme is native to static_h: read the version at the tip
#    of the branch.
gh api "repos/facebook/hermes/contents/npm/hermes-compiler/package.json?ref=static_h" \
  --jq '.content' | base64 -d | grep version
# => "version": "260318099.0.0",

# 2. RN's real V1 pin: read .hermesv1version off a tagged release.
gh api "repos/facebook/react-native/contents/packages/react-native/sdks/.hermesv1version?ref=v0.85.3" \
  --jq '.content' | base64 -d
# => hermes-v250829098.0.10

# 3. The 2022 fork, proving semver (.hermesversion / release-vNN) is a
#    different lineage from static_h, not an older V1.
gh api "repos/facebook/hermes/compare/static_h...release-v0.17" \
  --jq '.merge_base_commit.commit.committer.date'
# => 2022-08-19T13:11:07Z
```

Supporting commands used for the tables above (same technique, more data
points):

```bash
# Stable-branch cut dates (confirms the YYMMDDxxx encoding for both
# branches referenced in this doc).
gh api "repos/facebook/hermes/compare/static_h...250829098.0.0-stable" \
  --jq '.merge_base_commit.commit.committer.date'
# => 2025-08-29T19:46:38Z
gh api "repos/facebook/hermes/compare/static_h...260318099.0.0-stable" \
  --jq '.merge_base_commit.commit.committer.date'
# => 2026-03-18T21:24:56Z

# RN's .hermesv1version across releases (adoption timeline / pin table).
for tag in v0.82.0 v0.83.1 v0.84.1 v0.85.3 v0.86.0; do
  echo -n "$tag: "
  gh api "repos/facebook/react-native/contents/packages/react-native/sdks/.hermesv1version?ref=$tag" \
    --jq '.content' | base64 -d
  echo
done
# v0.82.0: 76dc37932b176d196c39d52a3ca759e8b5ce7a68   (raw commit SHA, no prebuilt)
# v0.83.1: hermes-v250829098.0.4
# v0.84.1: hermes-v250829098.0.9
# v0.85.3: hermes-v250829098.0.10
# v0.86.0: hermes-v250829098.0.14

# Pre-0.82 RN has no .hermesv1version at all.
gh api "repos/facebook/react-native/contents/packages/react-native/sdks/.hermesv1version?ref=v0.81.0"
# => 404 Not Found

# The legacy sibling pin, for contrast — a plain semver tag, not a date.
gh api "repos/facebook/react-native/contents/packages/react-native/sdks/.hermesversion?ref=v0.85.3" \
  --jq '.content' | base64 -d
# => hermes-v0.16.0
```

If a re-run produces different numbers than the ones recorded in this
doc, trust the re-run — update the tables above rather than treating this
document as a frozen historical record.
