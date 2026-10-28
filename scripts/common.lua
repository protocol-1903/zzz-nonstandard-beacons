-- NSB FILE MAP
-- owns: shared object guards, definitions, identity and protection policy
-- loaded_by: runtime feature modules
-- cadence: called at lifecycle/view boundaries; no scheduling
-- forwarded_events: none
-- storage_roots: passed beacon records only
-- gui_ids: none
-- remote_interfaces: none
-- rebuild_on: definitions read from prototype mod-data during loading
-- blueprint: docs/lifecycle.md#contract
---@class NSBCommon
---@field definitions table<string, NSBDefinition>
local M = {}
M.definitions = prototypes.mod_data["nsb-beacon-data"].data.definitions
---@param entity LuaEntity|nil
---@return boolean
function M.valid(entity)
  local kind = type(entity)
  return (kind == "table" or kind == "userdata") and entity.object_name == "LuaEntity" and entity.valid or false
end
---@param entity LuaEntity|nil
---@return boolean
function M.managed(entity) return M.valid(entity) and M.definitions[entity.name] ~= nil end
---@param surface_index uint32
---@param position MapPosition
---@param force_index uint32
---@return string
function M.key(surface_index, position, force_index)
  return surface_index .. ":" .. position.x .. ":" .. position.y .. ":" .. force_index
end
---@param entity LuaEntity
---@return string
function M.entity_key(entity) return M.key(entity.surface.index, entity.position, entity.force.index) end
-- Fluid-box prototype indices belong to separate recipe/energy namespaces. Only
-- the entity's runtime storage indices address get_fluid/set_fluid in Factorio 2.1.
---@param entity LuaEntity
---@param output boolean|nil Select spent-fluid storage instead of fuel input.
---@return FluidStorageIndex|nil
function M.energy_fluid_index(entity, output)
  local energy = entity.prototype.fluid_energy_source_prototype
  if not energy then return nil end
  local expected = output and energy.output_fluid_box or energy.fluid_box
  if output and not energy.output_fluid_box then return nil end
  for index = 1, entity.fluids_count do
    local box = entity.get_fluid_box_prototype(index)
    if box == expected then return index end
    if box and not box.object_name then
      for _, member in pairs(box) do if member == expected then return index end end
    end
  end
end
---@param record NSBRecord
---@param message string
function M.protect(record, message)
  record.phase, record.issue = "protected", message
  if M.valid(record.beacon) then
    record.beacon.disabled_by_script = true
    record.beacon.custom_status = {diode = defines.entity_status_diode.red, label = {"nsbc.repair-required", message}}
  end
  if M.valid(record.source) then
    if record.resume_disabled == nil then record.resume_disabled = record.source.disabled_by_script end
    record.source.disabled_by_script = true
  end
  -- An ingredient-free controller must not keep crafting against an unresolved
  -- mismatch while its notifications are deliberately ignored during protection.
  if M.valid(record.manager) then record.manager.disabled_by_script = true end
  log("NSBC protected " .. record.id .. ": " .. message)
end
---@param entity LuaEntity|nil
function M.destroy(entity) if M.valid(entity) then entity.destroy() end end
---@param before string
---@param after string
---@return boolean
function M.compatible(before, after)
  local a, b = M.definitions[before], M.definitions[after]
  return a and b and a.kind == b.kind and
    (before == after or (a.family ~= nil and a.family == b.family)) or false
end
return M
