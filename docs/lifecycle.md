<a id="contract"></a>
# Attachment and source ownership

The visible beacon owns real modules. Its hidden assembling-machine source owns fuel,
burning remainder, fluids, heat, energy and recipe state. Manager/monitor/mimic entities
and their synthetic module copies are disposable controllers.

Implementation owners: control.lua is the sole dispatcher; scripts/lifecycle.lua owns
attachment, migration, replacement, removal and repair; scripts/power.lua owns circuit
monitoring and callback registration; scripts/orientation.lua owns orientation;
scripts/information.lua owns derived presentation; scripts/common.lua owns shared guards;
scripts/types.lua describes persisted shapes; data-final-fixes.lua compiles consumer definitions.
scripts/legacy.lua validates and normalizes unversioned upstream records before controller
conversion; it retains malformed references in diagnostic quarantine.
The fixture sources under tests exercise these contracts without loading full ESIR.

<a id="upstream-storage"></a>
## Original-ID upstream saves

This contribution keeps `zzz-nonstandard-beacons`. Upstream 1.4.2 and 2.0.0 records
therefore arrive in this mod's own storage, rather than being discovered after a new
mod ID is installed. `scripts/legacy.lua` converts plain legacy tables before the
controller pass, preserving the actual visible and source entities. It derives source
direction, mirroring and pause from the saved source, validates prototype/surface/exact
position/force/quality, and checks claims against already-structured records too.

The normalizer builds a separate record map so swapped keys cannot erase entries.
Duplicate IDs and malformed metadata are appended to `storage.legacy_orphans`; unexpected
source/helper references stay outside operational cleanup fields. A valid helper name
alone does not authorize its destruction. Ownership must match and be unique. Missing or
ambiguous metadata protects affected beacons and resources for explicit repair.

The old `deathrattles`, `beacon_pointers` and `watched_beacons` routes are retired before
controller removal. Late legacy callbacks then have no authoritative destination.
`get-beacon-data` keeps the original `pointer` field as a read-compatible alias of the
new manager unit number. Existing schema-1 transactions are retained intact, including
pending work, escrow, pauses and energy reserves. Conversion runs only at a game-available
event boundary; `on_load` merely restores the temporary subscription.

storage.beacons is keyed by visible unit number. storage.locations is an exact
surface/position/force index. storage.callbacks maps destruction registrations to record
IDs and callback kinds. `storage.manager_owners` maps manager unit numbers to visible
record IDs. storage.pending and clone_pending contain finite lifecycle work.
Per-role `escrow` inventories retain actual item stacks until the successor or a native
actor's refund inventory accepts them. Transfers never reconstruct items from summary
counts, and incomplete transfers remain disabled. An explicit adoption retry may accept
a caller-owned refund inventory. Fluid reconciliation tracks only the untransferred
remainder and subtracts each accepted quantity, so pipes draining a paused source cannot
cause retries to duplicate fluid. Processing mismatches need a matching
verified state before protection can be removed; generic repair does not guess recipes.

Source references are authoritative resource custody; metadata absence is never grounds
for destroying a visible beacon or an ambiguous source.

Attachment is shared by normal construction, replacement, adoption and repair. A unique
matching source is adopted before disposable controllers are rebuilt. Repeated attachment
to a healthy record is a no-op. Explicit repair retries protected state without inventing
empty sources over existing ambiguous resources.

Replacement matches the declared family, energy kind, target, quality and exact location.
Native visible replacement owns real module transfer/refunds. Native hidden-source fast
replacement retains real stack and in-flight recipe custody. Energy buffers are captured
numerically and restored because the engine does not preserve every energy-fluid buffer.
Mirrored internal modules are removed before native transfer and rebuilt afterward.
Callback mappings are retired before helper destruction. An unresolved operation disables
the successor and preserves source/refund/snapshot evidence for repair.

Ordinary mining refunds real source contents. Death and ordinary destruction are distinct
from replacement. No routine tick path discovers the world. A full scan occurs only during
init, configuration change or an explicit repair command. Circuit comparisons enable the
ingredient-free manager recipe only while observed and recorded state differ. Its native
recipe-completion event handles power/module transitions. Its one-tick craft duration
prevents duplicate same-tick notifications after removing the ingredient. Ten-tick work services pending operations and
viewed entities only. Saved energy reserves temporarily subscribe to `on_tick` while
present. Each accepted joule is removed once from the reserve; paused sources do not
consume it. Burner heat capacity limits each feed, including after quality changes.

<a id="controller-migration"></a>
## Schema 2 controller conversion

`nsb-internal-recipe.raise_on_crafted` supplies the event ID registered by `control.lua`.
The event must name that recipe and a valid manager. Its unit lookup must resolve to an
attached record whose current manager matches both the entity and unit number. Late
events from retired managers are ignored. `nsb-internal-item` remains a circuit signal;
new power notifications do not insert items or register item destruction callbacks.
Real body/source/helper destruction registrations remain necessary.

Conversion retires legacy power registrations and rebuilds only disposable controllers.
It retains actual sources, pause state, real modules, orientation, processing state,
pending work/clone queues, escrow and energy reserves. Protected and pending records keep
their phase and diagnostic; conversion restores their removal callbacks without retrying
the transfer or enabling them. Invalid attached metadata is protected, not destroyed.
Mappings are retired before helper destruction. Protection also disables the manager,
so an ignored event cannot leave an ingredient-free recipe crafting forever.

Fresh initialization, configuration refresh and explicit adoption/repair establish the
lookup. A same-version schema-1 save can have no configuration event: `on_load` only
binds the existing temporary tick subscription. The first game-available boundary runs
the idempotent conversion; it then releases that subscription unless reserves need it.
A missing schema-2 lookup uses the same repair path. Ordinary schema-2 reload retains
controller identity. Automatic configuration refresh does not retry protected transfers;
`adopt-beacon`, `force_migrations` and `/update_beacons` are explicit repair requests.

Conversion restores the bounded pending/clone work index even when reached through
same-code `on_load`. Protected partial transactions lose only stale scheduling flags.
Missing deadlines cannot become inferred expiration times or trigger nil comparisons;
their state stays protected for explicit diagnosis and repair.

The transition mechanism credits protocol_1903's 2.1 update. See
[candidate verification](testing.md) for event stability,
schema conversion, migration, ESIR, rendered and multiplayer evidence.

<a id="orientation"></a>
## Orientation contract

The source's direction and mirroring are authoritative; the directionless visible beacon
must not overwrite them. The shared orientation adapter handles construction, custom
rotation, copy/paste and blueprint application. Blueprint tags have version1 and identify
blueprint-relative versus resolved world-ghost coordinates. Player pre-build transforms
are applied once; resolved ghost tags survive robot revival. Untagged legacy blueprint
direction cannot be recovered.

Normal interaction checks reach, force and permissions. Remote/editor interaction uses
the selected entity and does not require a nearby character. Scripted transformations
without player pre-build context must use the documented orientation adapter.

Cloning snapshots the source immediately and defers attachment briefly. If native area
cloning supplies its own source, it replaces only the transaction-created copy. Visible-only
and cross-surface clones preserve orientation and reserve custody. Same-surface teleports
move helpers with the visible beacon. Factorio 2.1.23 does not support native cross-surface
beacon teleportation; use cloning for that engine-supported path. Failed movement remains
protected until source and visible beacon have the same surface, position and force.

<a id="information"></a>
## Viewed information

Selection and the opened entity are independent subscriptions. Shared tooltip IDs belong
to this mod only. A beacon is refreshed once per ten-tick viewed batch regardless of viewer
count; events also refresh current views. Closure, disconnect and replacement remove
subscriptions and obsolete owned fields. Other mods' tooltip IDs are never cleared.

Rates are calculated operating requirements, not instantaneous measurements. Runtime
quality-aware power and consumption limits feed the calculation. Optional fluid caps,
stored amount/capacity, temperature and electric drain are separate rows. Fuel storage is
identified by energy-source role; recipe fluid rows stay distinct. Burning fuel remains
visible after queued fuel empties. Positive fractional quantities are retained.
Runtime fluid storages are enumerated by `fluids_count`; `get_fluid_box_prototype`
identifies fuel and spent-fluid roles, including merged prototype arrays. Prototype
indices are never used as runtime storage indices: their namespaces overlap. Spent
energy fluid is shown separately even when the recipe uses the same fluid.

Factorio 2.1.23 runtime tooltip fields target hover information and do not appear inside
the native beacon window in the rendered fixture. A read-only relative panel renders the same row model beside that
window. It has no fuel-management controls. Its roots belong only to this mod and are
destroyed on closure or disconnect; source rows continue updating without world hover.

<a id="verification"></a>
## Verification and open acceptance

scripts/validate.py uses the exact 2.1.23 executable and base-data version and records
explicit PEREL/Things dependencies. scripts/migration.py accepts a real 2.0.77/upstream
1.4.2 donor, loads it under this original-ID contribution, and reloads the resulting save
on private local servers. Fresh historical donors require an explicit verified old engine.
The migration fixture retains original source references as well as numerical snapshots.

See testing.md for executed evidence and pending cases. Source review does not prove
rendered tooltip placement, blueprint transform ordering, multiplayer determinism or
full ESIR compatibility. A passing headless test does not close those acceptance items.
