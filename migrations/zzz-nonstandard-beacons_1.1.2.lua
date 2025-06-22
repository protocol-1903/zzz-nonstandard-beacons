for index, metadata in pairs(storage) do
  if index ~= "deathrattles" then
    local manager = metadata.beacon.surface.create_entity{
      name = "nsb-internal-manager",
      position = metadata.beacon.position,
      force = metadata.beacon.force
    }

    metadata.manager.destroy()

    -- connect source and manager
    manager.get_wire_connector(defines.wire_connector_id.circuit_green, true).connect_to(metadata.source.get_wire_connector(defines.wire_connector_id.circuit_green, true), false, defines.wire_origin.script)

    -- set circuit settings
    local source_behaviour = metadata.source.get_or_create_control_behavior()
    local manager_behaviour = manager.get_or_create_control_behavior()

    source_behaviour.circuit_read_working = true
    source_behaviour.circuit_working_signal = {type = "item", name = "nsb-internal-item"}
    manager_behaviour.circuit_enable_disable = true
    local to_be_enabled = metadata.source.status == defines.entity_status.working
    manager.get_or_create_control_behavior().circuit_condition = {
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

    manager.get_inventory(defines.inventory.crafter_input).insert{
      name = "nsb-internal-item",
      count = 1,
      health = 0.5,
    }
    storage.deathrattles[script.register_on_object_destroyed(manager.get_inventory(defines.inventory.crafter_input)[1].item)] = {beacon = metadata.beacon, source = metadata.source, manager = manager}
    storage[index].manager = manager
  end
end