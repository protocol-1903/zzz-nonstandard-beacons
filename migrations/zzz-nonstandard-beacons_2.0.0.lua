storage.deathrattles = nil
storage.custom_beacon_prototypes = storage.modded_beacons or {}
for index, value in pairs(storage.custom_beacon_prototypes) do
  storage.custom_beacon_prototypes[index] = {uses_module_effects = value}
end
storage.modded_beacons = nil