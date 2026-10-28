-- File map: editor-only records; no runtime side effects.
-- blueprint: docs/lifecycle.md#contract
---@class NSBDefinition
---@field kind "burner"|"fluid"|"heat"|"electric"|"void"
---@field modules boolean
---@field family string|nil
---@field recipe string
---@field min_temperature number|nil
---@field max_temperature number|nil
---@field fluid_layout data.FluidBox[]
---@field energy_fluid data.FluidBox|nil
---@field spent_fluid data.FluidBox|nil

---@class NSBOrientation
---@field version integer
---@field space "blueprint"|"world"
---@field direction defines.direction
---@field mirrored boolean

---@class NSBRecord
---@field id uint64
---@field beacon LuaEntity
---@field source LuaEntity|nil Real resource owner, never a disposable controller.
---@field manager LuaEntity|nil
---@field manager_unit_number uint64|nil Saved separately so invalid controllers can retire their lookup.
---@field pointer uint64|nil Upstream-compatible alias of manager_unit_number; never a separate owner.
---@field legacy_helpers table<string, LuaEntity>|nil Unexpected legacy references retained for diagnosis, never destroyed as controllers.
---@field legacy_source LuaEntity|nil Unverified source reference, excluded from operational mutation.
---@field ownership_issue boolean|nil Explicit repair must revalidate legacy ownership before releasing protection.
---@field monitor LuaEntity|nil
---@field mimic LuaEntity|nil
---@field name string
---@field surface_index uint32
---@field position MapPosition
---@field force_index uint32
---@field quality string
---@field direction defines.direction
---@field mirrored boolean
---@field phase "attached"|"pending"|"protected"
---@field issue string|nil
---@field callbacks table<uint64, boolean>
---@field tooltip_ids table<string, uint32>
---@field deadline uint32|nil
---@field refund LuaInventory|nil Solid overflow retained until successfully refunded.
---@field escrow table<defines.inventory, LuaInventory>|nil Real stacks retained by inventory role during transfer.
---@field refund_actor NSBRefundActor|nil Last native actor able to receive overflow.
---@field energy_reserve number|nil Preserved joules exceeding the successor buffer capacity.
---@field reserve_capacity number|nil Observed stable capacity; prevents deferred engine clamping from erasing reserves.
---@field resume_disabled boolean|nil Source pause predating this mod's protection/deconstruction pause.
---@field created_tick MapTick|nil Distinguishes fresh item builds from adoption and blueprint paste.
---@field replaced_from uint64|nil One-shot native opened-window handoff.
---@field handoff NSBBuildIntent|NSBUpgradeIntent|nil Exact native build/upgrade intent authorizing replacement.
---@field transfer_snapshot NSBTransferSnapshot|nil Unverified resource custody; never cleared by a generic repair.

---@class NSBTransferSnapshot
---@field energy number
---@field fluids table<FluidStorageIndex, Fluid>
---@field remaining_fluids table<FluidStorageIndex, Fluid>|nil Only untransferred quantities; never replay full diagnostic totals.
---@field progress number
---@field bonus number
---@field result_quality LuaQualityPrototype|nil
---@field temperature number|nil
---@field burning {name: LuaItemPrototype, quality: LuaQualityPrototype}|nil
---@field remaining number|nil
---@field burner_heat number|nil

---@class NSBUpgradeIntent
---@field player_index uint32|nil
---@field name string|nil
---@field quality string|nil
---@field tick uint32

---@class NSBBuildIntent: NSBUpgradeIntent
---@field blueprint boolean
---@field direction defines.direction
---@field flip_horizontal boolean
---@field flip_vertical boolean
---@field mirror boolean|nil
---@field position MapPosition|nil
---@field surface_index uint32|nil
---@field force_index uint32|nil

---@class NSBRefundActor
---@field player_index uint32|nil
---@field robot LuaEntity|nil
---@field platform LuaSpacePlatform|nil

---@class NSBAttachOptions
---@field adopting boolean|nil
---@field predecessor NSBRecord|nil
---@field buffer LuaInventory|nil Caller-owned refund destination, never persisted.
---@field actor NSBRefundActor|nil

---@class NSBClonePending
---@field entity LuaEntity
---@field key string
---@field source LuaEntity|nil
---@field copied_source LuaEntity|nil
---@field resume_disabled boolean
---@field energy_reserve number|nil
---@field reserve_capacity number|nil
---@field deadline MapTick

---@alias NSBCallbackKind "beacon"|"source"|"helper"
---@alias NSBBuildEvent EventData.on_built_entity|EventData.on_robot_built_entity|EventData.on_space_platform_built_entity|EventData.script_raised_built|EventData.script_raised_revive
---@alias NSBRemovalEvent EventData.on_player_mined_entity|EventData.on_robot_mined_entity|EventData.on_space_platform_mined_entity|EventData.script_raised_destroy|EventData.on_entity_died

---@class NSBWorkItem
---@field kind "pending"|"clone"
---@field id uint64
---@field key string

---@class NSBWorkQueue
---@field head integer
---@field tail integer
---@field items table<integer, NSBWorkItem>
---@field seen table<string, boolean>

---@class NSBTooltipRow
---@field id string
---@field name LocalisedString
---@field value LocalisedString

---@class NSBStorage
---@field schema integer
---@field manager_owners table<uint64, uint64> Disposable controller unit number to authoritative beacon record ID.
---@field beacons table<uint64, NSBRecord>
---@field locations table<string, uint64>
---@field callbacks table<uint64, {id: uint64, kind: NSBCallbackKind|"power"}> Legacy power entries are retired during schema conversion.
---@field intents table<uint32, NSBBuildIntent>
---@field upgrades table<uint64, NSBUpgradeIntent>
---@field pending table<uint64, boolean>
---@field viewers table<uint32, {selected: uint64|nil, opened: uint64|nil}>
---@field watched table<uint64, boolean>
---@field recent_closed table<uint32, {id: uint64, tick: MapTick}> Same-tick native replacement closures only.
---@field clone_pending table<uint64, NSBClonePending>
---@field clone_locations table<string, uint64>
---@field energy_reserves table<uint64, boolean>
---@field work NSBWorkQueue
---@field legacy_orphans {key: any, record: any, issue: string}[] Append-only diagnostic quarantine; conversion never overwrites earlier evidence.

---@class NSBLegacyRecord
---@field beacon LuaEntity|nil
---@field source LuaEntity|nil
---@field manager LuaEntity|nil
---@field monitor LuaEntity|nil
---@field mimic LuaEntity|nil
---@field pointer uint64|nil Present in upstream 2.0.0, absent in upstream 1.4.2.

---@type NSBStorage
storage = storage
return {}
