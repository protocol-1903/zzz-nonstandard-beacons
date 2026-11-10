-- Retained as historical source, never replayed under Factorio 2.1. Adding this
-- mod to an existing save also runs every migration filename; that is a valid
-- fresh installation. The configuration event checks its authoritative old_version
-- before the runtime converter accepts an actual historical upgrade.
if script.active_mods.base:match("^2%.1%.") then return end

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
