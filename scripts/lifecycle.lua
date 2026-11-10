-- NSB FILE MAP
-- owns: source custody, adoption, replacement, repair and bounded lifecycle work
-- loaded_by: control.lua
-- cadence: lifecycle events; 64 queued operations/10 ticks; active reserves/tick
-- forwarded_events: built, removed, marked, destroyed, cloned, teleported
-- storage_roots: beacons, locations, pending, upgrades, clone_pending, clone_locations, work, energy_reserves
-- gui_ids: none
-- remote_interfaces: adapters routed by control.lua
-- rebuild_on: init, configuration change and explicit adoption/repair
-- blueprint: docs/lifecycle.md#contract
local common = require("scripts.common")
local power = require("scripts.power")
local legacy = require("scripts.legacy")
---@class NSBLifecycle
local M = {}

-- One finite queue owns deferred lifecycle work. Requeueing keeps full reserves
-- fair without scanning idle beacons or letting a large upgrade burst stall a tick.
---@param kind "pending"|"clone"
---@param id uint64
local function enqueue(kind, id)
  local queue = storage.work
  local key = kind .. ":" .. id
  if queue.seen[key] then return end
  queue.tail = queue.tail + 1
  queue.items[queue.tail] = {kind = kind, id = id, key = key}
  queue.seen[key] = true
end

---@param beacon LuaEntity
---@return NSBRecord
local function record_for(beacon)
  return {id = beacon.unit_number, beacon = beacon, name = beacon.name,
    position = beacon.position, surface_index = beacon.surface.index, force_index = beacon.force.index,
    quality = beacon.quality.name, direction = defines.direction.north, mirrored = false,
    phase = "attached", callbacks = {}, tooltip_ids = {}}
end

---@param beacon LuaEntity
---@param name string|string[]
---@return LuaEntity[]
local function colocated(beacon, name)
  local result = {}
  for _, entity in pairs(beacon.surface.find_entities_filtered{name = name, position = beacon.position, force = beacon.force}) do
    if entity.position.x == beacon.position.x and entity.position.y == beacon.position.y then result[#result + 1] = entity end
  end
  return result
end

---@param record NSBRecord
local function forget(record)
  power.retire(record)
  storage.beacons[record.id], storage.pending[record.id], storage.upgrades[record.id] = nil, nil, nil
  storage.energy_reserves[record.id] = nil
  local key = common.key(record.surface_index, record.position, record.force_index)
  if storage.locations[key] == record.id then storage.locations[key] = nil end
end

-- Actual stacks stay in engine inventories throughout a handoff. Keeping one
-- inventory per role prevents a smaller successor silently spilling rich items.
---@param record NSBRecord
---@param buffer LuaInventory|nil
---@return boolean
local function restore_stacks(record, buffer)
  local remaining = false
  for index, inventory in pairs(record.escrow or {}) do
    local destination = common.valid(record.source) and record.source.get_inventory(index)
    if destination then destination.transfer_from_inventory(inventory) end
    if buffer and buffer.valid then buffer.transfer_from_inventory(inventory) end
    if inventory.is_empty() then inventory.destroy(); record.escrow[index] = nil else remaining = true end
  end
  if record.refund then
    if record.refund.valid then
      if buffer and buffer.valid and buffer ~= record.refund then buffer.transfer_from_inventory(record.refund) end
      if record.refund.is_empty() then record.refund.destroy(); record.refund = nil else remaining = true end
    else record.refund = nil end
  end
  return not remaining
end

---@param actor NSBRefundActor|nil
---@return LuaInventory|nil
local function refund_destination(actor)
  if not actor then return nil end
  if actor.player_index then
    local player = game.get_player(actor.player_index)
    return player and player.get_main_inventory()
  elseif common.valid(actor.robot) then return actor.robot.get_inventory(defines.inventory.robot_cargo)
  elseif actor.platform and actor.platform.valid and common.valid(actor.platform.hub) then
    return actor.platform.hub.get_inventory(defines.inventory.hub_main)
  end
end

---@param record NSBRecord
---@return boolean, string|nil
local function reconcile(record)
  local snapshot, source = record.transfer_snapshot, record.source
  if not snapshot then return true end
  if not common.valid(source) then return false, "captured transfer has no surviving source" end
  -- Verify processing before changing custody. A pipe can drain a disabled source;
  -- replaying the original fluid snapshot on retries would duplicate that drain.
  if math.abs(source.crafting_progress - snapshot.progress) > 0.0000001 or
      math.abs(source.bonus_progress - snapshot.bonus) > 0.0000001 or
      source.result_quality ~= snapshot.result_quality then
    return false, "processing state requires manual reconciliation; captured state retained"
  end
  if not snapshot.remaining_fluids then return false, "legacy transfer lacks verified fluid remainder; inspect captured state" end
  local incomplete = false
  for index, fluid in pairs(snapshot.remaining_fluids) do
    local current = source.get_fluid(index)
    if current and current.name ~= fluid.name then
      incomplete = true
    else
      local accepted = source.add_fluid(index, fluid)
      fluid.amount = math.max(0, fluid.amount - accepted)
      if fluid.amount <= 0.00001 then snapshot.remaining_fluids[index] = nil else incomplete = true end
    end
  end
  if incomplete then return false, "fluid remainder retained until matching storage has capacity" end
  record.transfer_snapshot = nil
  return true
end

---@param record NSBRecord
---@param beacon LuaEntity
---@param buffer LuaInventory|nil
---@return boolean, string|nil
local function replace_source(record, beacon, buffer)
  if record.transfer_snapshot then
    return false, "an earlier transfer still requires reconciliation; source retained"
  end
  local source = record.source
  if not common.valid(source) then return false, "predecessor source is missing" end
  if common.entity_key(source) ~= common.entity_key(beacon) then return false, "predecessor source is not aligned with successor" end
  if record.refund and record.refund.valid and not record.refund.is_empty() then
    return false, "prior solid overflow remains in the recoverable refund inventory"
  end
  if record.escrow and next(record.escrow) then return false, "prior inventory transfer remains unresolved" end
  record.direction, record.mirrored = source.direction, source.mirroring
  if source.name == beacon.name .. "-source" and source.quality.name == beacon.quality.name then return true end
  local old_name = source.name:gsub("-source$", "")
  local before, after = common.definitions[old_name], common.definitions[beacon.name]
  if not before or not common.compatible(old_name, beacon.name) or before.recipe ~= after.recipe then
    return false, "source family, energy type or recipe is incompatible"
  end
  local target = prototypes.entity[beacon.name .. "-source"]
  -- Native replacement owns real stacks and consumed recipe ingredients. Energy
  -- source buffers are NOT all transferred by the engine, so preserve their scalar
  -- state separately and restore it before allowing the successor to run.
  local snapshot = {energy = source.energy, fluids = {}, remaining_fluids = {}, progress = source.crafting_progress,
    bonus = source.bonus_progress, result_quality = source.result_quality}
  for index = 1, source.fluids_count do snapshot.fluids[index] = source.get_fluid(index) end
  if before.kind == "heat" then snapshot.temperature = source.temperature end
  if source.burner then
    snapshot.burning, snapshot.remaining, snapshot.burner_heat = source.burner.currently_burning,
      source.burner.remaining_burning_fuel, source.burner.heat
  end
  local old_boxes, new_boxes = source.prototype.fluidbox_prototypes, target.fluidbox_prototypes
  if #old_boxes ~= #new_boxes then return false, "fluid storage roles differ" end
  for index, old in pairs(old_boxes) do
    local new = new_boxes[index]
    if old.production_type ~= new.production_type or old.filter ~= new.filter then
      return false, "fluid storage filter, role or capacity is incompatible"
    end
  end
  if before.energy_fluid and after.energy_fluid and before.energy_fluid.volume > after.energy_fluid.volume then
    return false, "fuel fluid capacity decreases; source retained"
  end
  if before.spent_fluid and after.spent_fluid and before.spent_fluid.volume > after.spent_fluid.volume then
    return false, "spent fluid capacity decreases; source retained"
  end
  for index, box in pairs(before.fluid_layout) do
    if not after.fluid_layout[index] or box.volume > after.fluid_layout[index].volume then
      return false, "recipe fluid capacity decreases; source retained"
    end
  end
  -- Keep the old source until the engine accepts an atomic replacement. Synthetic
  -- modules must not enter the native refund stream on a module-slot downgrade.
  local modules = source.get_module_inventory()
  if modules then modules.clear() end
  source.disabled_by_script = true
  record.escrow = {}
  for _, index in ipairs{defines.inventory.fuel, defines.inventory.burnt_result, defines.inventory.crafter_input, defines.inventory.crafter_output} do
    local inventory = source.get_inventory(index)
    if inventory and not inventory.is_empty() and not record.escrow[index] then
      local held = game.create_inventory(#inventory)
      record.escrow[index] = held
      held.transfer_from_inventory(inventory)
      if not inventory.is_empty() then return false, "source inventory could not be escrowed completely" end
    end
  end
  local own_buffer = not buffer and game.create_inventory(1000) or nil
  if own_buffer then record.refund = own_buffer end -- Custody survives every early return.
  buffer = buffer or own_buffer
  local marked = source.order_upgrade{target = {name = target.name, quality = beacon.quality}, force = source.force}
  local successor = marked and source.apply_upgrade(nil, buffer) or nil
  if not successor and source.valid then
    successor = source.surface.create_entity{name = target.name, position = source.position,
      force = source.force, quality = beacon.quality, direction = record.direction, mirror = record.mirrored,
      fast_replace = true, spill = false}
  end
  if not successor or source.valid then
    if successor and successor ~= source then common.destroy(successor) end
    if own_buffer then record.refund = own_buffer end
    restore_stacks(record)
    return false, "engine refused the source upgrade; predecessor retained"
  end
  record.source = successor
  successor.disabled_by_script = true
  successor.direction, successor.mirroring = record.direction, record.mirrored
  local stacks_restored = restore_stacks(record, buffer)
  successor.energy = snapshot.energy
  if snapshot.temperature then successor.temperature = snapshot.temperature end
  if successor.burner then
    successor.burner.currently_burning = snapshot.burning
    successor.burner.remaining_burning_fuel = snapshot.remaining
    successor.burner.heat = snapshot.burner_heat
  end
  record.energy_reserve = (record.energy_reserve or 0) + math.max(0, snapshot.energy - successor.energy)
  if successor.energy < snapshot.energy then record.reserve_capacity = successor.energy end
  for index, fluid in pairs(snapshot.fluids) do
    local accepted = successor.set_fluid(index, fluid)
    if math.abs(accepted - fluid.amount) > 0.00001 then
      snapshot.remaining_fluids[index] = {name = fluid.name, amount = math.max(0, fluid.amount - accepted), temperature = fluid.temperature}
    end
  end
  if next(snapshot.remaining_fluids) then
    record.transfer_snapshot = snapshot
    return false, "fluid restoration incomplete; untransferred remainder retained"
  end
  if before.recipe ~= "nsb-filler-recipe" and
      (math.abs(successor.crafting_progress - snapshot.progress) > 0.0000001 or
       math.abs(successor.bonus_progress - snapshot.bonus) > 0.0000001 or
       successor.result_quality ~= snapshot.result_quality) then
    record.transfer_snapshot = snapshot
    return false, "native processing-state preservation failed; captured state retained"
  end
  if not stacks_restored then
    return false, "solid overflow retained in role inventories; retry adoption with a refund inventory"
  end
  if record.refund and record.refund.valid and not record.refund.is_empty() then
    return false, "solid overflow retained in the recoverable refund inventory"
  end
  return true
end

---@param beacon LuaEntity
---@param tick MapTick
---@param options NSBAttachOptions|nil
---@return boolean, string|nil
function M.attach(beacon, tick, options)
  if not common.managed(beacon) then return false, "entity is not a managed beacon" end
  options = options or {}
  local existing = storage.beacons[beacon.unit_number]
  if existing and not options.adopting and existing.phase == "attached" and common.valid(existing.source) and common.entity_key(existing.source) == common.entity_key(beacon) and common.valid(existing.manager) and
      (not common.definitions[beacon.name].modules or (common.valid(existing.monitor) and common.valid(existing.mimic))) then return true end
  local key = common.entity_key(beacon)
  local prior = options.predecessor or storage.beacons[storage.locations[key]]
  local record = existing or record_for(beacon)
  record.refund_actor = options.actor or record.refund_actor
  local buffer = options.buffer or refund_destination(record.refund_actor)
  if common.valid(record.source) and common.entity_key(record.source) ~= key then
    common.protect(record, "source location or force differs; restore alignment before repair")
    return false, record.issue
  end
  if existing and existing.phase == "protected" and options.adopting then
    -- Repair is an explicit retry, not permission to erase unresolved resources.
    local owned, ownership_reason = legacy.can_repair(existing)
    if not owned then return false, ownership_reason end
    local reconciled, reason = reconcile(existing)
    if not reconciled then return false, reason end
    if not restore_stacks(existing, buffer) then return false, "solid overflow remains in recoverable inventories" end
    existing.phase, existing.issue = "attached", nil
    if common.valid(existing.source) and (existing.source.name ~= beacon.name .. "-source" or existing.source.quality.name ~= beacon.quality.name) then
      local ok, reason = replace_source(existing, beacon, buffer)
      if not ok then common.protect(existing, reason); return false, reason end
    end
  end
  if prior and prior.id ~= record.id then
    if common.valid(prior.beacon) and not options.predecessor then
      record.phase = "pending"
      beacon.disabled_by_script = true
      storage.beacons[record.id] = record
      return false, "another live beacon owns this exact source location"
    end
    if not options.predecessor and not options.adopting and
        (not prior.handoff or prior.handoff.name ~= beacon.name or prior.handoff.quality ~= beacon.quality.name) then
      common.protect(record, "successor does not match recorded build/upgrade intent")
      storage.beacons[record.id] = record
      return false, record.issue
    end
    record.source, record.direction, record.mirrored = prior.source, prior.direction, prior.mirrored
    record.replaced_from = prior.id
    record.resume_disabled = prior.resume_disabled
    if record.resume_disabled == nil and common.valid(prior.source) then record.resume_disabled = prior.source.disabled_by_script end
    record.refund_actor = options.actor or prior.refund_actor
    local ok, reason = replace_source(prior, beacon, buffer or refund_destination(record.refund_actor))
    record.source, record.refund, record.transfer_snapshot, record.energy_reserve, record.reserve_capacity =
      prior.source, prior.refund, prior.transfer_snapshot, prior.energy_reserve, prior.reserve_capacity
    record.escrow = prior.escrow
    forget(prior)
    if not ok then common.protect(record, reason) else record.phase = "attached" end
  elseif not common.valid(record.source) then
    local candidates = colocated(beacon, beacon.name .. "-source")
    local matches = {}
    for _, source in pairs(candidates) do
      if source.quality.name == beacon.quality.name then matches[#matches + 1] = source end
    end
    if #candidates > 1 or (#candidates > 0 and #matches == 0) then
      common.protect(record, "ambiguous source adoption; existing sources preserved")
    elseif #matches == 1 then
      record.source = matches[1]
      record.resume_disabled = record.source.disabled_by_script
      record.direction, record.mirrored = record.source.direction, record.source.mirroring
    else
      record.source = beacon.surface.create_entity{name = beacon.name .. "-source",
        position = beacon.position, force = beacon.force, quality = beacon.quality,
        direction = record.direction, mirror = record.mirrored}
      record.created_tick = tick
      if not record.source then common.protect(record, "source construction failed") end
    end
  end
  storage.beacons[record.id], storage.locations[key] = record, record.id
  if record.phase == "protected" then return false, record.issue end
  -- Adoption destroys only disposable controllers after a unique source is secured.
  power.retire(record)
  for _, helper in pairs(colocated(beacon, {"nsb-internal-manager", "nsb-internal-monitor", "nsb-internal-mimic"})) do common.destroy(helper) end
  record.phase, record.issue = "attached", nil
  record.source.destructible = false
  record.source.disabled_by_script = record.resume_disabled or beacon.to_be_deconstructed()
  local ok, reason = power.attach(record)
  if record.energy_reserve and record.energy_reserve > 0 then
    storage.energy_reserves[record.id] = true
  end
  if not ok then common.protect(record, reason) end
  if ok then record.ownership_issue = nil end
  return ok, reason
end

---@param record NSBRecord
local function refresh_controller(record)
  local definition = common.valid(record.beacon) and common.definitions[record.beacon.name]
  local aligned = definition and common.valid(record.source)
    and record.source.name == record.beacon.name .. "-source"
    and record.source.quality == record.beacon.quality
    and common.entity_key(record.source) == common.entity_key(record.beacon)
  if aligned then
    local ok, reason = power.attach(record)
    if not ok then common.protect(record, reason) end
  else
    power.retire(record)
    power.watch_owners(record)
    common.protect(record, "controller conversion needs a matching source and current definition")
  end
end

local function initialize_storage()
  storage.beacons, storage.locations = storage.beacons or {}, storage.locations or {}
  storage.callbacks, storage.intents = storage.callbacks or {}, storage.intents or {}
  storage.upgrades, storage.pending = storage.upgrades or {}, storage.pending or {}
  storage.clone_pending, storage.clone_locations = storage.clone_pending or {}, storage.clone_locations or {}
  storage.energy_reserves = storage.energy_reserves or {}
  storage.work = storage.work or {head = 1, tail = 0, items = {}, seen = {}}
  storage.viewers, storage.watched = storage.viewers or {}, storage.watched or {}
end

---@return boolean converted
function M.upgrade_controllers()
  if storage.schema == 2 and storage.manager_owners then return false end
  -- blueprint-ref: docs/lifecycle.md#controller-migration
  -- Conversion owns controllers only. In particular it must not call adoption:
  -- adoption may retry protected resource transfers or resume a paused source.
  initialize_storage()
  legacy.normalize()
  storage.manager_owners = {}
  for registration, callback in pairs(storage.callbacks) do
    if callback.kind == "power" then storage.callbacks[registration] = nil end
  end
  for _, record in pairs(storage.beacons) do
    record.callbacks = record.callbacks or {}
    if record.phase == "attached" then
      refresh_controller(record)
    else
      power.retire(record)
      power.watch_owners(record)
    end
  end
  -- Same-code on_load conversion does not pass through initialize(). Rebuild
  -- the bounded work index here as well, retaining coherent transaction records
  -- while dropping scheduling for partial records already put in protection.
  for id in pairs(storage.pending) do
    local record = storage.beacons[id]
    if record and record.phase == "pending" then enqueue("pending", id)
    else storage.pending[id] = nil end
  end
  for id in pairs(storage.clone_pending) do enqueue("clone", id) end
  storage.schema = 2
  return true
end

---@param tick MapTick
---@param repair boolean|nil Explicit commands may retry protected resources; automatic migration may not.
function M.initialize(tick, repair)
  initialize_storage()
  for id in pairs(storage.pending) do enqueue("pending", id) end
  for id in pairs(storage.clone_pending) do enqueue("clone", id) end
  local converted = M.upgrade_controllers()
  -- A deliberate migration/repair pass is the only world scan, never a tick path.
  for _, surface in pairs(game.surfaces) do
    for name in pairs(common.definitions) do
      for _, beacon in pairs(surface.find_entities_filtered{name = name}) do
        local existing = storage.beacons[beacon.unit_number]
        if repair or not existing then
          M.attach(beacon, tick, {adopting = true})
        elseif existing.phase == "attached" and not converted then
          -- A configuration refresh may rebuild wiring, but must not release a
          -- source pause set since attachment or retry a protected transaction.
          refresh_controller(existing)
        end
      end
    end
  end
end

---@param event NSBBuildEvent
function M.built(event)
  if not common.managed(event.entity) then return end
  local prior = storage.beacons[storage.locations[common.entity_key(event.entity)]]
  local scripted = event.name == defines.events.script_raised_built and prior and not common.valid(prior.beacon)
    and prior.phase == "attached" and common.compatible(prior.name, event.entity.name)
  M.attach(event.entity, event.tick, {predecessor = scripted and prior or nil,
    actor = {player_index = event.player_index, robot = event.robot, platform = event.platform}})
end

---@param event EventData.on_marked_for_upgrade
function M.marked(event)
  if not common.managed(event.entity) then return end
  local target, quality = event.entity.get_upgrade_target()
  if target then storage.upgrades[event.entity.unit_number] = {name = target.name, quality = quality.name, tick = event.tick, player_index = event.player_index} end
end

---@param event NSBRemovalEvent
function M.removed(event)
  local beacon = event.entity
  if not common.managed(beacon) then return end
  local record = storage.beacons[beacon.unit_number]
  if not record then return end -- Removal can follow an already committed handoff.
  local upgrade_event = event.name == defines.events.on_robot_mined_entity or event.name == defines.events.on_space_platform_mined_entity or event.name == defines.events.script_raised_destroy
  local intent = (upgrade_event and storage.upgrades[record.id]) or (event.player_index and storage.intents[event.player_index])
  local player_match = intent and intent.tick == event.tick and intent.position and
    intent.position.x == record.position.x and intent.position.y == record.position.y and
    intent.surface_index == record.surface_index and intent.force_index == record.force_index
  if event.name ~= defines.events.on_entity_died and intent and common.compatible(record.name, intent.name) and (upgrade_event or player_match) then
    record.handoff = intent
    for _, successor in pairs(colocated(beacon, intent.name)) do
      if successor.unit_number ~= record.id and successor.quality.name == intent.quality then
        M.attach(successor, event.tick, {predecessor = record, buffer = event.buffer})
        return
      end
    end
    record.phase, record.deadline = "pending", event.tick + 2
    if common.valid(record.source) then
      record.resume_disabled = record.source.disabled_by_script
      record.source.disabled_by_script = true
    end
    storage.pending[record.id] = true
    enqueue("pending", record.id)
    return
  end
  -- Ordinary mining uses native mining to preserve rich stacks and in-craft refunds.
  power.retire(record)
  if event.name == defines.events.on_entity_died then
    -- Death destroys the source's contents just as a native machine's death does.
    -- A refund inventory must not strand an immortal, invisible resource owner.
    if record.refund and record.refund.valid then record.refund.destroy() end
    for _, inventory in pairs(record.escrow or {}) do inventory.destroy() end
    common.destroy(record.source)
    forget(record)
    return
  end
  if not restore_stacks(record, event.buffer) then
    common.protect(record, "solid overflow retained after removal")
    return
  end
  if record.refund and record.refund.valid and not record.refund.is_empty() then
    if event.buffer then event.buffer.transfer_from_inventory(record.refund) end
    if not record.refund.is_empty() then
      common.protect(record, "solid overflow retained after removal")
      return
    end
    record.refund.destroy()
    record.refund = nil
  end
  if common.valid(record.source) then
    local modules = record.source.get_module_inventory()
    if modules then modules.clear() end
    if event.buffer then
      local refund = game.create_inventory(1000)
      local mined = record.source.mine{inventory = refund, raise_destroyed = false}
      event.buffer.transfer_from_inventory(refund)
      if not refund.is_empty() then record.refund = refund else refund.destroy() end
      if not mined or record.refund then
        common.protect(record, "mining refund incomplete; source retained")
        return
      end
    else common.destroy(record.source) end
  end
  forget(record)
end

---@param event EventData.on_object_destroyed
function M.destroyed(event)
  local callback = storage.callbacks[event.registration_number]
  if not callback then return end
  storage.callbacks[event.registration_number] = nil
  local record = storage.beacons[callback.id]
  if not record then return end
  record.callbacks[event.registration_number] = nil
  if callback.kind == "power" then return -- Retired schema-1 registrations are never rearmed.
  elseif callback.kind == "source" then common.protect(record, "source removed outside attachment lifecycle")
  elseif callback.kind == "helper" then common.protect(record, "controller removed; use /update_beacons to repair")
  elseif callback.kind == "beacon" and record.phase == "attached" then
    if common.valid(record.source) then record.source.disabled_by_script = true end
    record.phase, record.deadline = "pending", event.tick + 2
    storage.pending[record.id] = true
    enqueue("pending", record.id)
  end
end

---@param tick MapTick
function M.feed_reserves(tick)
  -- This temporary per-tick subscription prevents flicker in buffers smaller than
  -- ten operating ticks. It visits only saved surplus, never ordinary sources.
  -- Accepted joules leave custody exactly once, including after save/reload.
  for id in pairs(storage.energy_reserves) do
    local record = storage.beacons[id]
    if not record or not record.energy_reserve or record.energy_reserve <= 0.000001 then
      storage.energy_reserves[id] = nil
    elseif record.phase == "attached" and common.valid(record.source) and not record.source.disabled_by_script then
      local before = record.source.energy
      -- A burner can temporarily accept more joules than its quality buffer keeps
      -- at the next engine update. Use its native heat capacity; other source kinds
      -- use the stable capacity observed during replacement.
      local burner = record.source.burner
      local capacity = burner and burner.heat_capacity or record.reserve_capacity or before
      local available = math.max(0, capacity - before)
      record.source.energy = before + math.min(available, record.energy_reserve)
      local accepted = record.source.energy - before
      record.energy_reserve = math.max(0, record.energy_reserve - accepted)
      if accepted > 0 then
        -- A depleted source may be sleeping. Energy assignment alone does not
        -- wake every burner; the script pause transition wakes its native update.
        record.source.disabled_by_script = true
        record.source.disabled_by_script = false
      end
      if record.energy_reserve <= 0.000001 then record.energy_reserve = nil; storage.energy_reserves[id] = nil end
    end
  end
end

---@param tick MapTick
function M.expire(tick)
  local queue = storage.work
  local budget = math.min(64, queue.tail - queue.head + 1)
  for _ = 1, budget do
    local work = queue.items[queue.head]
    queue.items[queue.head], queue.seen[work.key] = nil, nil
    queue.head = queue.head + 1
    local id = work.id
    if work.kind == "clone" then
    local pending = storage.clone_pending[id]
    if pending and tick >= pending.deadline then
      storage.clone_pending[id] = nil
      storage.clone_locations[pending.key] = nil
      if common.valid(pending.entity) then
        local sources = colocated(pending.entity, pending.entity.name .. "-source")
        if #sources == 0 and common.valid(pending.source) then
          pending.source.clone{position = pending.entity.position, surface = pending.entity.surface, force = pending.entity.force}
        end
        M.attach(pending.entity, tick)
        local record = storage.beacons[id]
        if record and record.phase == "attached" then
          record.resume_disabled = pending.resume_disabled
          record.source.disabled_by_script = pending.resume_disabled or pending.entity.to_be_deconstructed()
          power.update(record)
        end
        if record and pending.energy_reserve and pending.energy_reserve > 0 then
          record.energy_reserve = pending.energy_reserve
          record.reserve_capacity = pending.reserve_capacity
          storage.energy_reserves[id] = true
        end
      end
    end
    if storage.clone_pending[id] then enqueue("clone", id) end
    elseif work.kind == "pending" then
    local record = storage.beacons[id]
    -- A partial legacy transaction may already have been protected during
    -- conversion. Retire its stale scheduling; never infer a commit deadline.
    if not record or record.phase ~= "pending" then storage.pending[id] = nil
    elseif storage.pending[id] and type(record.deadline) ~= "number" then
      storage.pending[id] = nil
      common.protect(record, "pending replacement has no valid deadline; source retained for repair")
    elseif storage.pending[id] and tick >= record.deadline then
      storage.pending[id] = nil
      common.protect(record, "successor was not confirmed; source retained for repair")
    end
    if storage.pending[id] then enqueue("pending", id) end
    end
  end
  if queue.head > queue.tail then queue.head, queue.tail = 1, 0 end
end

---@param event EventData.script_raised_teleported
function M.teleported(event)
  if not common.managed(event.entity) then return end
  local record = storage.beacons[event.entity.unit_number]
  if not record then return end
  local old_key = common.key(record.surface_index, record.position, record.force_index)
  local old_surface, old_position = game.surfaces[record.surface_index], record.position
  local moved = {}
  for _, name in ipairs{"source", "manager", "monitor", "mimic"} do
    local entity = record[name]
    if common.valid(entity) and (entity.surface ~= event.entity.surface or not entity.teleport(event.entity.position)) then
      for _, helper in ipairs(moved) do helper.teleport(old_position) end
      if event.entity.surface == old_surface then event.entity.teleport(old_position) end
      storage.locations[old_key] = nil
      record.surface_index, record.position = event.entity.surface.index, event.entity.position
      storage.locations[common.entity_key(event.entity)] = record.id
      common.protect(record, "helper teleport failed; resources retained, inspect positions before repair")
      return
    end
    if common.valid(entity) then moved[#moved + 1] = entity end
  end
  storage.locations[old_key] = nil
  record.surface_index, record.position = event.entity.surface.index, event.entity.position
  storage.locations[common.entity_key(event.entity)] = record.id
end

---@param event EventData.on_entity_cloned
function M.cloned(event)
  if not common.managed(event.destination) then
    -- Native area cloning may copy the real source after the visible beacon. Only
    -- replace a copy this transaction created, never an unrelated colocated source.
    local id = storage.clone_locations[common.entity_key(event.destination)]
    local pending = id and storage.clone_pending[id]
    if pending and event.source == pending.source then
      if pending.copied_source and pending.copied_source ~= event.destination then common.destroy(pending.copied_source) end
      pending.copied_source = event.destination
      event.destination.disabled_by_script = true
    end
    return
  end
  local original = storage.beacons[event.source.unit_number]
  event.destination.disabled_by_script = true
  local pending = {entity = event.destination, key = common.entity_key(event.destination),
    source = original and original.source, energy_reserve = original and original.energy_reserve,
    reserve_capacity = original and original.reserve_capacity,
    resume_disabled = original and common.valid(original.source) and original.source.disabled_by_script or false, deadline = event.tick + 1}
  storage.clone_pending[event.destination.unit_number] = pending
  storage.clone_locations[pending.key] = event.destination.unit_number
  local sources = colocated(event.destination, event.destination.name .. "-source")
  if #sources == 0 and common.valid(pending.source) then
    pending.copied_source = pending.source.clone{position = event.destination.position,
      surface = event.destination.surface, force = event.destination.force}
    if pending.copied_source then pending.copied_source.disabled_by_script = true end
  elseif #sources == 1 then
    sources[1].disabled_by_script = true
  end
  enqueue("clone", event.destination.unit_number)
end

return M
