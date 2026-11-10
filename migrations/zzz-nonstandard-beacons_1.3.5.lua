-- Retained as historical source, never replayed under Factorio 2.1. Adding this
-- mod to an existing save also runs every migration filename; that is a valid
-- fresh installation. The configuration event checks its authoritative old_version
-- before the runtime converter accepts an actual historical upgrade.
if script.active_mods.base:match("^2%.1%.") then return end

storage.force_migrations = true
