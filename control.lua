---@namespace zzz-nonstandard-beacons

local mod_data = assert(prototypes.mod_data["zzz-nonstandard-beacons"], "error: nonstandard beacon mod data not found!")
local event_filter = assert(mod_data.data.event_filter, "error: nonstandard beacon event filter not found!") --[[@as EventFilter]]
local deconstruction_filter = assert(mod_data.data.deconstruction_filter, "error: nonstandard beacon deconstruction filter not found!") --[[@as string[] ]]
local custom_beacon_prototypes = assert(mod_data.data.custom_beacon_prototypes, "error: nonstandard beacon data not found!") --[[@as {[string]: CustomBeaconConfiguration}]]
local tooltip_fields = assert(mod_data.data.tooltip_fields, "error: nonstandard beacon tooltip fields not found!")

require "__perel__.util.general"

log("Beacon Data:")
log(serpent.block(custom_beacon_prototypes))

---@param tbl1 any
---@param tbl2 any
local function compare(tbl1, tbl2)
  if type(tbl1) ~= type(tbl2) then
    return false
  elseif type(tbl1) == "table" then
    for k, v in pairs(tbl1) do
      if not compare(v, tbl2[k]) then return false end
    end
    for k, v in pairs(tbl2) do
      if not compare(v, tbl1[k]) then return false end
    end
    return true
  else
    return tbl1 == tbl2
  end
end

---@class storage
---@field beacons {[uint]: CustomBeaconData?}
---@field beacon_pointers {[uint]: uint?}
---@field custom_beacon_prototypes {[string]: CustomBeaconConfiguration}
---@field previous_version string
---@field watched_beacons {[uint]: uint}
---@field force_migrations boolean?
storage = {} --[[@as storage]]

---@class CustomBeaconData
---@field beacon LuaEntity
---@field source LuaEntity
---@field manager LuaEntity
---@field pointer uint
---@field monitor LuaEntity?
---@field mimic LuaEntity?

script.on_init(function ()
  storage.beacons = storage.beacons or {}
  storage.beacon_pointers = storage.beacon_pointers or {}
  storage.custom_beacon_prototypes = storage.custom_beacon_prototypes or {}
  storage.previous_version = script.active_mods["zzz-nonstandard-beacons"]
  storage.watched_beacons = storage.watched_beacons or {}
end)

---@param entity LuaEntity?
local function safe_destroy(entity)
  if entity and entity.valid then
    entity.destroy()
  end
end

---@param beacon_data CustomBeaconData
local function make_custom_variant(beacon_data)
  -- skip if already exists as custom
  if beacon_data.monitor then return end
  local beacon = beacon_data.beacon
  local source = beacon_data.source
  local manager = beacon_data.manager
  -- create new entities
  local mimic = beacon.surface.create_entity{
    name = "nsb-internal-mimic",
    position = beacon.position,
    force = beacon.force
  }
  local monitor = beacon.surface.create_entity{
    name = "nsb-internal-monitor",
    position = beacon.position,
    force = beacon.force
  }

  -- connect monitor and mimic
  manager.get_wire_connector(defines.wire_connector_id.circuit_green, true).connect_to(monitor.get_wire_connector(defines.wire_connector_id.circuit_green, true) --[[@as LuaWireConnector]], false, defines.wire_origin.script)
  manager.get_wire_connector(defines.wire_connector_id.circuit_green, true).connect_to(mimic.get_wire_connector(defines.wire_connector_id.circuit_green, true) --[[@as LuaWireConnector]], false, defines.wire_origin.script)
  monitor.proxy_target_entity = beacon
  monitor.proxy_target_inventory = defines.inventory.beacon_modules
  local mimic_behaviour = mimic.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
  mimic_behaviour.sections[1].set_slot(1, {value = {type = "item", name = "nsb-internal-item", quality = "normal"}, min = -1})
  mimic_behaviour.sections[1].active = false
  mimic_behaviour.add_section().multiplier = -1

  -- update manager
  manager.get_or_create_control_behavior() --[[@as LuaAssemblingMachineControlBehavior]].circuit_condition = {
    comparator = "≠",
    constant = 0,
    first_signal = { name = "signal-anything", type = "virtual" }
  }

  -- initialize mimic and source
  source.get_module_inventory().clear()
  for index, item_stack in pairs(beacon.get_module_inventory().get_contents()) do
    source.get_module_inventory().insert(item_stack --[[@as ItemStackDefinition]])
    mimic_behaviour.sections[2].set_slot(index, {
      value = {type = "item", name = item_stack.name, quality = item_stack.quality},
      min = item_stack.count
    })
  end

  -- add data
  beacon_data.mimic = mimic
  beacon_data.monitor = monitor
end

---@param beacon_data CustomBeaconData
local function valid(beacon_data)
  if not beacon_data then return false end
  if not beacon_data.beacon or not beacon_data.beacon.valid or
    not beacon_data.source or not beacon_data.source.valid or
    not beacon_data.manager or not beacon_data.manager.valid or
    beacon_data.monitor and not beacon_data.monitor.valid or
    beacon_data.mimic and not beacon_data.mimic.valid then
    log("Found invalid beacon data:")
    log(beacon_data.beacon)

    safe_destroy(beacon_data.beacon)
    safe_destroy(beacon_data.source)
    safe_destroy(beacon_data.manager)
    safe_destroy(beacon_data.monitor)
    safe_destroy(beacon_data.mimic)
    return false
  end
  return true
end

local function attempt_migration(force)
  local ninjas = 0
  log("Nonstandard Beacons: Checking for invalid data")
  for _, metatable in pairs{
    storage.custom_beacon_prototypes,
    custom_beacon_prototypes
  } do
    for beacon_prototype in pairs(metatable) do
      if prototypes.entity[beacon_prototype] and prototypes.entity[beacon_prototype .. "-source"] then
        for _, surface in pairs(game.surfaces) do
          for _, source in pairs(surface.find_entities_filtered{
            name = beacon_prototype .. "-source"
          }) do
            if source.valid then
              local beacons = surface.find_entities_filtered{
                position = source.position,
                name = beacon_prototype
              }
              -- no beacon or beacon with no storage reference
              if #beacons == 0  or #beacons == 1 and not storage.beacons[beacons[1].unit_number] then
                -- remove excess entities
                for _, entity_name in pairs{
                  "nsb-internal-monitor",
                  "nsb-internal-manager",
                  "nsb-internal-mimic",
                  beacon_prototype .. "-source" -- do last cause we use it to reference position
                } do
                  for _, entity in pairs(surface.find_entities_filtered{
                    position = source.position,
                    name = entity_name
                  }) do
                    entity.destroy()
                    ninjas = ninjas + 1
                  end
                end
              elseif #beacons == 1 then
                -- make sure no extraneous entities exist
                for reference_name, entity_name in pairs{
                  source = beacon_prototype .. "-source",
                  monitor = "nsb-internal-monitor",
                  manager = "nsb-internal-manager",
                  mimic = "nsb-internal-mimic"
                } do
                  for _, entity in pairs(surface.find_entities_filtered{
                    position = source.position,
                    name = entity_name
                  }) do
                    local reference = storage.beacons[beacons[1].unit_number --[[@as uint]]][reference_name] or {}
                    if entity.unit_number ~= reference.unit_number then
                      entity.destroy()
                      ninjas = ninjas + 1
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  log("Removed " .. ninjas .. " ninjas")
  log("Nonstandard Beacons: attempting migrations")
  -- attempt to update migrated entities
  if force or compare(custom_beacon_prototypes, storage.custom_beacon_prototypes) then
    log("Migrating beacons")

    local beacons_removed = 0

    local changes = {}
    for prototype, properties in pairs(custom_beacon_prototypes) do
      changes[prototype] = force or not compare(properties, storage.custom_beacon_prototypes[prototype])
    end

    -- migrate already stored beacons
    for index, beacon_data in pairs(storage.beacons or {}) do
      if not valid(beacon_data) then -- beacon removed, destroy entities
        beacons_removed = beacons_removed + 1
        log("Removing beacon:")
        log(beacon_data.beacon)
        storage.beacons[index] = nil
        storage.beacon_pointers[beacon_data.pointer] = nil
      elseif changes[beacon_data.beacon.name] then
        if not custom_beacon_prototypes[beacon_data.beacon.name] then
          log("Removing custom entities for: " .. beacon_data.beacon)

          -- no longer custom, revert to normal
          beacon_data.beacon.disabled_by_script = false
          beacon_data.beacon.custom_status = nil

          -- remove unneeded entities
          safe_destroy(beacon_data.source)
          safe_destroy(beacon_data.manager)
          safe_destroy(beacon_data.monitor)
          safe_destroy(beacon_data.mimic)

          -- clear storage index
          storage.beacons[index] = nil
        else
          if custom_beacon_prototypes[beacon_data.beacon.name].uses_module_effects and not beacon_data.monitor then
            log("Adding monitor for:")
            log(beacon_data.beacon)
            make_custom_variant(beacon_data)
          elseif not custom_beacon_prototypes[beacon_data.beacon.name].uses_module_effects and beacon_data.monitor then
            log("Removing monitor for:")
            log(beacon_data.beacon)
            -- reset manager settings and clear source modules
            beacon_data.source.get_module_inventory().clear()
            beacon_data.manager.get_or_create_control_behavior() --[[@as LuaAssemblingMachineControlBehavior]].circuit_condition = {
              comparator = beacon_data.source.status == defines.entity_status.working and "=" or "≠",
              constant = 0,
              first_signal = { name = "nsb-internal-item", type = "item" }
            }

            -- remove monitor and mimic
            safe_destroy(beacon_data.monitor)
            safe_destroy(beacon_data.mimic)
            storage.beacons[index].monitor = nil
            storage.beacons[index].mimic = nil
          end
        end
      end
    end
    log("Removed " .. beacons_removed .. " invalid beacons")
    log("Old data: " .. serpent.block(storage.custom_beacon_prototypes))
    log("New data: " .. serpent.block(custom_beacon_prototypes))
    log("Changes: " .. serpent.block(changes))

    -- migrate existing beacons
    for prototype, changed in pairs(changes) do
      if changed and not storage.custom_beacon_prototypes[prototype] then
        log("Nonstandard Beacons: attempting migrations for prototype: " .. prototype)
        -- was not previously custom, must be made custom
        for _, surface in pairs(game.surfaces) do
          log("Searching surface: " .. surface.name)
          for _, beacon in pairs(surface.find_entities_filtered{
            name = prototype,
            type = "beacon"
          }) do
            if not storage.beacons[beacon.unit_number] then
              log("Found unmodded beacon: ")
              log(beacon)
              local source = beacon.surface.create_entity{
                name = beacon.name .. "-source",
                position = beacon.position,
                quality = beacon.quality,
                force = beacon.force
              }

              local manager = beacon.surface.create_entity{
                name = "nsb-internal-manager",
                position = beacon.position,
                force = beacon.force
              }

              -- connect source, manager, mimic, and (?) monitor
              manager.get_wire_connector(defines.wire_connector_id.circuit_green, true).connect_to(source.get_wire_connector(defines.wire_connector_id.circuit_green, true) --[[@as LuaWireConnector]], false, defines.wire_origin.script)

              -- set circuit settings
              local source_behaviour = source.get_or_create_control_behavior() --[[@as LuaAssemblingMachineControlBehavior]]
              local manager_behaviour = manager.get_or_create_control_behavior() --[[@as LuaAssemblingMachineControlBehavior]]

              source_behaviour.circuit_read_working = true
              source_behaviour.circuit_working_signal = {type = "item", name = "nsb-internal-item"}
              manager_behaviour.circuit_enable_disable = true
              manager_behaviour.circuit_condition = {
                comparator = "≠",
                constant = 0,
                first_signal = { name = "nsb-internal-item", type = "item" }
              }

              -- save data
              local beacon_data = {
                beacon = beacon,
                source = source --[[@as LuaEntity]],
                manager = manager --[[@as LuaEntity]],
                pointer = manager.unit_number --[[@as uint]]
              }
              storage.beacons[beacon.unit_number --[[@as uint]]] = beacon_data
              storage.beacon_pointers[beacon_data.pointer] = beacon.unit_number
            end
            if custom_beacon_prototypes[prototype].uses_module_effects then
              make_custom_variant(storage.beacons[beacon.unit_number --[[@as uint]]])
            end
          end
        end
      end
    end
  end

  -- adjust moduled beacons, items may have been converted/migrated/removed
  for _, beacon_data in pairs(storage.beacons) do
    -- only apply to beacons that have not changed, otherwise they've already been properly updated
    if (custom_beacon_prototypes[beacon_data.beacon.name] or {}).uses_module_effects and (storage.custom_beacon_prototypes[beacon_data.beacon.name] or {}).uses_module_effects then
      -- reset logistic section and modules
      local mimic_behaviour = beacon_data.mimic.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
      beacon_data.source.get_module_inventory().clear()
      mimic_behaviour.remove_section(2) -- just straight up delete the section, filters may be nonconsecutive
      -- update logistic section and modules
      mimic_behaviour.add_section().multiplier = -1
      for index, item_stack in pairs(beacon_data.beacon.get_module_inventory().get_contents()) do
        beacon_data.source.get_module_inventory().insert(item_stack --[[@as ItemStackDefinition]])
        mimic_behaviour.sections[2].set_slot(index, {
          value = {type = "item", name = item_stack.name, quality = item_stack.quality},
          min = item_stack.count
        })
      end
    end
  end
  storage.custom_beacon_prototypes = custom_beacon_prototypes
end

commands.add_command("update_beacons", "Attempt to update custom beacons via scripted migration. Used for mod development or to fix critical issues. Include optional paramater \"force_update\" to update entities regardless of detected changes.", function (command)
  attempt_migration(command.parameter == "force_update")
end)

remote.add_interface("nonstandard-beacons", {
  force_migrations = function()
    attempt_migration(true)
  end,
  ["get-beacon-data"] = function (beacon_unit_number)
    return storage.beacons[beacon_unit_number]
  end
})

script.on_configuration_changed(function (event)
  log("Nonstandard Beacons: configuration change detected")
  storage.beacons = storage.beacons or {}
  storage.previous_version = script.active_mods["zzz-nonstandard-beacons"]
  storage.watched_beacons = storage.watched_beacons or {}
  attempt_migration(storage.force_migrations)
  storage.force_migrations = nil
end)

---@param event EventData.RecipeCraftedEvent
script.on_event(assert(prototypes.recipe["nsb-internal-recipe"].on_crafted_event), function (event)
  local pointer = storage.beacon_pointers[event.entity.unit_number --[[@as uint]]]
  if not pointer then return end
  local beacon_data = storage.beacons[pointer]
  if not beacon_data then return end
  local beacon = beacon_data.beacon
  local manager = beacon_data.manager
  local source = beacon_data.source
  local mimic = beacon_data.mimic
  local monitor = beacon_data.monitor

  -- something got invalidated, do nothing
  if not valid(beacon_data) then return end

  if monitor then -- supports modules, do complex logic
    local mimic_sections = mimic.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]].sections
    local beacon_state = manager.get_signal({ type = "item", name = "nsb-internal-item" }, defines.wire_connector_id.circuit_green)
    if beacon_state ~= 0 then -- 0 is stable, 1 is turning on, -1 is turning off
      local disabled = beacon_state == -1
      beacon.disabled_by_script = disabled
      beacon.custom_status = disabled and {
        diode = defines.entity_status_diode.red, -- add custom status to reflect source status
        label = {tooltip_fields[beacon.name].low_status or "unknown-status"}
      } or nil -- clears if beacon is working as intended
      mimic_sections[1].active = not disabled -- update the combinator with the current state
    end
    if beacon_state == 0 or beacon.get_module_inventory().get_contents() ~= source.get_module_inventory().get_contents() then
      source.get_module_inventory().clear()
      for i=1, mimic_sections[2].filters_count do
        mimic_sections[2].clear_slot(i)
      end
      for index, item_stack in pairs(beacon.get_module_inventory().get_contents()) do
        source.get_module_inventory().insert(item_stack --[[@as ItemStackDefinition]])
        mimic_sections[2].set_slot(index, {
          value = {type = "item", name = item_stack.name, quality = item_stack.quality},
          min = item_stack.count
        })
      end
    end
  else -- does not support modules, do basic logic
    local disabled = source.status ~= defines.entity_status.working
    beacon.disabled_by_script = disabled
    beacon.custom_status = disabled and {
      diode = defines.entity_status_diode.red, -- add custom status to reflect source status
      label = {tooltip_fields[beacon.name].low_status or "unknown-status"}
    } or nil -- clears if beacon is working as intended
    manager.get_or_create_control_behavior() --[[@as LuaAssemblingMachineControlBehavior]].circuit_condition = {
      comparator = disabled and "≠" or "=",
      constant = 0,
      first_signal = { name = "nsb-internal-item", type = "item" }
    }
  end
end)

--- @param event EventData.on_built_entity|EventData.on_robot_built_entity|EventData.on_space_platform_built_entity|EventData.script_raised_built|EventData.script_raised_revive
local function on_created(event)
  local beacon = event.entity

  local source = beacon.surface.create_entity{
    name = beacon.name .. "-source",
    position = beacon.position,
    quality = beacon.quality,
    force = beacon.force
  }

  local manager = beacon.surface.create_entity{
    name = "nsb-internal-manager",
    position = beacon.position,
    force = beacon.force
  }

  -- connect source, manager, mimic, and (?) monitor
  manager.get_wire_connector(defines.wire_connector_id.circuit_green, true).connect_to(source.get_wire_connector(defines.wire_connector_id.circuit_green, true) --[[@as LuaWireConnector]], false, defines.wire_origin.script)

  -- set circuit settings
  local source_behaviour = source.get_or_create_control_behavior() --[[@as LuaAssemblingMachineControlBehavior]]
  local manager_behaviour = manager.get_or_create_control_behavior() --[[@as LuaAssemblingMachineControlBehavior]]

  source_behaviour.circuit_read_working = true
  source_behaviour.circuit_working_signal = {type = "item", name = "nsb-internal-item"}
  manager_behaviour.circuit_enable_disable = true
  manager_behaviour.circuit_condition = {
    comparator = "≠",
    constant = 0,
    first_signal = { name = "nsb-internal-item", type = "item" }
  }

  beacon.disabled_by_script = true
  beacon.custom_status = {
    diode = defines.entity_status_diode.red,
    label = {tooltip_fields[beacon.name].low_status or "unknown-status"}
  }

  -- save data and register event
  local beacon_data = {
    beacon = beacon,
    source = source --[[@as LuaEntity]],
    manager = manager --[[@as LuaEntity]],
    pointer = manager.unit_number --[[@as uint]]
  }
  storage.beacons[beacon.unit_number --[[@as uint]]] = beacon_data
  storage.beacon_pointers[beacon_data.pointer] = beacon.unit_number

  if custom_beacon_prototypes[beacon.name].uses_module_effects then
    make_custom_variant(beacon_data)
  end
end

--- @param event EventData.on_player_mined_entity|EventData.on_robot_mined_entity|EventData.on_space_platform_mined_entity|EventData.script_raised_destroy|EventData.on_entity_died
local function on_destroyed(event)
  local beacon_data = storage.beacons[event.entity.unit_number --[[@as uint]]]

  if not beacon_data then error("error: nonstandard beacons could not find metadata for destroyed entity") end

  -- attempt to insert fuel into the event buffer, if possible
  if event.buffer and beacon_data.source.valid and beacon_data.source.get_fuel_inventory() then
    for _, item_stack in pairs(beacon_data.source.get_fuel_inventory().get_contents()) do
      event.buffer.insert{
        name = item_stack.name,
        quality = item_stack.quality,
        count = item_stack.count
      }
    end
  end

  -- delete source entity
  safe_destroy(beacon_data.source)
  safe_destroy(beacon_data.manager)
  safe_destroy(beacon_data.monitor)
  safe_destroy(beacon_data.mimic)

  -- remove storage index
  storage.beacons[event.entity.unit_number --[[@as uint]]] = nil
end

-- don't register events if nothing is included
if #event_filter == 0 then return end

script.on_event(defines.events.on_built_entity, on_created, event_filter)
script.on_event(defines.events.on_robot_built_entity, on_created, event_filter)
script.on_event(defines.events.on_space_platform_built_entity, on_created, event_filter)
script.on_event(defines.events.script_raised_built, on_created, event_filter)
script.on_event(defines.events.script_raised_revive, on_created, event_filter)

script.on_event(defines.events.on_player_mined_entity, on_destroyed, event_filter)
script.on_event(defines.events.on_robot_mined_entity, on_destroyed, event_filter)
script.on_event(defines.events.on_space_platform_mined_entity, on_destroyed, event_filter)
script.on_event(defines.events.script_raised_destroy, on_destroyed, event_filter)
script.on_event(defines.events.on_entity_died, on_destroyed, event_filter)

-- disable the source if marked for deconstruction
---@param event EventData.on_marked_for_deconstruction
script.on_event(defines.events.on_marked_for_deconstruction, function (event)
  storage.beacons[event.entity.unit_number --[[@as uint]]].source.disabled_by_script = true
end, event_filter)

-- enable the source if cancelled deconstruction
---@param event EventData.on_cancelled_deconstruction
script.on_event(defines.events.on_cancelled_deconstruction, function (event)
  storage.beacons[event.entity.unit_number --[[@as uint]]].source.disabled_by_script = false
end, event_filter)

--- @param event EventData.on_player_deconstructed_area
script.on_event(defines.events.on_player_deconstructed_area, function (event)
  -- quit if alt-deconstructing, or if non-editor (cause editor is the reason this handler exists)
  if event.alt or game.players[event.player_index].controller_type ~= defines.controllers.editor then return end
  -- recreate deconstruction logic cause... reasons
  local count = event.surface.count_entities_filtered{
    area = event.area,
    quality = event.quality,
    type = "beacon",
    name = deconstruction_filter
  }

  if count ~= 0 then
    local to_remove = {}
    for index, beacon_data in pairs(storage.beacons) do
      if not valid(beacon_data) then
        to_remove[index] = beacon_data.pointer
      end
    end
    for index, pointer in pairs(to_remove) do
      storage.beacons[index] = nil
      storage.beacon_pointers[pointer] = nil
    end
  end
end)

--- on upgrade/replacement, for quality/source changes
---@param event EventData.script_raised_teleported
script.on_event(defines.events.script_raised_teleported, function (event)
  if not storage.beacons[event.entity.unit_number] then return end
  for _, entity in pairs(storage.beacons[event.entity.unit_number]) do
    entity.teleport(event.entity.position)
  end
end, event_filter)

---@param event EventData.CustomInputEvent
script.on_event("nsb-beacon-rotate", function (event)
  local player = game.players[event.player_index]
  local entity = player.selected
  if not entity then return end
  if not custom_beacon_prototypes[entity.name] then return end
  storage.beacons[entity.unit_number --[[@as uint]]].source.rotate()
end)

---@param event EventData.CustomInputEvent
script.on_event("nsb-beacon-rotate-reverse", function (event)
  local player = game.players[event.player_index]
  local entity = player.selected
  if not entity then return end
  if not custom_beacon_prototypes[entity.name] then return end
  storage.beacons[entity.unit_number --[[@as uint]]].source.rotate{reverse = true}
end)

local ticks_per_update = 2

-- slow poll entities to check if they are no longer viewed
script.on_nth_tick(61, function (event)
  for index, last_tick in pairs(storage.watched_beacons) do
    if event.tick > last_tick + 600 then
      local metadata = storage.beacons[index]
      if metadata and metadata.beacon.valid then
        local beacon = metadata.beacon
        beacon.custom_status = beacon.status ~= defines.entity_status.working and {
          diode = defines.entity_status_diode.red, -- add custom status to reflect source status
          label = {
            beacon.to_be_deconstructed() and "entity-status.marked-for-deconstruction" or
            beacon.get_module_inventory().is_empty() and "entity-status.no-modules-to-transmit" or tooltip_fields[beacon.name].low_status
          }
        } or nil -- clears if beacon is working as intended
      end
      storage.watched_beacons[index] = nil
    end
  end
end)

do return end

-- showing custom tooltip data via custom_status
script.on_nth_tick(ticks_per_update, function (event)
  for _, player in pairs(game.players) do
    if player.valid and player.selected and custom_beacon_prototypes[player.selected.name] then
      local beacon = player.selected
      storage.watched_beacons[beacon.unit_number --[[@as uint]]] = event.tick
      local metadata = storage.beacons[beacon.unit_number --[[@as uint]]]
      local source = metadata.source
      local working = source.status == defines.entity_status.working
      local fuel_inventory = source.get_fuel_inventory()
      local contents = fuel_inventory and not fuel_inventory.is_empty() and fuel_inventory.get_contents()
      local fuel = contents and "[item=" .. contents[1].name .. "] x " .. tostring(contents[1].count)
      local fluid = source.fluids_count ~= 0 and (source.get_fluid(1) or {}) or nil
      local max_fluid_per_second = fluid and source.prototype.fluid_energy_source_prototype.fluid_usage_per_tick * 60
      local tooltip_data = tooltip_fields[beacon.name]
      local current_consumption = source.consumption_bonus == 0 and tooltip_data.max_consumption[beacon.quality.name] or
        perel.calculate_power(perel.parse_power(tooltip_data.max_consumption[beacon.quality.name]) * (1 + source.consumption_bonus)) ..
        (source.consumption_bonus > 0 and " (+%d%%)" or source.consumption_bonus <= -0.80000001 and " (%d%% = limit)" or " (%d%%)"):format(source.consumption_bonus * 100) .. (tooltip_data.drain and " + " .. tooltip_data.drain or "")
      if current_consumption:len() > 17 then
        for _ = 38 - current_consumption:len(), 0, -1 do
          current_consumption = "  " .. current_consumption
        end
        current_consumption = "\n" .. current_consumption
      end
      beacon.custom_status = {
        diode = working and defines.entity_status_diode.green or defines.entity_status_diode.red,
        label = {
          "", -- concatenate strings
          { -- entity status (actual)
            working and "entity-status.working" or
            beacon.to_be_deconstructed() and "entity-status.marked-for-deconstruction" or
            beacon.get_module_inventory().is_empty() and "entity-status.no-modules-to-transmit" or
            tooltip_data.low_status or "unknown-status"
          },
          "\n",
          tooltip_data.header, -- consumes ___
          "\n",
          { -- max consumption
            "",
            {"description.max-energy-consumption"},
            ": ",
            {
              "custom-tooltip.font-normal",
              current_consumption
            }
          },
          tooltip_data.drain and { -- min consumption, if appliccable
            "",
            "\n",
            {"description.min-energy-consumption"},
            ": ",
            {
              "custom-tooltip.font-normal",
              tooltip_data.drain
            }
          } or "",
          fuel and {
            "",
            "\n",
            {"gui.fuel"},
            ": ",
            {
              "custom-tooltip.font-normal",
              fuel
            },
          } or "",
          source.temperature and {
            "",
            "\n",
            {"description.temperature"},
            ": ",
            {
              "custom-tooltip.font-normal",
              {
                "",
                perel.parse_si(source.temperature),
                {"si-unit-degree-celsius"}
              }
            },
            tooltip_data.min_temperature
          } or "",
          fluid and {
            "",
            "\n",
            {"description.fluid-consumption"},
            ": ",
            {
              "custom-tooltip.font-normal",
              {
                "description.of",
                {
                  "",
                  ("%d"):format(working and max_fluid_per_second or 0),
                  {"per-second-suffix"}
                },
                {
                  "",
                  ("%d"):format(max_fluid_per_second),
                  {"per-second-suffix"}
                }
              }
            },
            fluid.amount and {
              "",
              "\n",
              prototypes.fluid[fluid.name].localised_name,
              ": ",
              {
                "custom-tooltip.font-normal",
                {
                  "description.of",
                  ("%d"):format(fluid.amount),
                  ("%d"):format(source.get_fluid_capacity(1))
                }
              },
            } or "",
            fluid.temperature and {
              "",
              "\n",
              {
                "description.fluid-temperature",
                prototypes.fluid[fluid.name].localised_name
              },
              ": ",
              {
                "custom-tooltip.font-normal",
                {
                  "",
                  ("%.2f"):format(fluid.temperature),
                  {"si-unit-degree-celsius"}
                }
              }
            } or "",
            tooltip_data.max_temperature
          } or ""
        }
      }
    end
  end
end)

-- slow polling beacons to check for invalid ones