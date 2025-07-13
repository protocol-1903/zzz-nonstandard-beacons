if not storage.previous_version or storage.previous_version == script.active_mods["zzz-nonstandard-beacons"] then return end
for index, metadata in pairs(storage) do
  local beacon = metadata[1]
  local source = metadata[2]

  if beacon.valid and source.valid then
    storage[index] = nil
    local manager = beacon.surface.create_entity{
      name = "nsb-internal-manager",
      position = beacon.position,
      force = beacon.force
    }
    
    storage[index] = {beacon = beacon, source = source, manager = manager}
  else
    if beacon.valid then beacon.destroy() end
    if source.valid then source.destroy() end
    storage[index] = nil
  end
end