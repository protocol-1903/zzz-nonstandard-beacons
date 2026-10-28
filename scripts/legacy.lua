-- NSB FILE MAP
-- owns: original-ID upstream saved-record normalization and diagnostic quarantine
-- loaded_by: scripts/lifecycle.lua before disposable-controller conversion
-- cadence: one bounded pass when an unversioned upstream storage graph is loaded
-- storage_roots: beacons, locations, legacy_orphans; retired upstream lookup tables
-- rebuild_on: first game-available conversion boundary; never during on_load
-- blueprint: docs/lifecycle.md#upstream-storage
local common = require("scripts.common")
---@class NSBLegacy
local M = {}

---Reject unsupported historical upgrades before adopting their storage. A missing
---old version means a fresh installation, including adding NSB to an existing save.
---@param previous string|nil Authoritative ModChangeData.old_version from the configuration event.
function M.require_supported_version(previous)
  if not previous then return end
  local major, minor, patch = previous:match("^(%d+)%.(%d+)%.(%d+)$")
  major, minor, patch = tonumber(major), tonumber(minor), tonumber(patch)
  if major and (major < 1 or (major == 1 and (minor < 4 or (minor == 4 and patch < 2)))) then
    error("Please upgrade this save to Nonstandard Beacons 1.4.2 under Factorio 2.0 before loading this contribution.")
  end
end

---@param value any
---@return boolean
local function plain_record(value)
  -- LuaObjects can have Lua's table type. Their property getters must not be
  -- probed as if they were arbitrary saved records.
  return type(value) == "table" and value.object_name == nil
end

---@param record NSBRecord
---@param reason string
local function protect_later(record, reason)
  record.phase, record.issue = "protected", record.issue or reason
  record.ownership_issue = true
end

---@param key any
---@param record any
---@param reason string
local function quarantine(key, record, reason)
  storage.legacy_orphans[#storage.legacy_orphans + 1] = {key = key, record = record, issue = reason}
end

---@param entity LuaEntity|nil
---@param beacon LuaEntity
---@param expected string
---@return boolean
local function aligned(entity, beacon, expected)
  return common.valid(entity) and entity.name == expected
    and common.entity_key(entity) == common.entity_key(beacon)
end

---@return boolean converted_legacy
function M.normalize()
  local legacy, normalized, helper_claims = {}, {}, {}
  storage.legacy_orphans = storage.legacy_orphans or {}
  for key, record in pairs(storage.beacons) do
    if plain_record(record) and record.id and record.phase then
      normalized[key] = record -- Existing schema-1 transactions retain their entire state.
    else
      legacy[#legacy + 1] = {key = key, record = record}
    end
    if plain_record(record) then
      for _, field in ipairs{"manager", "monitor", "mimic"} do
        local helper = record[field]
        if common.valid(helper) and helper.unit_number then
          helper_claims[helper.unit_number] = (helper_claims[helper.unit_number] or 0) + 1
        end
      end
    end
  end
  if #legacy == 0 then return false end
  table.sort(legacy, function(a, b) return tostring(a.key) < tostring(b.key) end)

  -- Old item destruction and recipe notifications may still arrive. Retire
  -- their routing before cleanup; never interpret them as new-schema callbacks.
  storage.deathrattles, storage.beacon_pointers, storage.watched_beacons = nil, nil, nil
  local converted = {}
  for _, entry in ipairs(legacy) do
    local record = entry.record
    local beacon = plain_record(record) and record.beacon
    if not common.valid(beacon) or beacon.type ~= "beacon" or not beacon.unit_number then
      quarantine(entry.key, record, "legacy record has no valid visible beacon")
    else
      record.id, record.name = beacon.unit_number, beacon.name
      record.position, record.surface_index = beacon.position, beacon.surface.index
      record.force_index, record.quality = beacon.force.index, beacon.quality.name
      record.callbacks, record.tooltip_ids = record.callbacks or {}, record.tooltip_ids or {}
      local previous_phase = record.phase
      if previous_phase == "protected" then
        record.issue = record.issue or "partially structured protected record requires explicit repair"
      elseif previous_phase == "pending" then
        record.phase, record.issue = "protected", record.issue or "partially structured pending record needs queue reconciliation"
      else record.phase, record.issue = "attached", nil end
      record.direction, record.mirrored = beacon.direction, beacon.mirroring
      if aligned(record.source, beacon, beacon.name .. "-source")
        and record.source.unit_number and record.source.quality.name == beacon.quality.name then
        -- These are the actual saved engine objects: no inventory, fuel, fluid,
        -- progress, temperature or energy is reconstructed during conversion.
        record.direction, record.mirrored = record.source.direction, record.source.mirroring
        if previous_phase == nil or record.resume_disabled == nil then record.resume_disabled = record.source.disabled_by_script end
        local matches = 0
        for _, source in pairs(beacon.surface.find_entities_filtered{
          name = beacon.name .. "-source", position = beacon.position, force = beacon.force}) do
          if common.entity_key(source) == common.entity_key(beacon) then matches = matches + 1 end
        end
        if matches ~= 1 then protect_later(record, "legacy source ownership is ambiguous") end
      else
        -- A corrupt pointer must not let protection pause someone else's machine.
        -- Retain it diagnostically, outside operational/destructive helper paths.
        record.legacy_source, record.source = record.source, nil
        protect_later(record, "legacy source reference does not uniquely match the visible beacon")
      end
      for field, expected in pairs{manager = "nsb-internal-manager", monitor = "nsb-internal-monitor", mimic = "nsb-internal-mimic"} do
        local helper = record[field]
        if common.valid(helper) and (not aligned(helper, beacon, expected)
          or helper_claims[helper.unit_number] ~= 1) then
          record.legacy_helpers = record.legacy_helpers or {}
          record.legacy_helpers[field], record[field] = helper, nil
          protect_later(record, "legacy helper ownership is incomplete or ambiguous")
          if field == "manager" and aligned(helper, beacon, expected) then
            -- A shared, mod-owned manager is disposable but not yet attributable
            -- to one record. Leave it intact and idle while its owners are protected.
            helper.disabled_by_script = true
          end
        end
      end
      record.manager_unit_number = common.valid(record.manager) and record.manager.unit_number or nil
      local previous = normalized[record.id]
      if previous and previous ~= record then
        protect_later(previous, "multiple legacy records claim the same visible beacon")
        protect_later(record, "multiple legacy records claim the same visible beacon")
        quarantine(entry.key, record, record.issue)
      else normalized[record.id] = record end
      converted[#converted + 1] = record
      beacon.custom_status = nil -- Only the old status this mod owned; no foreign tooltip IDs.
    end
  end

  -- Never rekey the original table in place: swapped old keys or duplicate IDs
  -- must not erase another record. Include already-structured owners in conflict
  -- detection so partially upgraded saves receive the same conservative policy.
  local locations, sources, included = {}, {}, {}
  local function include(record)
    if included[record] then return end
    included[record] = true
    if record.position and record.surface_index and record.force_index then
      local key = common.key(record.surface_index, record.position, record.force_index)
      if locations[key] and locations[key] ~= record then
        protect_later(locations[key], "multiple records claim the same source location")
        protect_later(record, "multiple records claim the same source location")
      else locations[key] = record end
    end
    if common.valid(record.source) and record.source.unit_number then
      local id = record.source.unit_number
      if sources[id] and sources[id] ~= record then
        protect_later(sources[id], "multiple records claim the same source")
        protect_later(record, "multiple records claim the same source")
      else sources[id] = record end
    end
  end
  for _, record in pairs(normalized) do include(record) end
  for _, record in ipairs(converted) do include(record) end
  storage.beacons = normalized
  for key, record in pairs(locations) do storage.locations[key] = record.id end
  for record in pairs(included) do
    if record.phase == "protected" then common.protect(record, record.issue) end
  end
  return true
end

---@param record NSBRecord
---@return boolean, string|nil
function M.can_repair(record)
  if not record.ownership_issue then return true end
  local beacon = record.beacon
  if not common.valid(beacon) then return false, "visible owner is unavailable" end
  local matches = {}
  for _, source in pairs(beacon.surface.find_entities_filtered{
    name = beacon.name .. "-source", position = beacon.position, force = beacon.force}) do
    if common.entity_key(source) == common.entity_key(beacon) then matches[#matches + 1] = source end
  end
  if #matches > 1 or (#matches == 1 and matches[1].quality.name ~= beacon.quality.name)
    or (common.valid(record.source) and matches[1] ~= record.source) then
    return false, "source ownership remains ambiguous; existing state is preserved"
  end
  local function conflicts(other)
    return other ~= record and plain_record(other) and
      ((common.valid(other.beacon) and other.beacon == beacon)
        or (common.valid(other.source) and (other.source == record.source or other.source == matches[1])))
  end
  for _, other in pairs(storage.beacons) do
    if conflicts(other) then return false, "another record still claims this beacon or source" end
  end
  for _, orphan in pairs(storage.legacy_orphans or {}) do
    if conflicts(orphan.record) then return false, "quarantined metadata still claims this beacon or source" end
  end
  for _, other in pairs(beacon.surface.find_entities_filtered{type = "beacon", position = beacon.position, force = beacon.force}) do
    if other ~= beacon and common.managed(other) and common.entity_key(other) == common.entity_key(beacon) then
      return false, "another visible beacon still claims this exact location"
    end
  end
  return true
end
return M
