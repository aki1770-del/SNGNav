# Contributing to SNGNav

Thank you for contributing to SNGNav.

This project is an offline-first navigation architecture for Flutter on embedded
Linux. The goal is not to ship flashy demos for perfect conditions. The goal is
to help edge developers build systems that still assist the driver when GPS,
network, or backend availability degrades.

If you are new here, start with one of these:

- documentation drift or broken links
- package README improvements
- tests for an existing edge case
- small fixes that preserve offline-first, consent-first, display-only behavior

If you want to propose a new feature or report a bug, use the GitHub issue
templates first. They capture the failure mode, environment, and driver or edge
developer impact before code work starts.

---

## Project Shape

SNGNav is a monorepo with 11 published packages plus an example application
that composes them.

### Package portfolio

| Package | Responsibility |
|---------|----------------|
| `kalman_dr` | Dead reckoning and 4D Extended Kalman Filter |
| `routing_engine` | Engine-agnostic route interface |
| `routing_bloc` | Route lifecycle BLoC |
| `driving_weather` | Weather condition models |
| `driving_conditions` | Road surface classification and simulation |
| `driving_consent` | Consent records and deny-by-default policy |
| `fleet_hazard` | Hazard reports, clustering, temporal decay |
| `navigation_safety` | Safety overlays and navigation safety boundaries |
| `map_viewport_bloc` | Camera and viewport state |
| `offline_tiles` | MBTiles-backed offline tile handling |
| `voice_guidance` | Engine-agnostic navigation speech |

Use the package boundary as your first design tool. If a change can be cleanly
expressed inside one package, keep it there.

---

## First Contribution Paths

Good first contributions usually look like this:

- fix a broken doc path or stale metric
- improve an install or demo instruction that caused friction
- add a missing test around an existing public API
- tighten a package README example so it matches the real API
- add analysis or CI-safe coverage around an already accepted behavior

Higher-risk changes include:

- safety-boundary changes
- consent semantics changes
- routing engine interface changes
- new platform-specific runtime behavior
- anything that weakens offline-first behavior

Open an issue before starting those.

---

## Before You Open An Issue

SNGNav ships repository issue templates in `.github/ISSUE_TEMPLATE/`.

Use:

- `bug_report.yml` for reproducible defects
- `feature_request.yml` for new capabilities or workflow changes

The templates ask for the right things:

- why it matters to the driver or edge developer
- a minimal reproduction path
- expected behavior
- environment details
- safety and scope impact

That structure is deliberate. It keeps the discussion tied to driver-assisting
value instead of drifting into vague feature requests.

---

## Local Setup

### Prerequisites

On Ubuntu or Debian-like systems:

```bash
sudo apt install clang cmake ninja-build libgtk-3-dev libsqlite3-dev pkg-config
flutter pub get
for pkg in packages/*/; do
  (cd "$pkg" && flutter pub get)
done
```

For the app demo, see [README.md](README.md).

For ARM targets, see [docs/arm_deployment.md](docs/arm_deployment.md).

---

## Choosing Where To Change Code

Use these rules:

1. If the behavior is domain logic, prefer a package over app widget code.
2. If the behavior is package-specific, change only that package and its tests.
3. If multiple packages need to compose, wire them together in the example app.
4. If you find yourself cutting through several layers for a small feature, the boundary is probably wrong.

Examples:

- Road surface logic belongs in `packages/driving_conditions/`
- Consent semantics belong in `packages/driving_consent/`
- TTS engine integration belongs in `packages/voice_guidance/`
- Route lifecycle UI state belongs in `packages/routing_bloc/`

---

## Testing Expectations

CI is the authoritative gate.

Current CI runs three jobs:

1. `flutter analyze --no-fatal-infos`
2. test suites across the app and all packages
3. Linux release build

Coverage is also aggregated in CI as a quality signal.

### Before opening a PR

Run the relevant local checks for your change.

For documentation-only changes:

```bash
flutter analyze --no-fatal-infos
```

For package changes, run the package tests you touched plus root checks.

Examples:

```bash
flutter analyze --no-fatal-infos
flutter test --exclude-tags=probe

cd packages/voice_guidance && flutter test
cd packages/kalman_dr && dart test
```

### Test guidance

- mirror `lib/` structure under `test/`
- keep tests self-contained
- prefer constructor injection over global mocking
- use `bloc_test` for event-to-state assertions
- keep probe or live-network tests out of normal CI paths

If a README or doc claims a test count or metric, verify it against the live
repository state before submitting the change.

---

## Documentation Contributions

Documentation is a first-class contribution type here.

Useful doc work includes:

- correcting stale package counts, test counts, or version numbers
- tightening installation paths
- improving explanation of safety boundaries
- aligning package docs with current APIs
- reducing the time from clone to first successful run

When editing docs:

- prefer concrete examples over marketing language
- keep claims auditable
- state limitations plainly
- link to real files that exist in the repo

If you remove reader friction, say so explicitly in the PR description.

---

## Safety And Scope Rules

Read [SAFETY.md](SAFETY.md) before making safety-adjacent changes.

Non-negotiable constraints:

- SNGNav is display-only and advisory
- there is no vehicle control path
- dead reckoning must remain honest about uncertainty
- consent defaults to deny until explicitly granted
- offline-first behavior should not be weakened casually

If your change affects any of those, call it out in the PR description.

---

## Pull Requests

When opening a PR, include:

- what changed
- why it matters to the driver or edge developer
- which package or surface it affects
- what checks you ran
- any limitations or follow-up work

For code changes, include exact test or analyze commands.

For doc-only changes, replace test delta language with the friction or drift you
removed.

Keep PRs narrow. Small, well-bounded contributions are easier to review and
safer to merge.

---

## Community Etiquette

The best contributions here are legible, reproducible, and honest.

- explain failure modes clearly
- avoid vague feature requests
- prefer evidence over slogans
- preserve package boundaries where possible
- be explicit about tradeoffs

SNGNav is built for stressful conditions. The contribution standard should be
calm and precise for the same reason.

---

## License

By contributing, you agree that your contributions will be licensed under the
same BSD-3-Clause license as the project.