for index, metadata in pairs(storage) do
  if index ~= "deathrattles" then
    if metadata.source.to_be_deconstructed then
      beacon = metadata.beacon
      source = metadata.source

      -- move modules back to the beacon
      for _, item_stack in pairs(source.get_module_inventory().get_contents()) do
        beacon.get_module_inventory().insert(item_stack)
        source.get_module_inventory().remove(item_stack)
      end

      source.cancel_deconstruction(source.force)
      source.disabled_by_script = true
    end
  end
end