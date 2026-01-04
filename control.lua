local event_filter = assert(prototypes.mod_data["nsb-beacon-data"].data.event, "error: nonstandard beacon event filter not found!")
local modded_beacons = assert(prototypes.mod_data["nsb-beacon-data"].data.modded_beacons, "error: nonstandard beacon data not found!")

log("Beacon Data:")
log(serpent.block(modded_beacons))

local function make_modded(beacon)
  -- skip if already existant
  if storage.beacons[beacon.unit_number].monitor then return end
  local source = storage.beacons[beacon.unit_number].source
  local manager = storage.beacons[beacon.unit_number].manager
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
  manager.get_wire_connector(defines.wire_connector_id.circuit_green, true).connect_to(monitor.get_wire_connector(defines.wire_connector_id.circuit_green, true), false, defines.wire_origin.script)
  manager.get_wire_connector(defines.wire_connector_id.circuit_green, true).connect_to(mimic.get_wire_connector(defines.wire_connector_id.circuit_green, true), false, defines.wire_origin.script)
  monitor.proxy_target_entity = beacon
  monitor.proxy_target_inventory = defines.inventory.beacon_modules
  local mimic_behaviour = mimic.get_or_create_control_behavior()
  mimic_behaviour.sections[1].set_slot(1, {value = {type = "item", name = "nsb-internal-item", quality = "normal"}, min = -1})
  mimic_behaviour.sections[1].active = false
  mimic_behaviour.add_section().multiplier = -1
  
  -- update manager
  manager.get_or_create_control_behavior().circuit_condition = {
    comparator = "≠",
    constant = 0,
    first_signal = { name = "signal-anything", type = "virtual" }
  }
  
  -- initialize mimic and source
  source.get_module_inventory().clear()
  for index, item_stack in pairs(beacon.get_module_inventory().get_contents()) do
    source.get_module_inventory().insert(item_stack)
    mimic_behaviour.sections[2].set_slot(index, {
      value = {type = "item", name = item_stack.name, quality = item_stack.quality},
      min = item_stack.count
    })
  end
  
  -- add data to storage
  storage.beacons[beacon.unit_number].mimic = mimic
  storage.beacons[beacon.unit_number].monitor = monitor
end

local function valid(metadata)
  if not metadata then return false end
  if not metadata.beacon or not metadata.beacon.valid then
    if metadata.source.valid then metadata.source.destroy() end
    if metadata.manager.valid then metadata.manager.destroy() end
    if metadata.monitor and metadata.monitor.valid then metadata.monitor.destroy() end
    if metadata.mimic and metadata.mimic.valid then metadata.mimic.destroy() end
    return false
  end
  return true
end

local function register_sacrifice(manager, metadata)
  manager.get_inventory(defines.inventory.crafter_input).insert{
    name = "nsb-internal-item",
    count = 1,
    health = 0.5,
  }
  storage.deathrattles[script.register_on_object_destroyed(manager.get_inventory(defines.inventory.crafter_input)[1].item)] = metadata
end

local function attempt_migration(force)
  local ninjas = 0
  log("NSB: Checking for invalid data")
  for _, metatable in pairs{
    storage.modded_beacons,
    prototypes.mod_data["nsb-beacon-data"].data.modded_beacons
  } do
    for beacon_prototype in pairs(metatable) do
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
                  local reference = storage.beacons[beacons[1].unit_number][reference_name] or {}
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

  log("Removed " .. ninjas .. " ninjas")
  log("NSB: attempting migrations")
  -- attempt to update migrated entities
  if modded_beacons ~= storage.modded_beacons or force then
    log("Migrating beacons")

    local beacons_removed = 0
    
    local changes = {}
    for prototype, value in pairs(modded_beacons) do
      changes[prototype] = force or value ~= storage.modded_beacons[prototype]
    end
    
    -- migrate already stored beacons
    for index, metadata in pairs(storage.beacons or {}) do
      if not valid(metadata) then -- beacon removed, destroy entities
        beacons_removed = beacons_removed + 1
        log("Removing beacon:")
        log(metadata.beacon)
        storage.beacons[index] = nil
      elseif changes[metadata.beacon.name] then
        if modded_beacons[metadata.beacon.name] == nil then
          log("Removing custom entities for: " .. metadata.beacon)
          
          -- no longer custom, revert to normal
          metadata.beacon.disabled_by_script = false
          metadata.beacon.custom_status = nil
          
          -- remove unneeded entities
          if metadata.source.valid then metadata.source.destroy() end
          if metadata.manager.valid then metadata.manager.destroy() end
          if metadata.monitor and metadata.monitor.valid then metadata.monitor.destroy() end
          if metadata.mimic and metadata.mimic.valid then metadata.mimic.destroy() end
          
          -- clear storage index
          storage.beacons[index] = nil
        elseif modded_beacons[metadata.beacon.name] and not metadata.monitor then
          log("Adding monitor for: " .. metadata.beacon)
          make_modded(metadata.beacon)
        elseif not modded_beacons[metadata.beacon.name] and metadata.monitor then
          log("Removing monitor for: " .. metadata.beacon)
          -- reset manager settings and clear source modules
          metadata.source.get_module_inventory().clear()
          metadata.manager.get_or_create_control_behavior().circuit_condition = {
            comparator = metadata.source.status == defines.entity_status.working and "=" or "≠",
            constant = 0,
            first_signal = { name = "nsb-internal-item", type = "item" }
          }
  
          -- remove monitor and mimic
          metadata.monitor.destroy()
          metadata.mimic.destroy()
          storage.beacons[index].monitor = nil
          storage.beacons[index].mimic = nil
        end
      end
    end
    log("Removed " .. beacons_removed .. " invalid beacons")
    log("Old data: " .. serpent.block(storage.modded_beacons))
    log("New data: " .. serpent.block(modded_beacons))
    log("Changes: " .. serpent.block(changes))
  
    -- migrate existing beacons
    for prototype, changed in pairs(changes) do
      if changed and storage.modded_beacons[prototype] == nil then
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
              manager.get_wire_connector(defines.wire_connector_id.circuit_green, true).connect_to(source.get_wire_connector(defines.wire_connector_id.circuit_green, true), false, defines.wire_origin.script)
              
              -- set circuit settings
              local source_behaviour = source.get_or_create_control_behavior()
              local manager_behaviour = manager.get_or_create_control_behavior()
              
              source_behaviour.circuit_read_working = true
              source_behaviour.circuit_working_signal = {type = "item", name = "nsb-internal-item"}
              manager_behaviour.circuit_enable_disable = true
              manager_behaviour.circuit_condition = {
                comparator = "≠",
                constant = 0,
                first_signal = { name = "nsb-internal-item", type = "item" }
              }
    
              -- save data and register event
              storage.beacons[beacon.unit_number] = {beacon = beacon, source = source, manager = manager}
              register_sacrifice(manager, storage.beacons[beacon.unit_number])
            end
            if storage.modded_beacons[prototype] then
              make_modded(beacon)
            end
          end
        end
      end
    end
  end
  
  -- adjust moduled beacons, items may have been converted/migrated/removed
  for _, metadata in pairs(storage.beacons) do
    -- only apply to beacons that have not changed, otherwise they've already been properly updated
    if modded_beacons[metadata.beacon.name] and storage.modded_beacons[metadata.beacon.name] then
      -- reset logistic section and modules
      local mimic_behaviour = metadata.mimic.get_or_create_control_behavior()
      metadata.source.get_module_inventory().clear()
      mimic_behaviour.remove_section(2) -- just straight up delete the section, filters may be nonconsecutive
      -- update logistic section and modules
      mimic_behaviour.add_section().multiplier = -1
      for index, item_stack in pairs(metadata.beacon.get_module_inventory().get_contents()) do
        metadata.source.get_module_inventory().insert(item_stack)
        mimic_behaviour.sections[2].set_slot(index, {
          value = {type = "item", name = item_stack.name, quality = item_stack.quality},
          min = item_stack.count
        })
      end
    end
  end
  storage.modded_beacons = modded_beacons
end

script.on_init(function ()
  _G.storage = {
    beacons = {},
    modded_beacons = {},
    deathrattles = {},
    previous_version = script.active_mods["zzz-nonstandard-beacons"]
  }
end)

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
  storage.deathrattles = storage.deathrattles or {}
  storage.previous_version = script.active_mods["zzz-nonstandard-beacons"]
  attempt_migration(storage.force_migrations)
  storage.force_migrations = nil
end)

script.on_event(defines.events.on_object_destroyed, function(event)
  local metadata = storage.deathrattles[event.registration_number]
  if not metadata then return end
  storage.deathrattles[event.registration_number] = nil
  local beacon = metadata.beacon
  local manager = metadata.manager
  local source = metadata.source
  local mimic = metadata.mimic
  local monitor = metadata.monitor

  -- something got invalidated, do nothing
  if not beacon.valid or not source.valid or not manager.valid or monitor and not monitor.valid or mimic and not mimic.valid then return end

  if monitor then -- supports modules, do complex logic
    local mimic_sections = mimic.get_or_create_control_behavior().sections
    local beacon_state = manager.get_signal({ type = "item", name = "nsb-internal-item" }, defines.wire_connector_id.circuit_green)
    if beacon_state ~= 0 then -- 0 is stable, 1 is turning on, -1 is turning off
      beacon.disabled_by_script = beacon_state == -1
      beacon.custom_status = beacon_state == -1 and {
        diode = defines.entity_status_diode.red, -- add custom status to reflect source status
        label = beacon.to_be_deconstructed() and {"entity-status.marked-for-deconstruction"} or {"entity-status." .. (
        source.prototype.burner_prototype and "no-fuel" or source.prototype.fluid_energy_source_prototype and "no-input-fluid" or
        source.prototype.heat_energy_source_prototype and "low-temperature" or "low-power")}
      } or nil -- clears if beacon is working as intended
      mimic_sections[1].active = beacon_state == 1 -- update the combinator with the current state
    end
    if beacon_state == 0 or beacon.get_module_inventory().get_contents() ~= source.get_module_inventory().get_contents() then
      source.get_module_inventory().clear()
      for i=1, mimic_sections[2].filters_count do
        mimic_sections[2].clear_slot(i)
      end
      for index, item_stack in pairs(beacon.get_module_inventory().get_contents()) do
        source.get_module_inventory().insert(item_stack)
        mimic_sections[2].set_slot(index, {
          value = {type = "item", name = item_stack.name, quality = item_stack.quality},
          min = item_stack.count
        })
      end
    end

  else -- does not support modules, do basic logic
    beacon.disabled_by_script = source.status ~= defines.entity_status.working
    beacon.custom_status = source.status ~= defines.entity_status.working and {
      diode = defines.entity_status_diode.red, -- add custom status to reflect source status
      label = beacon.to_be_deconstructed() and {"entity-status.marked-for-deconstruction"} or {"entity-status." .. (
      source.prototype.burner_prototype and "no-fuel" or source.prototype.fluid_energy_source_prototype and "no-input-fluid" or
      source.prototype.heat_energy_source_prototype and "low-temperature" or "low-power")}
    } or nil -- clears if beacon is working as intended
    manager.get_or_create_control_behavior().circuit_condition = {
      comparator = source.status == defines.entity_status.working and "=" or "≠",
      constant = 0,
      first_signal = { name = "nsb-internal-item", type = "item" }
    }
  end

  register_sacrifice(manager, metadata)
end)

--- @param event EventData.on_built_entity|EventData.on_robot_built_entity|EventData.on_space_platform_built_entity|EventData.script_raised_built|EventData.script_raised_revive|EventData.on_cancelled_deconstruction
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
  manager.get_wire_connector(defines.wire_connector_id.circuit_green, true).connect_to(source.get_wire_connector(defines.wire_connector_id.circuit_green, true), false, defines.wire_origin.script)
  
  -- set circuit settings
  local source_behaviour = source.get_or_create_control_behavior()
  local manager_behaviour = manager.get_or_create_control_behavior()
  
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
    label = {"entity-status." .. (
      source.prototype.burner_prototype and "no-fuel" or source.prototype.fluid_energy_source_prototype and "no-input-fluid" or
      source.prototype.heat_energy_source_prototype and "low-temperature" or "low-power")}
  }

  -- save data and register event
  storage.beacons[beacon.unit_number] = {beacon = beacon, source = source, manager = manager}
  register_sacrifice(manager, storage.beacons[beacon.unit_number])
            
  if storage.modded_beacons[beacon.name] then
    make_modded(beacon)
  end
end

--- @param event EventData.on_player_mined_entity|EventData.on_robot_mined_entity|EventData.on_space_platform_mined_entity|EventData.script_raised_destroy|EventData.on_entity_died
local function on_destroyed(event)
  local metadata = storage.beacons[event.entity.unit_number]

  if not metadata then error("error: nonstandard beacons could not find metadata for destroyed entity") end

  -- attempt to insert fuel into the event buffer, if possible
  if event.buffer and metadata.source.get_fuel_inventory() then
    for _, item_stack in pairs(metadata.source.get_fuel_inventory().get_contents()) do
      event.buffer.insert{
        name = item_stack.name,
        quality = item_stack.quality,
        count = item_stack.count
      }
    end
  end

  -- delete source entity
  metadata.source.destroy()
  metadata.manager.destroy()
  if metadata.monitor then metadata.monitor.destroy() end
  if metadata.mimic then metadata.mimic.destroy() end

  -- remove storage index
  storage.beacons[event.entity.unit_number] = nil
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
script.on_event(defines.events.on_marked_for_deconstruction, function (event)
  storage.beacons[event.entity.unit_number].source.disabled_by_script = true
end, event_filter)

-- enable the source if cancelled deconstruction
script.on_event(defines.events.on_cancelled_deconstruction, function (event)
  storage.beacons[event.entity.unit_number].source.disabled_by_script = false
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
    name = assert(prototypes.mod_data["nsb-beacon-data"].data.decon, "error: nonstandard beacon deconstruction entity filter not found!")
  }

  if count ~= 0 then
    for index, metadata in pairs(storage.beacons) do
      if not metadata.beacon.valid or not metadata.source.valid or not metadata.manager.valid or not metadata.mimic.valid or metadata.monitor and not metadata.monitor.valid then
        if metadata.beacon.valid then metadata.beacon.destroy() end
        if metadata.source.valid then metadata.source.destroy() end
        if metadata.manager.valid then metadata.manager.destroy() end
        if metadata.monitor and metadata.monitor.valid then metadata.monitor.destroy() end
        if metadata.mimic and metadata.mimic.valid then metadata.mimic.destroy() end
        storage.beacons[index] = nil
      end
    end
  end
end)

--- on upgrade/replacement, for quality/source changes

script.on_event(defines.events.script_raised_teleported, function (event)
  if not storage.beacons[event.entity.unit_number] then return end
  for _, entity in pairs(storage.beacons[event.entity.unit_number]) do
    entity.teleport(event.entity.position)
  end
end, event_filter)

script.on_event("nsb-beacon-rotate", function (event)
  if not event.selected_prototype or modded_beacons[event.selected_prototype.name] == nil then return end

  local name = event.selected_prototype.name
  local player = game.players[event.player_index]
  local surface = player.character and player.character.surface or player.surface
  local sources = surface.find_entities_filtered{
    position = event.cursor_position,
    name = name .. "-source"
  }
  if #sources ~= 1 then return end
  sources[1].rotate()
end)

script.on_event("nsb-beacon-rotate-reverse", function (event)
  if not event.selected_prototype or modded_beacons[event.selected_prototype.name] == nil then return end

  local name = event.selected_prototype.name
  local player = game.players[event.player_index]
  local surface = player.character and player.character.surface or player.surface
  local sources = surface.find_entities_filtered{
    position = event.cursor_position,
    name = name .. "-source"
  }
  if #sources ~= 1 then return end
  sources[1].rotate{reverse = true}
end)