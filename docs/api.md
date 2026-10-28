# Consumer API

Declare `~ zzz-nonstandard-beacons` as a non-ordering dependency, as in the original
README. This review branch keeps version 2.0.0; a release version remains the
maintainer's decision. The new adapters below are capabilities of this proposal,
not a claim that the currently published 2.0.0 already provides them.
The visible beacon prototype accepts the upstream effect_receiver, source_recipe and
source_fluidboxes extensions. Custom recipes use categories containing nsb-filler-category
in Factorio 2.1. Use separate families for different energy kinds.

## Existing interface

The interface remains named nonstandard-beacons:

- get-beacon-data(unit_number) returns attachment metadata or nil. LuaEntity references
  must be checked for validity. Metadata is read-only by convention; its source is the
  actual fuel/processing entity. The original `pointer` field remains a compatible
  alias of `manager_unit_number`; controllers themselves remain implementation details.
- force_migrations() runs an adoption/repair pass.
- /update_beacons invokes the same explicit repair pass.

## Adapters

- `adopt-beacon(entity, refund_inventory?)` returns true, or false plus a diagnostic
  string. Call it after silent script construction. Raised construction events are
  handled automatically, including compatible `create_entity{fast_replace=true,
  raise_built=true}` replacements. The optional caller-owned `LuaInventory` receives
  solid overflow during a repair; remaining items stay in the mod's saved inventories.
- set-beacon-orientation(entity, direction, mirrored) returns true, or false plus a
  diagnostic string. It accepts a managed visible beacon or ghost; direction must be
  a cardinal defines.direction value and mirrored must be a boolean.

Scripts placing or transforming blueprints without player pre-build context must call
the orientation adapter with resolved world orientation. The library does not scan for
unannounced script construction.

The nsb_orientation tag contains version=1, space='blueprint' or 'world', direction and
mirrored. Unknown versions are ignored rather than guessed. Do not transform a world tag
again during revival. Export/import retains the tag; old untagged direction is unknowable.

## Replacement and diagnostics

Eligible visible prototypes share fast_replaceable_group and compatible source energy,
recipe and fluid roles. next_upgrade selects the default target; it is separate from the
bidirectional family. Cross-energy conversion is not supported.

A protected record keeps the successor disabled. Its issue explains the failure; a retained
source, refund inventory or transfer snapshot must not be discarded. Resolve incompatibility
or recover overflow through the owning integration, then call adopt-beacon or /update_beacons.
Repair is idempotent. Do not destroy nonempty refund or escrow inventories. A processing
snapshot is cleared only when the surviving source matches it; arbitrary consumed
ingredients cannot safely be reconstructed from a progress percentage. Source alignment
must be restored before a movement failure can be repaired.

No fuel-management window is added. Runtime hover rows and a read-only panel beside the
opened native beacon window carry the same information. Use the source through the existing
interface for controlled integration.

Schema 2 changes internal controller ownership only; public adapter signatures, helper
prototype names and blueprint tags remain unchanged. Consumers must not persist manager
IDs or modify `manager_owners`/callback mappings. Read the current source through
`get-beacon-data`; a controller can be rebuilt while that resource-bearing source remains.
The ingredient-free native manager event requires no new consumer dependency. The
upstream dependencies remain PEREL >= 1.2.3 and Things >= 0.6.1. See
[migration](migration.md) for same-version saves.

The helper retains upstream's `quality_affects_energy_usage=true` crafting-machine policy.
It uses `quality.crafting_machine_energy_usage_multiplier`, not ordinary beacon quality
power savings. Changing that policy would change existing consumer balance. Calculated
information reads the helper's actual quality-aware power and consumption modifiers.
