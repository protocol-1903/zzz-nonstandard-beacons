-- NSB FILE MAP
-- owns: sole event dispatcher, public adapters and temporary migration/reserve subscription
-- loaded_by: Factorio control stage
-- cadence: events; 10-tick viewed/lifecycle batch; per-tick reserves only when present
-- forwarded_events: lifecycle, orientation, information handlers below
-- storage_roots: NSBStorage, owned by the respective feature modules
-- gui_ids: nsbc-source-information (information module)
-- remote_interfaces: nonstandard-beacons
-- rebuild_on: init/configuration and explicit repair; on_load schedules old-schema conversion
-- blueprint: docs/lifecycle.md#contract
local common = require("scripts.common")
local lifecycle = require("scripts.lifecycle")
local power = require("scripts.power")
local orientation = require("scripts.orientation")
local information = require("scripts.information")
local legacy = require("scripts.legacy")

---@param tick MapTick
local function ensure_controllers(tick)
  if lifecycle.upgrade_controllers() then information.initialize(tick) end
end

-- Event ordering around the first loaded tick is not assumed. All dispatch paths
-- establish the controller schema before handling input, removals or recipe events.
---@generic T: {tick: MapTick}
---@param events uint32|string|(uint32|string)[]
---@param handler fun(event: T)
local function on_event(events, handler)
  script.on_event(events, function(event)
    ensure_controllers(event.tick)
    handler(event)
  end)
end

---@param event EventData.on_tick
local function reserve_tick(event)
  ensure_controllers(event.tick)
  lifecycle.feed_reserves(event.tick)
  if not next(storage.energy_reserves) then script.on_event(defines.events.on_tick, nil) end
end
local function reserve_schedule()
  local needed = storage.schema ~= 2 or not storage.manager_owners
    or (storage.energy_reserves and next(storage.energy_reserves))
  script.on_event(defines.events.on_tick, needed and reserve_tick or nil)
end

local function initialize(repair)
  local tick = game.tick -- Unticked init/configuration boundary; never read during loading.
  lifecycle.initialize(tick, repair == true)
  information.initialize(tick)
  reserve_schedule()
end
script.on_init(function() initialize(false) end)
---@param event ConfigurationChangedData
script.on_configuration_changed(function(event)
  local change = event.mod_changes[script.mod_name]
  legacy.require_supported_version(change and change.old_version)
  initialize(false)
end)
script.on_load(reserve_schedule) -- Rebind local scheduling only; no saved-state mutation.
on_event(assert(prototypes.recipe["nsb-internal-recipe"].on_crafted_event), function(event)
  if power.crafted(event) then information.update(event.tick) end
end)

local function built(event)
  lifecycle.built(event)
  orientation.built(event)
  information.replaced(event.entity, event.tick)
  information.update(event.tick)
  reserve_schedule()
end
on_event({defines.events.on_built_entity, defines.events.on_robot_built_entity,
  defines.events.on_space_platform_built_entity, defines.events.script_raised_built,
  defines.events.script_raised_revive}, built)
on_event({defines.events.on_player_mined_entity, defines.events.on_robot_mined_entity,
  defines.events.on_space_platform_mined_entity, defines.events.script_raised_destroy,
  defines.events.on_entity_died}, lifecycle.removed)
on_event(defines.events.on_object_destroyed, function(event)
  lifecycle.destroyed(event)
  information.update(event.tick)
end)
on_event(defines.events.on_marked_for_upgrade, lifecycle.marked)
on_event(defines.events.on_cancelled_upgrade, function(event)
  storage.upgrades[event.entity.unit_number] = nil
end)
on_event(defines.events.on_pre_build, orientation.pre_build)
on_event(defines.events.on_player_setup_blueprint, orientation.setup_blueprint)
on_event(defines.events.on_blueprint_settings_pasted, orientation.built)
on_event(defines.events.on_entity_settings_pasted, orientation.pasted)
on_event(defines.events.on_entity_cloned, lifecycle.cloned)
on_event(defines.events.script_raised_teleported, lifecycle.teleported)
on_event("nsb-beacon-rotate", function(event) orientation.rotate(event, false); information.update(event.tick) end)
on_event("nsb-beacon-rotate-reverse", function(event) orientation.rotate(event, true); information.update(event.tick) end)
on_event({defines.events.on_marked_for_deconstruction, defines.events.on_cancelled_deconstruction}, function(event)
  local record = common.managed(event.entity) and storage.beacons[event.entity.unit_number]
  if record and common.valid(record.source) then
    record.source.disabled_by_script = record.phase ~= "attached" or record.resume_disabled or event.entity.to_be_deconstructed()
    information.refresh(record)
  end
end)
on_event({defines.events.on_selected_entity_changed, defines.events.on_gui_opened,
  defines.events.on_gui_closed, defines.events.on_player_joined_game, defines.events.on_player_left_game,
  defines.events.on_player_controller_changed, defines.events.on_player_changed_surface}, information.changed)
on_event(defines.events.on_player_removed, function(event)
  storage.viewers[event.player_index] = nil
  information.update(event.tick)
end)
script.on_nth_tick(10, function(event)
  ensure_controllers(event.tick)
  -- Work is limited to pending transactions and currently viewed entities, never the world.
  lifecycle.expire(event.tick)
  reserve_schedule()
  information.update(event.tick)
end)

commands.add_command("update_beacons", {"nsbc.update-help"}, function()
  initialize(true)
end)
remote.add_interface("nonstandard-beacons", {
  ["get-beacon-data"] = function(unit_number) return storage.beacons[unit_number] end,
  ["force_migrations"] = function() initialize(true) end,
  ["adopt-beacon"] = function(entity, refund_inventory)
    local tick = game.tick -- Public adapter has no engine event payload.
    ensure_controllers(tick)
    local ok, reason = lifecycle.attach(entity, tick, {adopting = true, buffer = refund_inventory})
    reserve_schedule()
    information.replaced(entity, tick)
    information.update(tick)
    return ok, reason
  end,
  ["set-beacon-orientation"] = function(entity, direction, mirrored)
    ensure_controllers(game.tick)
    return orientation.set(entity, direction, mirrored)
  end
})
