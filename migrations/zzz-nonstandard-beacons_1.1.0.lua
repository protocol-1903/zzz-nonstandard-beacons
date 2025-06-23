for index, metadata in pairs(storage) do
  local beacon = metadata[1]
  local source = metadata[2]
  storage[index] = nil
  local manager = beacon.surface.create_entity{
    name = "nsb-internal-manager",
    position = beacon.position,
    force = beacon.force
  }
  
  storage[index] = {beacon = beacon, source = source, manager = manager}
end