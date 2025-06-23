for index, metadata in pairs(storage) do
  if index ~= "deathrattles" then
    if metadata.source.to_be_deconstructed() then
      beacon = metadata.beacon
      source = metadata.source

      -- move modules back to the beacon
      for _, item_stack in pairs(source.get_module_inventory().get_contents()) do
        beacon.get_module_inventory().insert(item_stack)
        source.get_module_inventory().remove(item_stack)
      end

      beacon.order_deconstruction(beacon.force)

      local source_2 = source.surface.create_entity{
        name = beacon.name .. "-source",
        position = beacon.position,
        force = beacon.force
      }

      -- connect source and manager
      metadata.manager.get_wire_connector(defines.wire_connector_id.circuit_green, true).connect_to(source_2.get_wire_connector(defines.wire_connector_id.circuit_green, true), false, defines.wire_origin.script)

      -- set circuit settings
      local source_behaviour = source_2.get_or_create_control_behavior()

      source_behaviour.circuit_read_working = true
      source_behaviour.circuit_working_signal = {type = "item", name = "nsb-internal-item"}

      if source.prototype.heat_energy_source_prototype then
        source_2.temperature = source.temperature
      elseif source.prototype.fluid_energy_source_prototype then
        source_2.fluidbox[1] = source.fluidbox[1]
      else -- must be a burner
        source_2.get_fuel_inventory().insert{
          name = source.get_fuel_inventory()[1].name,
          count = source.get_fuel_inventory()[1].count,
          quality = source.get_fuel_inventory()[1].quality
        }
      end

      source.destroy()
      source_2.disabled_by_script = true
      metadata.source = source_2
    end
  end
end