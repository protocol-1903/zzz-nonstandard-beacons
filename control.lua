local check_valid = false

script.on_init(function (event)
  storage.deathrattles = {}
end)

local function register_sacrifice(beacon, source, manager)
  manager.get_inventory(defines.inventory.crafter_input).insert{
    name = "nsb-internal-item",
    count = 1,
    health = 0.5,
  }
  storage.deathrattles[script.register_on_object_destroyed(manager.get_inventory(defines.inventory.crafter_input)[1].item)] = {beacon = beacon, source = source, manager = manager}
end

local event_filter = {{filter = "type", type = "beacon"}}
local alt_event_filter = {{filter = "type", type = "assembling-machine"}}

--- @param event EventData.on_built_entity|EventData.on_robot_built_entity|EventData.script_raised_built|EventData.script_raised_revive|EventData.on_space_platform_built_entity|EventData.on_cancelled_deconstruction
local function on_constructed(event)
  -- make sure its one of our entities
  if not prototypes.entity[event.entity.name .. "-source"] then return end
  local beacon = event.entity

  local source = beacon.surface.create_entity{
    name = beacon.name .. "-source",
    position = beacon.position,
    force = beacon.force
  }

  local manager = beacon.surface.create_entity{
    name = "nsb-internal-manager",
    position = beacon.position,
    force = beacon.force
  }

  -- connect source and manager
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
    first_signal = {
      name = "nsb-internal-item",
      type = "item"
    },
  }

  beacon.disabled_by_script = true
  beacon.custom_status = {
    diode = defines.entity_status_diode.red,
    label = {source.prototype.localised_description}
  }

  register_sacrifice(beacon, source, manager)
  storage[beacon.unit_number] = {beacon = beacon, source = source, manager = manager}
end

script.on_event(defines.events.on_object_destroyed, function(event)
  local metadata = storage.deathrattles[event.registration_number]
  if not metadata then return end
  storage.deathrattles[event.registration_number] = nil

  -- something got removed, do nothing
  if not metadata.beacon.valid or not metadata.source.valid or not metadata.manager.valid then return end

  -- invert control behaviour
  local to_be_enabled = metadata.source.status == defines.entity_status.working
  metadata.manager.get_or_create_control_behavior().circuit_condition = {
    comparator = to_be_enabled and "=" or "≠",
    constant = 0,
    first_signal = {
      name = "nsb-internal-item",
      type = "item"
    },
  }
  
  -- change the beacon state
  if to_be_enabled then
    metadata.beacon.disabled_by_script = false
    metadata.beacon.custom_status = {
      diode = defines.entity_status_diode.green,
      label = {"entity-status.working"}
    }
  else
    metadata.beacon.disabled_by_script = true
    metadata.beacon.custom_status = {
      diode = defines.entity_status_diode.red,
      label = {metadata.source.prototype.localised_description}
    }
  end

  register_sacrifice(metadata.beacon, metadata.source, metadata.manager)
end)

--- @param event EventData.on_player_mined_entity|EventData.on_robot_mined_entity|EventData.script_raised_destroy|EventData.on_space_platform_mined_entity|EventData.on_entity_died
local function on_deconstructed(event)
  -- make sure its one of our entities
  if not prototypes.entity[event.entity.name .. "-source"] then return end

  source = storage[event.entity.unit_number].source

  -- attempt to insert fuel into the event buffer, if possible
  if event.buffer and source.get_fuel_inventory() then
    for _, item_stack in pairs(source.get_fuel_inventory().get_contents()) do
      event.buffer.insert{
        name = item_stack.name,
        quality = item_stack.quality,
        count = item_stack.count
      }
    end
  end
  -- attempt to insert modules (only happens if source is marked for deconstruction)
  if event.buffer and source.to_be_deconstructed() then
    for _, item_stack in pairs(source.get_module_inventory().get_contents()) do
      event.buffer.insert(item_stack)
    end
  end

  -- delete source entity
  storage[event.entity.unit_number].source.destroy()
  storage[event.entity.unit_number].manager.destroy()

  -- remove storage index
  storage[event.entity.unit_number] = nil
end

--- @param event EventData.on_player_mined_entity|EventData.on_robot_mined_entity|EventData.script_raised_destroy|EventData.on_space_platform_mined_entity|EventData.on_entity_died
local function alt_on_deconstructed(event)
  -- make sure its one of our entities
  if not prototypes.entity[event.entity.name:sub(1,-8)] then return end

  local source = event.entity
  -- get our storage data
  local beacon = source.surface.find_entities_filtered{
    name = source.name:sub(1,-8),
    position = source.position,
    radius = 0.1
  }[1]

  -- remove storage index and delete beacon
  storage[beacon.unit_number].manager.destroy()
  storage[beacon.unit_number] = nil
  beacon.destroy()
end

script.on_event(defines.events.script_raised_built, on_constructed, event_filter)
script.on_event(defines.events.script_raised_revive, on_constructed, event_filter)
script.on_event(defines.events.on_built_entity, on_constructed, event_filter)
script.on_event(defines.events.on_space_platform_built_entity, on_constructed, event_filter)
script.on_event(defines.events.on_robot_built_entity, on_constructed, event_filter)

script.on_event(defines.events.script_raised_destroy, on_deconstructed, event_filter)
script.on_event(defines.events.on_robot_mined_entity, alt_on_deconstructed, alt_event_filter)
script.on_event(defines.events.on_player_mined_entity, on_deconstructed, event_filter)
script.on_event(defines.events.on_space_platform_mined_entity, on_deconstructed, event_filter)
script.on_event(defines.events.on_entity_died, alt_on_deconstructed, alt_event_filter)

-- do other stuff when a source is marked for deconstruction (it will be marked instead of the beacon)
script.on_event(defines.events.on_marked_for_deconstruction, function (event)
  -- make sure its one of our entities
  if not prototypes.entity[event.entity.name:sub(1,-8)] then return end
  local source = event.entity
  -- get our storage data
  local beacon = source.surface.find_entities_filtered{
    name = source.name:sub(1,-8),
    position = source.position,
    radius = 0.1
  }[1]

  -- copy modules over to the assembler for them to be 'removed'
  for _, item_stack in pairs(beacon.get_module_inventory().get_contents()) do
    source.get_module_inventory().insert(item_stack)
    beacon.get_module_inventory().remove(item_stack)
  end

  -- 'disable' the beacon and save the current status to storage
  storage[beacon.unit_number][3] = beacon.custom_status
  beacon.disabled_by_script = true
  beacon.custom_status = {
    diode = defines.entity_status_diode.red,
    label = {"entity-status.marked-for-deconstruction"}
  }

end, {{filter = "type", type = "assembling-machine"}})

script.on_event(defines.events.on_cancelled_deconstruction, function (event)
  -- make sure its one of our entities
  if not prototypes.entity[event.entity.name:sub(1,-8)] then return end
  local source = event.entity
  -- get our storage data
  local beacon = source.surface.find_entities_filtered{
    name = source.name:sub(1,-8),
    position = source.position,
    radius = 0.1
  }[1]

  -- move modules back to the beacon, if they're there
  for _, item_stack in pairs(source.get_module_inventory().get_contents()) do
    beacon.get_module_inventory().insert(item_stack)
    source.get_module_inventory().remove(item_stack)
  end

  -- reenable the beacon and restore the previous status
  beacon.custom_status = storage[beacon.unit_number][3]
  beacon.disabled_by_script = false

end, {{filter = "type", type = "assembling-machine"}})

-- editor mode when in instant deconstruct never registers that entities are deconstructed so i have to remove invalid references
--- @param event EventData.on_player_deconstructed_area
script.on_event(defines.events.on_player_deconstructed_area, function (event)
  -- quit if alt-deconstructing, or if non-editor (cause editor is the reason this handler exists)
  if event.alt or game.players[event.player_index].controller_type ~= defines.controllers.editor then return end
  -- recreate deconstruction logic cause... reasons
  count = event.surface.count_entities_filtered{
    area = event.area,
    quality = event.quality,
    type = "beacon"
  }

  if count ~= 0 then
    for index, metadata in pairs(storage) do
      if index ~= "deathrattles" and (not metadata.beacon.valid or not metadata.source.valid or not metadata.manager.valid) then
        if metadata.beacon.valid then metadata.beacon.destroy() end
        if metadata.source.valid then metadata.source.destroy() end
        if metadata.manager.valid then metadata.manager.destroy() end
        storage[index] = nil
      end
    end
  end
end)