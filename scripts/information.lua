-- NSB FILE MAP
-- owns: numeric source view model, owned tooltip rows and relative screen adapter
-- loaded_by: control.lua
-- cadence: relevant events and viewed beacons once/10 ticks
-- forwarded_events: changed; update from dispatcher
-- storage_roots: viewers, watched and beacon tooltip_ids
-- gui_ids: nsbc-source-information
-- remote_interfaces: none
-- rebuild_on: init/configuration; selected/opened entity changes
-- blueprint: docs/lifecycle.md#information
local common = require("scripts.common")
---@class NSBInformation
local M = {}
local GUI_NAME = "nsbc-source-information"
local status_names = {}
for name, value in pairs(defines.entity_status) do status_names[value] = name:gsub("_", "-") end

---@param value number
---@return string
function M.number(value)
  if value == 0 then return "0" end
  return string.format("%.4g", value)
end
---@param value number
---@param unit string
---@return string
local function si(value, unit)
  local prefixes = {"", "k", "M", "G", "T"}
  local index = 1
  while math.abs(value) >= 1000 and index < #prefixes do value, index = value / 1000, index + 1 end
  return M.number(value) .. " " .. prefixes[index] .. unit
end
---@param inventory LuaInventory|nil
---@return LocalisedString
local function inventory_text(inventory)
  local text = {}
  if inventory and inventory.valid then
    for _, item in pairs(inventory.get_contents()) do
      text[#text + 1] = "[item=" .. item.name .. ",quality=" .. item.quality .. "] " .. item.count
    end
  end
  return #text == 0 and {"nsbc.empty"} or table.concat(text, ", ")
end

---@param record NSBRecord
---@return LocalisedString, defines.entity_status_diode
local function status(record)
  if record.issue then return {"nsbc.repair-required", record.issue}, defines.entity_status_diode.red end
  if not common.valid(record.source) then return {"nsbc.missing-source"}, defines.entity_status_diode.red end
  if record.beacon.to_be_deconstructed() then return {"entity-status.marked-for-deconstruction"}, defines.entity_status_diode.red end
  if record.beacon.get_module_inventory().is_empty() then return {"entity-status.no-modules-to-transmit"}, defines.entity_status_diode.yellow end
  local source_status = record.source.status
  return {"?", {"entity-status." .. (status_names[source_status] or "unknown")}, {"nsbc.source-status", source_status}},
    source_status == defines.entity_status.working and defines.entity_status_diode.green or defines.entity_status_diode.red
end

---@param record NSBRecord
---@return NSBTooltipRow[] rows Ordered localised values; the same model serves hover and opened screens.
function M.rows(record)
  local rows = {}
  local function row(id, value) rows[#rows + 1] = {id = id, name = {"nsbc." .. id}, value = value} end
  if not common.valid(record.source) then row("state", {"nsbc.missing-source"}); return rows end
  local source, definition = record.source, common.definitions[record.name]
  local limits = source.prototype.effect_receiver.consumption_limits
  local bonus = math.max(limits.low, math.min(limits.high, source.consumption_bonus))
  local watts = source.prototype.get_max_energy_usage(source.quality) * 60 * (1 + bonus)
  row("operating-power", si(watts, "W"))
  if record.energy_reserve and record.energy_reserve > 0 then row("energy-reserve", si(record.energy_reserve, "J")) end
  if bonus ~= 0 then row("consumption-effect", M.number(bonus * 100) .. "%") end
  local electric = source.prototype.electric_energy_source_prototype
  if electric then row("idle-drain", si(electric.drain * 60, "W")) end
  if definition.kind == "burner" then
    local burner = source.burner
    local fuel = burner.currently_burning
    if fuel then
      row("burning", {"", "[item=" .. fuel.name.name .. ",quality=" .. fuel.quality.name .. "] ", si(burner.remaining_burning_fuel, "J")})
    else row("burning", {"nsbc.empty"}) end
    row("stored-fuel", inventory_text(source.get_fuel_inventory()))
    row("burnt-results", inventory_text(source.get_burnt_result_inventory()))
  elseif definition.kind == "fluid" then
    local energy = source.prototype.fluid_energy_source_prototype
    local index = common.energy_fluid_index(source)
    local fluid = index and source.get_fluid(index)
    local prototype = fluid and prototypes.fluid[fluid.name] or energy.fluid_box.filter
    local joules = prototype and prototype.fuel_value or 0
    if not energy.burns_fluid then
      joules = 0
      if prototype and fluid then
        local temperature = math.min(fluid.temperature, energy.maximum_temperature or fluid.temperature)
        if (not energy.minimum_input_temperature or fluid.temperature >= energy.minimum_input_temperature) and
            (not energy.maximum_input_temperature or fluid.temperature <= energy.maximum_input_temperature) then
          joules = math.max(0, temperature - prototype.default_temperature) * prototype.heat_capacity
        end
      end
    end
    -- Zero fluid_usage_per_tick means no configured scaled cap, not zero demand.
    local requirement = joules > 0 and energy.effectivity > 0 and watts / (joules * energy.effectivity) or nil
    row("operating-requirement", requirement and (M.number(requirement) .. "/s") or {"nsbc.unavailable"})
    local configured = energy.fluid_usage_per_tick * 60
    if configured > 0 then row(energy.scale_fluid_usage and "configured-cap" or "fixed-fluid-rate", M.number(configured) .. "/s") end
    row("stored-fluid", {"", prototype and ("[fluid=" .. prototype.name .. "] ") or "",
      M.number(fluid and fluid.amount or 0), " / ", index and M.number(source.get_fluid_capacity(index)) or {"nsbc.unavailable"}})
    if fluid then row("fluid-temperature", M.number(fluid.temperature) .. " °C") end
    local output_index = common.energy_fluid_index(source, true)
    if output_index then
      local spent = source.get_fluid(output_index)
      row("spent-fluid", {"", spent and ("[fluid=" .. spent.name .. "] ") or "",
        M.number(spent and spent.amount or 0), " / ", M.number(source.get_fluid_capacity(output_index))})
      if spent then row("spent-temperature", M.number(spent.temperature) .. " °C") end
    end
  elseif definition.kind == "heat" then
    row("temperature", M.number(source.temperature) .. " °C")
    if definition.min_temperature then row("minimum-temperature", M.number(definition.min_temperature) .. " °C") end
    if definition.max_temperature then row("maximum-temperature", M.number(definition.max_temperature) .. " °C") end
  end
  if definition.recipe ~= "nsb-filler-recipe" then
    row("recipe-input", inventory_text(source.get_inventory(defines.inventory.crafter_input)))
    row("recipe-output", inventory_text(source.get_inventory(defines.inventory.crafter_output)))
    local energy_index = common.energy_fluid_index(source)
    local spent_index = common.energy_fluid_index(source, true)
    for index = 1, source.fluids_count do
      if index ~= energy_index and index ~= spent_index then
        local fluid = source.get_fluid(index)
        if fluid then rows[#rows + 1] = {id = "recipe-fluid-" .. index, name = {"nsbc.recipe-fluid", index},
          value = "[fluid=" .. fluid.name .. "] " .. M.number(fluid.amount) .. " / " .. M.number(source.get_fluid_capacity(index)) .. " (" .. M.number(fluid.temperature) .. " °C)"} end
      end
    end
  end
  return rows
end

---@param record NSBRecord
function M.clear(record)
  if common.valid(record.beacon) then
    for _, id in pairs(record.tooltip_ids) do record.beacon.clear_tooltip_field(id) end
  end
  record.tooltip_ids = {}
end

---@param record NSBRecord
---@return NSBTooltipRow[]|nil
function M.refresh(record)
  if not common.valid(record.beacon) then return end
  local label, diode = status(record)
  record.beacon.custom_status = {diode = diode, label = label}
  local retained = {}
  local rows = M.rows(record)
  for order, row in ipairs(rows) do
    retained[row.id] = record.beacon.set_tooltip_field{
      id = record.tooltip_ids[row.id], name = row.name, value = row.value, order = order}
  end
  for key, id in pairs(record.tooltip_ids) do
    if not retained[key] then record.beacon.clear_tooltip_field(id) end
  end
  record.tooltip_ids = retained
  return rows
end

-- Runtime tooltip rows do not render inside the native 2.1.23 beacon window.
-- This relative, read-only adapter shares the same model and closes with it.
---@param player LuaPlayer
---@param record NSBRecord|nil
---@param rows NSBTooltipRow[]|nil
local function opened_panel(player, record, rows)
  local root = player.gui.relative[GUI_NAME]
  if not record or not common.valid(record.beacon) or not rows then
    if root then root.destroy() end
    return
  end
  local signature = ""
  for _, row in ipairs(rows) do signature = signature .. ":" .. row.id end
  if root and (root.tags.unit ~= record.id or root.tags.signature ~= signature) then root.destroy(); root = nil end
  if not root then
    root = player.gui.relative.add{type = "frame", name = GUI_NAME, direction = "vertical",
      caption = {"nsbc.source-information"}, tags = {parent_gui = GUI_NAME, unit = record.id, signature = signature},
      anchor = {gui = defines.relative_gui_type.beacon_gui, position = defines.relative_gui_position.right}}
    root.style.width = 360
    local pane = root.add{type = "scroll-pane", name = "body", horizontal_scroll_policy = "never"}
    pane.style.maximal_height = 420
    local fields = pane.add{type = "table", name = "fields", column_count = 2}
    for index, row in ipairs(rows) do
      local label = fields.add{type = "label", name = "name-" .. index, caption = row.name, tooltip = row.name}
      label.style.width, label.style.single_line = 180, false
      local value = fields.add{type = "label", name = "value-" .. index, caption = row.value, tooltip = row.value}
      value.style.width, value.style.single_line = 145, false
    end
  else
    for index, row in ipairs(rows) do
      local value = root.body.fields["value-" .. index]
      value.caption, value.tooltip = row.value, row.value
    end
  end
end

---@param player LuaPlayer
---@param closing boolean|nil
local function viewer(player, closing)
  if not player.connected then storage.viewers[player.index] = nil; return end
  local selected = common.managed(player.selected) and player.selected.unit_number or nil
  local opened = not closing and player.opened or nil
  opened = (type(opened) == "table" or type(opened) == "userdata") and opened.object_name == "LuaEntity" and common.managed(opened) and opened.unit_number or nil
  storage.viewers[player.index] = (selected or opened) and {selected = selected, opened = opened} or nil
end

---@param event EventData.on_selected_entity_changed|EventData.on_gui_opened|EventData.on_gui_closed|EventData.on_player_joined_game|EventData.on_player_left_game|EventData.on_player_controller_changed|EventData.on_player_changed_surface
function M.changed(event)
  local player = game.get_player(event.player_index)
  if player then
    local previous = storage.viewers[player.index]
    if event.name == defines.events.on_gui_closed and previous and previous.opened then
      -- Native replacement closes the old window before its built event. Keep
      -- only this tick's closure, so a later unrelated build cannot reopen it.
      storage.recent_closed[player.index] = {id = previous.opened, tick = event.tick}
    end
    if not player.connected then storage.recent_closed[player.index] = nil end
    viewer(player, event.name == defines.events.on_gui_closed)
    if not storage.viewers[player.index] or not storage.viewers[player.index].opened then opened_panel(player) end
  end
  M.update(event.tick, event.name == defines.events.on_gui_closed and event.player_index or nil)
end

---@param entity LuaEntity
---@param tick MapTick
function M.replaced(entity, tick)
  local record = common.managed(entity) and storage.beacons[entity.unit_number]
  if not record or not record.replaced_from then return end
  local old = record.replaced_from
  record.replaced_from = nil
  local viewers = {}
  for index, view in pairs(storage.viewers) do if view.opened == old then viewers[index] = true end end
  for index, closed in pairs(storage.recent_closed) do
    if closed.id == old and closed.tick == tick then viewers[index] = true end
  end
  for index in pairs(viewers) do
    local player = game.get_player(index)
    if player and player.connected and (not player.opened or (common.valid(player.opened) and player.opened.unit_number == old)) then
      player.opened = entity
    end
    storage.recent_closed[index] = nil
  end
end

---@param tick MapTick
---@param closing_player uint32|nil
function M.update(tick, closing_player)
  for index, closed in pairs(storage.recent_closed) do if closed.tick < tick then storage.recent_closed[index] = nil end end
  local watched, affected, models = {}, {}, {}
  for index in pairs(storage.viewers) do
    local player = game.get_player(index)
    if player then affected[index] = player end
    if player then viewer(player, index == closing_player) else storage.viewers[index] = nil end
    local view = storage.viewers[index]
    if view then
      if view.selected then watched[view.selected] = true end
      if view.opened then watched[view.opened] = true end
    end
  end
  for id in pairs(storage.watched) do
    if not watched[id] and storage.beacons[id] then M.clear(storage.beacons[id]) end
  end
  storage.watched = watched
  for id in pairs(watched) do
    local record = storage.beacons[id]
    if record then models[id] = M.refresh(record) end
  end
  for index, player in pairs(affected) do
    local view = storage.viewers[index]
    local id = view and view.opened
    opened_panel(player, id and storage.beacons[id], id and models[id])
  end
end

---@param tick MapTick
function M.initialize(tick)
  storage.recent_closed = storage.recent_closed or {}
  for _, player in pairs(game.players) do opened_panel(player) end
  for _, player in pairs(game.connected_players) do viewer(player) end
  M.update(tick)
end
return M
