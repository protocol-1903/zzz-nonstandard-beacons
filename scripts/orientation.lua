-- NSB FILE MAP
-- owns: source-authoritative orientation and versioned blueprint tags
-- loaded_by: control.lua
-- cadence: blueprint/build/paste/rotation events only
-- forwarded_events: pre_build, built, setup_blueprint, pasted, rotate
-- storage_roots: intents and beacon direction/mirroring
-- gui_ids: none
-- remote_interfaces: set-beacon-orientation via control.lua
-- rebuild_on: source adoption; world tags survive save/reload
-- blueprint: docs/lifecycle.md#orientation
local common = require("scripts.common")
---@class NSBOrientationModule
local M = {}

---@param entity LuaEntity
---@return string|nil
local function name(entity)
  if not common.valid(entity) then return nil end
  return entity.type == "entity-ghost" and entity.ghost_name or entity.name
end

---@param tag NSBOrientation|nil
---@return boolean
local function valid_tag(tag)
  return type(tag) == "table" and tag.version == 1 and
    (tag.space == "world" or tag.space == "blueprint") and
    type(tag.direction) == "number" and tag.direction >= 0 and tag.direction < 16 and
    tag.direction % 4 == 0 and type(tag.mirrored) == "boolean"
end

---@param entity LuaEntity
---@param direction defines.direction
---@param mirrored boolean
---@return boolean, string|nil
function M.set(entity, direction, mirrored)
  if not common.valid(entity) or not common.definitions[name(entity)] then return false, "not a managed beacon or ghost" end
  local tag = {version = 1, space = "world", direction = direction, mirrored = mirrored}
  if not valid_tag(tag) then return false, "orientation requires a quarter-turn direction and boolean mirroring" end
  if entity.type == "entity-ghost" then
    local tags = entity.tags or {}
    tags.nsb_orientation = tag
    entity.tags = tags
    return true
  end
  local record = storage.beacons[entity.unit_number]
  if not record or not common.valid(record.source) then return false, "source is not attached" end
  record.source.direction, record.source.mirroring = direction, mirrored
  record.direction, record.mirrored = direction, mirrored
  return true
end

---@param event EventData.on_pre_build
function M.pre_build(event)
  local player = game.get_player(event.player_index)
  local stack = player.cursor_stack
  local item = stack and stack.valid_for_read and stack.prototype or nil
  local target = item and item.place_result
  local ghost = player.cursor_ghost
  if not target and ghost then target = ghost.name.place_result end
  storage.intents[event.player_index] = {
    player_index = event.player_index, tick = event.tick, direction = event.direction,
    blueprint = player.is_cursor_blueprint(),
    flip_horizontal = event.flip_horizontal, flip_vertical = event.flip_vertical, mirror = event.mirror,
    name = target and target.name, quality = stack and stack.valid_for_read and stack.quality.name or ghost and ghost.quality.name,
    position = event.position, surface_index = player.surface.index, force_index = player.force.index
  }
end

---@param tag NSBOrientation
---@param intent NSBBuildIntent|nil
---@return defines.direction, boolean
function M.resolve(tag, intent)
  local direction, mirrored = tag.direction, tag.mirrored
  if tag.space == "blueprint" and intent then
    if intent.flip_horizontal then direction, mirrored = (-direction) % 16, not mirrored end
    if intent.flip_vertical then direction, mirrored = (8 - direction) % 16, not mirrored end
    direction = (direction + intent.direction) % 16
  end
  return direction, mirrored
end

---@param event NSBBuildEvent|EventData.on_blueprint_settings_pasted
function M.built(event)
  local entity = event.entity
  if not common.valid(entity) or not common.definitions[name(entity)] then return end
  local tags = entity.type == "entity-ghost" and entity.tags or event.tags
  local tag = tags and tags.nsb_orientation
  local intent = event.player_index and storage.intents[event.player_index]
  if intent and (intent.tick ~= event.tick or intent.surface_index ~= entity.surface.index or intent.force_index ~= entity.force.index) then intent = nil end
  if not valid_tag(tag) then
    -- Ordinary item placement has native pre-build intent. Legacy blueprint entries
    -- lack that item identity, so their unknowable historical direction stays unchanged.
    if intent and intent.name == name(entity) and intent.position.x == entity.position.x and
        intent.position.y == entity.position.y and intent.surface_index == entity.surface.index and
        intent.force_index == entity.force.index then
      local record = storage.beacons[entity.unit_number]
      if entity.type == "entity-ghost" or (record and record.created_tick == event.tick) then M.set(entity, intent.direction, intent.mirror or false) end
    end
    return
  end
  if tag.space == "blueprint" and (not intent or not intent.blueprint) then
    -- Script blueprint transforms must explicitly resolve orientation through the adapter.
    return
  end
  M.set(entity, M.resolve(tag, intent))
end

---@param event EventData.on_player_setup_blueprint
function M.setup_blueprint(event)
  local blueprint = event.stack or event.record
  if not blueprint or not blueprint.valid then return end
  for index, entity in pairs(event.mapping.get()) do
    if common.valid(entity) and common.definitions[name(entity)] then
      local record = storage.beacons[entity.unit_number]
      local tag = entity.type == "entity-ghost" and entity.tags and entity.tags.nsb_orientation
      if record and common.valid(record.source) then
        tag = {version = 1, space = "blueprint", direction = record.source.direction, mirrored = record.source.mirroring}
      elseif valid_tag(tag) then
        tag = {version = 1, space = "blueprint", direction = tag.direction, mirrored = tag.mirrored}
      end
      if tag then blueprint.set_blueprint_entity_tag(index, "nsb_orientation", tag) end
    end
  end
end

---@param event EventData.on_entity_settings_pasted
function M.pasted(event)
  if not common.definitions[name(event.source)] or not common.definitions[name(event.destination)] then return end
  local record = storage.beacons[event.source.unit_number]
  local tag = event.source.type == "entity-ghost" and event.source.tags and event.source.tags.nsb_orientation
  if record and common.valid(record.source) then M.set(event.destination, record.source.direction, record.source.mirroring)
  elseif valid_tag(tag) then M.set(event.destination, tag.direction, tag.mirrored) end
end

---@param event EventData.CustomInputEvent
---@param reverse boolean
function M.rotate(event, reverse)
  if event.in_gui then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local cursor = player.cursor_stack
  if player.is_cursor_blueprint() or player.cursor_ghost or (cursor and cursor.valid_for_read and
      (cursor.prototype.place_result or cursor.is_blueprint or cursor.is_blueprint_book)) then return end
  local entity = player and player.selected
  if not common.valid(entity) or not common.definitions[name(entity)] then return end
  if player.force ~= entity.force then return end
  if player.permission_group and not player.permission_group.allows_action(defines.input_action.rotate_entity) then return end
  local remote = player.controller_type == defines.controllers.remote or player.controller_type == defines.controllers.editor
  if not remote and not player.can_reach_entity(entity) then return end
  local record = storage.beacons[entity.unit_number]
  local tag = entity.type == "entity-ghost" and entity.tags and entity.tags.nsb_orientation
  local source = record and common.valid(record.source) and record.source
  local direction = source and source.direction or (valid_tag(tag) and tag.direction or 0)
  local mirrored = source and source.mirroring or (valid_tag(tag) and tag.mirrored or false)
  M.set(entity, (direction + (reverse and -4 or 4)) % 16, mirrored)
end
return M
