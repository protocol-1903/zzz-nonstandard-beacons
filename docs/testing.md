# Candidate verification

Tests use the original `zzz-nonstandard-beacons` ID and **Factorio 2.1.23 build 87750**.
Executable and adjacent base-data versions are asserted separately. Mod/configuration/save
directories are isolated; no runner reads account credentials or changes installed selections.

The reference is upstream `8bf22ca6fe59544e816ad360017e083a697ff5cd`. Its dependencies remain
unchanged: PEREL >=1.2.3 and Things >=0.6.1. Fixtures used PEREL **1.2.3**, public commit
`febdb6760a99d776b23107e3ad791eaae5083978`, and Things **0.6.7**. Exact dependency/source
hashes, settings, logs and native receipts are retained outside the shipping archive.

## Reproduction

The Python harnesses are Windows-oriented (hidden graphical clients and local servers)
and use Python 3.11 or newer. Supply an explicit engine and dependency source directories
or ZIPs. Use a different empty output directory for each command.

```text
python scripts/validate.py --engine <engine> --output <runtime-stage> --perel <perel> --things <things> --ticks 3600 --space-age --examples
python scripts/validate.py --engine <engine> --output <installation-stage> --perel <perel> --things <things> --ticks 3600 --space-age --examples --add-to-existing
python scripts/legacy_fixture.py --engine <engine> --output <legacy-stage> --perel <perel> --things <things>
python scripts/schema_fixture.py --engine <engine> --output <schema-stage> --perel <perel> --things <things>
python scripts/power_events.py --engine <engine> --output <event-stage> --perel <perel> --things <things>
python scripts/package.py --engine <engine> --output <package-stage> --perel <perel> --things <things>
python scripts/migration.py --engine <engine> --output <migration-stage> --perel <perel> --things <things> --donor-save <donor.zip> --donor-sha256 <recorded-hash> --donor-provenance <original-log>
```

Add `--archive <candidate.zip>` to migration.py for archive-only migration and reload.
For a fresh historical donor, replace the three `--donor-*` arguments with
`--old-engine <verified-2.0.77-engine> --old-nsb <NSB-1.4.2.zip> --old-perel <PEREL-1.1.9.zip>`.
Preserved donors are copied and hash-checked, never overwritten. Donor/candidate phases
are explicit because both now use the same mod ID.

The legacy fixture exercises unchanged-code `on_load` and reload with swapped keys,
duplicate IDs, foreign sources/helpers, malformed values, partial protected/pending
records, missing deadlines, escrow, reserves and repeated repair. The schema fixture
defaults to a **synthetic schema-1 development donor**, not an upstream release.
It and the event runner accept an optional compatible structured `--baseline`;
unmodified upstream does not expose their private hooks.

After validate.py creates the standalone runtime stage:

```text
python scripts/native_client.py --engine <engine> --run <runtime-stage> --save <runtime-stage>/fixture.zip --marker nsbc-ui-result.json --phase ui-en-100 --locale en --ui-scale 1 --width 1920 --height 1200
python scripts/multiplayer.py --engine <engine> --staged <runtime-stage> --output <multiplayer-stage> --wait-seconds 420
```

Repeat native_client.py for `en`, `de`, `ja` with unique phase names: 1920x1200 at
100%, 2400x1500 at 125%, and 2880x1800 at 150%, maintaining the same logical workspace.
Receipts record engine scale and actual window geometry. Private hooks are appended only
to staged copies and never ship. The multiplayer runner starts two actual clients, overlaps
their viewing/actions, then disconnects/rejoins one. Sprite startup is serialized.

## Candidate results

These are new original-ID contribution results, not inherited NSBC acceptance claims.

| Case | Result |
| --- | --- |
| Fresh game and add-to-existing installation, each with 3,600 ticks, Space Age, examples, recovery and robot/platform operations | Passed |
| Actual populated upstream 1.4.2 donor, direct conversion and second reload | Passed, including archive-only loading |
| Healthy populated upstream 2.0.0 donor, same-version conversion and reload | Passed, including archive-only loading |
| Adversarial legacy storage, unchanged-code conversion, repeated repair and second reload | Passed; eight records and three quarantined entries retained |
| Synthetic schema 1, pending/clone work, reserves/escrow, protected pauses, conversion and two further loads | Passed |
| 200-beacon event fixture, five runs | Passed; all operating/depleted/module/protected settled samples have zero new events and updates |
| Runtime-only ZIP creation and archive runtime | Passed; 30 files and all eight locales |
| Captured ESIR 1.4.0 native replacement, overload and depletion | Passed; eight handoffs, overload 4→5→4 with actual machine disable/recovery |
| Captured ESIR native player matrix, transforms and reload | Passed; 12 player cases, 128 transforms and 131 reconciled beacon records |
| Captured ESIR robot/platform and Alien repair-to-upgrade | Passed; 26 actor cases and six repair/upgrade cases |
| English/German/Japanese rendering at three scales | Final receipts pending |
| Captured ESIR two-client viewing/actions and disconnect/rejoin | Final receipts pending |

The ESIR profile is a captured **1.4.0** snapshot with a private dependency switch to
this candidate; 493 main source files were verified before the switch. This does not
certify unrelated later ESIR worktree changes. Controlled engine depletion measured
Copper **4.9999988 nitrogen/s** and Iron **9.9999976 nitrogen/s**, matching 5/s and 10/s
within native float precision. Displayed rates remain calculated operating requirements.
Copper→Iron changes ESIR's overload weight from 1 to 2.

All eight locales have 38 matching keys, no duplicate/empty entries and matching numbered
placeholders. Rendered ESIR screenshots show opened panels and burning fuel with an empty
queue. Structural and rendered checks do not establish native-speaker approval.

## Limits and provenance

Physical keyboard/mouse actions, complete blueprint-library UI navigation and native
language review are not established by scripted actions or screenshots. The hover-only
screenshot does not independently prove physical pointer tooltip display. Factorio 2.1.23
rejects native cross-surface beacon teleportation; cross-surface cloning is covered instead.

Earlier NSBC evidence helped select fixtures but does not certify this candidate.
No earlier NSBC performance percentage is presented as an upstream comparison; candidate
event timings are diagnostic, not an isolated performance claim. Older-than-1.4.2 saves
require their historical Factorio 2.0 upgrade first. No cross-energy replacement or new
fuel-management window is proposed.

The shipping allowlist excludes development docs, tests, Python, manifests, executables
and private evidence. Acceptance and release of this optional proposal remain the
maintainer's decision.
