# Original-ID source and controller migration

This contribution keeps `zzz-nonstandard-beacons` and receives the original mod's saved
storage directly. Direct conversion supports populated upstream **1.4.2** and **2.0.0**
saves on Factorio **2.1.23**. Older saves must first reach 1.4.2 under Factorio 2.0;
unsupported historical migration routines stop before destructive work. Preserve an
untouched original save. A 1.4.2 save does not need to pass through unchanged upstream
2.0.0 before using this contribution.

Consumer mods retain their upstream dependency and must themselves support Factorio
2.1. The upstream dependency declarations remain unchanged, including PEREL >=1.2.3
and Things >=0.6.1. The original and continuation implementations share prototype and
remote-interface names and cannot be loaded together.

`scripts/legacy.lua` recognizes the unversioned upstream record shape. It retains the
actual visible beacon and source, deriving identity, direction, mirroring and pause
from those engine objects. Expected source prototype, surface, exact position, force
and quality must match. Controllers are disposable only after ownership is established.
Their callbacks and manager lookup are rebuilt; optional module monitoring is restored
from current definitions. The original public `pointer` field remains an alias of the
current manager unit number.

Malformed values, swapped keys, duplicate record IDs, ambiguous sources and foreign
helper references cannot authorize deleting a visible beacon or unrelated entity.
Conflicting records are retained in `storage.legacy_orphans`; unverified references
stay outside operational source/helper fields. Protected records retain diagnostics.
Explicit repair revalidates ownership and refuses to release unresolved ambiguity.

The historical 2.0.0 migration filename remains but delegates resource-preserving work
to the lifecycle converter. Existing 2.0.0 saves have already executed that filename,
so saved schema detection also supports a same-version development load.

Historical 1.x routines do no work under Factorio 2.1. The configuration callback
checks the engine's authoritative old mod version before conversion, rather than
relying only on legacy storage metadata. No old version means a new installation:
adding NSB to an existing save is supported and must not be rejected by a historical
migration filename. Partial pending records without a usable deadline stay protected;
their stale work scheduling is retired without discarding resources or diagnostics.

## Structured development state

The review branch keeps the upstream version at 2.0.0; internal storage uses schema 2.
Already-structured development records retain source pauses, inventories, modules,
processing state, orientation, pending transactions, escrow, protected diagnostics and
saved surplus energy. Conversion rebuilds controllers only. A normal schema-2 reload
does not rebuild them. The synthetic schema-1 fixture is development-state coverage,
not a claim that upstream released that schema.

`on_load` does not mutate saved state. If conversion is needed, it subscribes to one
game-available tick through the existing reserve scheduler. Any earlier dispatched event
also ensures conversion before using the lookup. Configuration changes may run first;
both routes use the same conversion. A missing lookup in a schema-2 save is recoverable.
Protected state is never automatically re-enabled by this conversion. After resolving
its reported incompatibility, use the existing explicit repair adapters.

## Historical engine provenance

`scripts/migration.py` accepts an explicit verified 2.0.77 `--old-engine`, or a preserved
`--donor-save` with `--donor-sha256` and `--donor-provenance`. The target `--engine` must
have both executable and base data at 2.1.23. A Steam path is not proof of an old engine.
The current acceptance reused retained 2.0.77 donors; no new 2.0.77 installation was available.

The unchanged upstream 2.0.0 snapshot at `8bf22ca6fe59544e816ad360017e083a697ff5cd`
was tested separately during the earlier continuation work: its 1.4.2 donor transition
reached a recipe event with a missing `storage.beacon_pointers` lookup. That is a
pinned-code fixture finding, not an explanation of every separately reported failure.
The current contribution's own original-ID conversions are recorded in
[candidate verification](testing.md).
