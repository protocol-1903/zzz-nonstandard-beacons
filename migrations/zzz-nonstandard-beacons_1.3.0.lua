if not storage.previous_version or storage.previous_version == script.active_mods["zzz-nonstandard-beacons"] then return end
-- changes to storage structure, nothing major
local deathrattles = storage.deathrattles
local beacons = storage
beacons.deathrattles = nil
_G.storage = {
  beacons = beacons,
  deathrattles = deathrattles
}