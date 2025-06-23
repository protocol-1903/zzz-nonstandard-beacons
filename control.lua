local event_filter = {}
local deconstruction_event_filter = {}

for _, prototype in pairs(prototypes.entity) do
  if prototype.type == "beacon" and prototypes.entity[prototype.name .. "-source"] then
    event_filter[#event_filter+1] = {filter = "name", name = prototype.name}
    deconstruction_event_filter[#deconstruction_event_filter+1] = prototype.name
  end
end

script.on_init(function (event)
  storage.deathrattles = {}
end)

script.on_configuration_changed(function (event)
  storage.deathrattles = storage.deathrattles or {}
end)

local function register_sacrifice(beacon, source, manager)
  manager.get_inventory(defines.inventory.crafter_input).insert{
    name = "nsb-internal-item",
    count = 1,
    health = 0.5,
  }
  storage.deathrattles[script.register_on_object_destroyed(manager.get_inventory(defines.inventory.crafter_input)[1].item)] = {beacon = beacon, source = source, manager = manager}
end

script.on_event(defines.events.on_object_destroyed, function(event)
  metadata = storage.deathrattles[event.registration_number]
  if not metadata then return end
  storage.deathrattles[event.registration_number] = nil

  -- something got removed, do nothing
  if not metadata.beacon.valid or not metadata.source.valid or not metadata.manager.valid then return end

  -- invert control behaviour
  to_be_enabled = metadata.source.status == defines.entity_status.working
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
    metadata.beacon.custom_status = nil -- clear custom status
  else
    metadata.beacon.disabled_by_script = true
    metadata.beacon.custom_status = { -- add custom status to reflect source status
      diode = defines.entity_status_diode.red,
      label = metadata.beacon.to_be_deconstructed() and {"entity-status.marked-for-deconstruction"} or {metadata.source.prototype.localised_description}
    }
  end

  register_sacrifice(metadata.beacon, metadata.source, metadata.manager)
end)

--- @param event EventData.on_built_entity|EventData.on_robot_built_entity|EventData.on_space_platform_built_entity|EventData.script_raised_built|EventData.script_raised_revive|EventData.on_cancelled_deconstruction
local function on_created(event)
  beacon = event.entity

  source = beacon.surface.create_entity{
    name = beacon.name .. "-source",
    position = beacon.position,
    force = beacon.force
  }

  manager = beacon.surface.create_entity{
    name = "nsb-internal-manager",
    position = beacon.position,
    force = beacon.force
  }

  -- connect source and manager
  manager.get_wire_connector(defines.wire_connector_id.circuit_green, true).connect_to(source.get_wire_connector(defines.wire_connector_id.circuit_green, true), false, defines.wire_origin.script)

  -- set circuit settings
  source_behaviour = source.get_or_create_control_behavior()
  manager_behaviour = manager.get_or_create_control_behavior()

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

--- @param event EventData.on_player_mined_entity|EventData.on_robot_mined_entity|EventData.on_space_platform_mined_entity|EventData.script_raised_destroy|EventData.on_entity_died
local function on_destroyed(event)
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

  -- delete source entity
  storage[event.entity.unit_number].source.destroy()
  storage[event.entity.unit_number].manager.destroy()

  -- remove storage index
  storage[event.entity.unit_number] = nil
end

script.on_event(defines.events.on_built_entity, on_created, event_filter)
script.on_event(defines.events.on_robot_built_entity, on_created, event_filter)
script.on_event(defines.events.on_space_platform_built_entity, on_created, event_filter)
script.on_event(defines.events.script_raised_built, on_created, event_filter)
script.on_event(defines.events.script_raised_revive, on_created, event_filter)

script.on_event(defines.events.on_player_mined_entity, on_destroyed, event_filter)
script.on_event(defines.events.on_robot_mined_entity, on_destroyed, alt_event_filter)
script.on_event(defines.events.on_space_platform_mined_entity, on_destroyed, event_filter)
script.on_event(defines.events.script_raised_destroy, on_destroyed, event_filter)
script.on_event(defines.events.on_entity_died, on_destroyed, alt_event_filter)

-- disable the source if marked for deconstruction
script.on_event(defines.events.on_marked_for_deconstruction, function (event)
  storage[event.entity.unit_number].source.disabled_by_script = true
end, event_filter)

-- enable the source if cancelled deconstruction
script.on_event(defines.events.on_cancelled_deconstruction, function (event)
  storage[event.entity.unit_number].source.disabled_by_script = false
end, event_filter)

--- @param event EventData.on_player_deconstructed_area
script.on_event(defines.events.on_player_deconstructed_area, function (event)
  -- quit if alt-deconstructing, or if non-editor (cause editor is the reason this handler exists)
  if event.alt or game.players[event.player_index].controller_type ~= defines.controllers.editor then return end
  -- recreate deconstruction logic cause... reasons
  count = event.surface.count_entities_filtered{
    area = event.area,
    quality = event.quality,
    type = "beacon",
    name = deconstruction_event_filter
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