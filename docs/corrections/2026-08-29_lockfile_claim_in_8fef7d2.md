# Correction: the `pubspec.lock` claim in commit `8fef7d2` is wrong

**Date:** 2026-08-29
**Corrects:** the commit message of `8fef7d2461d29bd10b43268e52633243f0a39512`
("IVI-6: land the offline-camera, badge and thrown-layer fixes on the base the recipe actually
fetches"), which is already published and cannot be amended.

This file exists because that message is public and states something false about how this
repository's lockfile works. Rewriting published history would be worse than a wrong sentence with
a correction beside it, so the correction lives here instead.

---

## The claim that was wrong

`8fef7d2`'s message said its `pubspec.lock` changes were

> "a property of `origin/main`'s lock being five packages stale **against today's pub.dev**"

and listed five packages, singling out `condition_aggregator_jma 0.5.0 -> 0.7.0` as one that "feeds
the weather stack" — implying a dependency version could move underneath a consumer.

**Neither part is true.**

## What is actually true

All five packages are **in-tree path dependencies**, not hosted ones:

```yaml
  adaptive_reroute:
    dependency: "direct main"
    description:
      path: "packages/adaptive_reroute"
      relative: true
    source: path              # <- not `hosted`. pub.dev cannot move this.
    version: "0.2.1"
```

For a `source: path` entry, the version recorded in `pubspec.lock` is **read off the in-tree
`packages/<name>/pubspec.yaml` sitting beside it in the same commit.** It is not resolved from
pub.dev, and no registry publish can change it.

Measured at `feead05` (the parent of `8fef7d2`), lockfile against the tree in that same commit:

| package | `pubspec.lock` | `packages/<name>/pubspec.yaml` |
|---|---|---|
| `adaptive_reroute` | 0.2.0 | **0.2.1** |
| `condition_aggregator_jma` | 0.5.0 | **0.7.0** |
| `driving_conditions` | 0.6.0 | **0.7.0** |
| `kalman_dr` | 0.6.1 | **0.6.2** |
| `pretrip_decision_advisor` | 0.6.0 | **0.6.1** |

Running `dart pub get` / `flutter pub get` fetched nothing newer from the network for these. It
**reconciled the lockfile to code that was already committed beside it.**

## Why the distinction matters

1. **The risk the original message implied does not exist.** A `path` dependency always builds the
   in-tree source. The number in the lockfile changes nothing about which bytes compile, so no
   consumer's weather adapter — or anything else — could move under them because of it.

2. **The real problem is different, and it is a genuine one.** At `feead05` the lockfile disagreed
   with its own tree *inside a single commit*: five package versions had been bumped in
   `packages/*/pubspec.yaml` with nothing regenerating `pubspec.lock` alongside them. That is not
   staleness against an external registry — it is a commit that contradicts itself, and it will
   reappear on the next in-tree version bump. **Nothing in this repository currently regenerates
   `pubspec.lock` when a path package's version changes.**

3. **The floating surface was mis-located.** The original message named five packages that cannot
   float and said nothing about the ones that can. Measured in the same lockfile:

   ```
   source: hosted   109
   source: path      23
   ```

   The 109 hosted entries are the surface where a version genuinely can move. The 23 path entries
   are pinned by construction.

## If you are checking this yourself

```sh
git show feead05:pubspec.lock | grep -A6 '^  adaptive_reroute:$'
git show feead05:packages/adaptive_reroute/pubspec.yaml | grep '^version:'
grep -c '    source: hosted' pubspec.lock
grep -c '    source: path'   pubspec.lock
```

## Root of the mistake

A version number was read as evidence of a registry resolution without reading the `source:` field
four lines below it — in output that had already been printed while investigating. The tooling
reported correctly; the reading stopped early.
