-- Retained as historical source, never replayed under Factorio 2.1. Adding this
-- mod to an existing save also runs every migration filename; that is a valid
-- fresh installation. The configuration event checks its authoritative old_version
-- before the runtime converter accepts an actual historical upgrade.
if script.active_mods.base:match("^2%.1%.") then return end

if not storage.previous_version or storage.previous_version == script.active_mods["zzz-nonstandard-beacons"] then return end
-- changes to storage structure, nothing major
local deathrattles = storage.deathrattles
local beacons = storage
beacons.deathrattles = nil
_G.storage = {
  beacons = beacons,
  deathrattles = deathrattles
}
