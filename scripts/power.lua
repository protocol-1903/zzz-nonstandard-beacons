-- NSB FILE MAP
-- owns: powered state, optional synthetic modules and destruction callbacks
-- loaded_by: scripts/lifecycle.lua
-- cadence: circuit/recipe transitions; attachment and explicit repair
-- forwarded_events: crafted via the internal recipe event; real entity destruction
-- storage_roots: manager_owners, callbacks and each beacon's callbacks/controllers
-- gui_ids: none
-- remote_interfaces: none
-- rebuild_on: attachment and explicit repair
-- blueprint: docs/lifecycle.md#contract
-- Thanks to quezler for the original low-overhead approach, and to protocol_1903
-- for NSB's implementation. This module is the AI-assisted continuation of that design.
-- protocol_1903's 2.1 update suggested native recipe notifications. The circuit
-- comparison still wakes Lua only while state differs. Real modules stay in the beacon.
local common = require("scripts.common")
---@class NSBPower
local M = {}
---@param record NSBRecord
---@param kind NSBCallbackKind
---@param object LuaEntity
function M.register(record, kind, object)
  local registration = script.register_on_object_destroyed(object)
  record.callbacks[registration] = true
  storage.callbacks[registration] = {id = record.id, kind = kind}
end
---@param record NSBRecord
function M.retire(record)
  -- Remove mappings before destroying helpers: callbacks may arrive next tick.
  local manager_id = record.manager_unit_number
    or (common.valid(record.manager) and record.manager.unit_number)
  if manager_id and storage.manager_owners[manager_id] == record.id then
    storage.manager_owners[manager_id] = nil
  end
  record.manager_unit_number, record.pointer = nil, nil
  for registration in pairs(record.callbacks or {}) do storage.callbacks[registration] = nil end
  record.callbacks = {}
  common.destroy(record.manager)
  common.destroy(record.monitor)
  common.destroy(record.mimic)
  record.manager, record.monitor, record.mimic = nil, nil, nil
end
---@param record NSBRecord
function M.watch_owners(record)
  -- Protected and pending records still need removal detection after conversion.
  if common.valid(record.beacon) then M.register(record, "beacon", record.beacon) end
  if common.valid(record.source) then M.register(record, "source", record.source) end
end
---@param record NSBRecord
function M.copy_modules(record)
  if not common.valid(record.mimic) then return end
  local mirror = record.source.get_module_inventory()
  mirror.clear()
  local section = record.mimic.get_or_create_control_behavior().sections[2]
  for i = 1, section.filters_count do section.clear_slot(i) end
  for index, item in pairs(record.beacon.get_module_inventory().get_contents()) do
    mirror.insert(item)
    section.set_slot(index, {value = {type = "item", name = item.name, quality = item.quality}, min = item.count})
  end
end
---@param record NSBRecord
function M.update(record)
  -- something got invalidated, do nothing
  if record.phase ~= "attached" or not common.valid(record.beacon) or not common.valid(record.source) or not common.valid(record.manager) then return end
  local working = record.source.status == defines.entity_status.working
  record.beacon.disabled_by_script = not working
  if common.valid(record.mimic) then
    -- supports modules, do complex logic
    record.mimic.get_or_create_control_behavior().sections[1].active = working
    M.copy_modules(record)
  else
    -- does not support modules, do basic logic
    record.manager.get_or_create_control_behavior().circuit_condition = {
      comparator = working and "=" or "≠", constant = 0,
      first_signal = {type = "item", name = "nsb-internal-item"}
    }
  end
end
---@param event EventData.RecipeCraftedEvent
---@return NSBRecord|nil changed
function M.crafted(event)
  local manager = event.entity
  if event.recipe ~= "nsb-internal-recipe" or not common.valid(manager) then return end
  local manager_id = manager.unit_number
  local id = storage.manager_owners[manager_id]
  local record = id and storage.beacons[id]
  -- A delayed event from a retired controller must never affect its successor.
  if not record or record.phase ~= "attached" or record.manager ~= manager
    or record.manager_unit_number ~= manager_id or not common.valid(record.beacon)
    or not common.valid(record.source) then return end
  M.update(record)
  return record
end
---@param record NSBRecord
---@return boolean, string|nil
function M.attach(record)
  M.retire(record)
  M.watch_owners(record)
  local beacon, source = record.beacon, record.source
  if not common.valid(source) then return false, "missing source" end
  local function create(name)
    local entity = beacon.surface.create_entity{name = name, position = beacon.position, force = beacon.force}
    if entity then
      entity.destructible = false
      M.register(record, "helper", entity)
    end
    return entity
  end
  record.manager = create("nsb-internal-manager")
  if not record.manager then return false, "manager construction failed" end
  local manager = record.manager
  manager.disabled_by_script = true -- Failed attachment must remain idle.
  record.manager_unit_number = manager.unit_number
  record.pointer = manager.unit_number -- Keep upstream get-beacon-data's public field readable.
  storage.manager_owners[record.manager_unit_number] = record.id
  local function connect(entity)
    return manager.get_wire_connector(defines.wire_connector_id.circuit_green, true).connect_to(
      entity.get_wire_connector(defines.wire_connector_id.circuit_green, true), false, defines.wire_origin.script)
  end
  -- connect source, manager, mimic, and (?) monitor
  if not connect(source) then return false, "source controller connection failed" end
  local source_control = source.get_or_create_control_behavior()
  source_control.circuit_read_working = true
  source_control.circuit_working_signal = {type = "item", name = "nsb-internal-item"}
  local control = manager.get_or_create_control_behavior()
  control.circuit_enable_disable = true
  if common.definitions[beacon.name].modules then
    record.monitor, record.mimic = create("nsb-internal-monitor"), create("nsb-internal-mimic")
    if not record.monitor or not record.mimic then return false, "module monitor construction failed" end
    record.monitor.proxy_target_entity = beacon
    record.monitor.proxy_target_inventory = defines.inventory.beacon_modules
    if not connect(record.monitor) or not connect(record.mimic) then return false, "module controller connection failed" end
    local mimic = record.mimic.get_or_create_control_behavior()
    mimic.sections[1].set_slot(1, {value = {type = "item", name = "nsb-internal-item", quality = "normal"}, min = -1})
    mimic.add_section().multiplier = -1
    control.circuit_condition = {comparator = "≠", constant = 0, first_signal = {type = "virtual", name = "signal-anything"}}
  end
  M.update(record)
  manager.disabled_by_script = false
  return true
end
return M
