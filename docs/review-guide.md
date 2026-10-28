# Optional state, orientation and information contribution

Thank you to protocol_1903 for Nonstandard Beacons, to quezler for the original
event-driven approach, and to the contributors credited in the existing README and
changelog. This is a substantial, optional proposal. It does not presume that its scope
or architecture is the direction the maintainer wants, and it does not require adopting
the separate continuation, its name, or ESIR's gameplay changes.

The implementation, annotations, tests, explanatory documentation and additional
translations were developed with substantial Codex AI assistance. They are presented
as contribution work, not as work by the original author. The repository's current
license, author metadata, contact/community/support links, issue routing, original
README and historical changelog are retained. No endorsement is implied.

## What this proposes

| Player or consumer operation | Proposed behavior | Main owner |
| --- | --- | --- |
| Replace a compatible tier or quality | Preserve actual stacks, burning fuel and quality, fluids/temperatures, energy, compatible processing state and orientation; use native visible-module transfer. | `scripts/lifecycle.lua` |
| A new buffer is smaller | Preserve excess energy in a saved reserve and feed it back only as capacity becomes available. | `scripts/lifecycle.lua` |
| A transfer cannot complete | Keep the successor disabled, retain recoverable resources and report the reason; allow explicit idempotent repair. | `scripts/lifecycle.lua`, `scripts/common.lua` |
| Upgrade an existing NSB save | Adopt the actual source before rebuilding disposable controllers; protect uncertain ownership. | `scripts/legacy.lua` |
| Power or modules change | Use upstream's native recipe-completion approach with current-controller ownership validation; settled controllers emit no notifications. | `scripts/power.lua` |
| Place or transform a blueprint | Preserve versioned direction/mirroring tags and resolve blueprint-relative versus world-ghost orientation exactly once. | `scripts/orientation.lua` |
| Rotate in normal, remote or editor view | Resolve the selected entity on the viewed surface; enforce ordinary reach/permission rules while allowing character-free remote/editor interaction. | `scripts/orientation.lua` |
| Hover or open a beacon | Show operating requirement, configured caps, stored contents, fuel quality, thermal/electric details and actual blocking status. Opened panels update independently of hover. | `scripts/information.lua` |
| Construct or transform entities silently from a script | Use documented `adopt-beacon` and `set-beacon-orientation` adapters rather than periodic discovery. | `control.lua`, `docs/api.md` |

All eight locale CFGs are included: English, German, French, Japanese, Polish, Russian,
Simplified Chinese and Traditional Chinese. Additional translations are AI-assisted and
are not presented as native-speaker-reviewed text.

## Suggested review order

1. Read [migration](migration.md) and [source ownership](lifecycle.md). Resource ownership
   and protected recovery are the central invariants.
2. Review `scripts/legacy.lua`, `scripts/lifecycle.lua` and their persistent types in
   `scripts/types.lua`. Visible modules and resource-bearing sources are authoritative;
   internal module copies and controllers are disposable.
3. Review `scripts/power.lua` and `control.lua` for event routing, controller retirement,
   same-version load conversion and bounded subscriptions.
4. Review `scripts/orientation.lua`, then `scripts/information.lua`. Blueprint tags,
   runtime tooltip IDs and per-player opened/selected views have distinct ownership.
5. Use [testing](testing.md) to distinguish new candidate evidence from prior continuation
   comparisons and to reproduce focused cases with explicit engine/dependency inputs.

## Compatibility and deliberate limits

The original mod ID, public remote-interface name, existing function signatures,
prototype names, custom inputs, author metadata and upstream dependency declarations
remain. The extensible `zzz-nonstandard-beacons` mod-data handle remains available.
Private `nsbc` locale/GUI/helper-group names inherited from the tested continuation are
implementation identifiers, not a dependency switch. The blueprint tag remains
`nsb_orientation`.

Replacement families are opt-in consumer prototype declarations and must share an energy
kind. This proposal does not convert burner fuel into fluid/electric energy or change
consumer recipes, costs, slots, range or balance. ESIR is a test consumer, not a new
dependency. No separate fuel-management window is introduced.

Untagged legacy blueprints cannot recover historically omitted direction. Factorio
2.1.23 rejects native cross-surface beacon teleportation; cloning is the supported
cross-surface route. Physical input and the complete blueprint-library UI route are
separate from scripted native action tests and must not be inferred from them.

The version remains upstream's current `2.0.0` for this review branch. Release version,
scope and acceptance remain the maintainer's decision. The historical changelog is not
rewritten to imply these proposed changes were already released.
